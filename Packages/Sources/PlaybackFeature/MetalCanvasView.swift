import MetalKit
import StoryboardCore
import StoryboardRendering
import SwiftUI

/// Hosts the Metal renderer inside SwiftUI and drives it from the display link.
struct MetalCanvasView: NSViewRepresentable {
    let model: PlaybackModel
    let source: any StoryboardSource
    /// The widest drawable to render, in pixels; `nil` draws at full backing
    /// resolution, which is what the editor wants. See `CappedDrawable`.
    var maximumPixelWidth: CGFloat? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, source: source)
    }

    func makeNSView(context: Context) -> MTKView {
        let view: MTKView = maximumPixelWidth.map { CappedMTKView(maximumWidth: $0) } ?? MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        // Plain `bgra8Unorm`, not the `_srgb` variant.
        //
        // osu! composites its storyboards in gamma space — sprite colours are
        // blended as the bytes stand, without a conversion to linear light and
        // back. Declaring sRGB here makes the GPU do that conversion, which is
        // more correct in the abstract and wrong for matching what the artwork
        // was drawn against: overlaps darken and edges pick up a fringe.
        view.colorPixelFormat = .bgra8Unorm
        // osu! composites a storyboard over black, and anything else tints
        // every partly transparent sprite.
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.preferredFramesPerSecond = 60

        // Dropped while a scroll is running, and back to 60 when it settles.
        //
        // A scroll anywhere in the window makes AppKit recompose it, and with a
        // Metal layer inside that costs the canvas twelve times what a quiet
        // frame does — measured, 6ms against 0.5ms. Neither number is over
        // budget on its own; together with the scroll they are, and the panel
        // stutters.
        //
        // Verified by pausing the canvas outright: the scroll went smooth at
        // once, which is what a minute of switching something off answers and
        // five rounds of instrumenting did not.
        //
        // Half rate for as long as a hand is on the wheel, which is what every
        // video editor does while you navigate. Half rather than a third:
        // thirty still reads as motion, and twenty is visibly a slideshow —
        // the point is to take pressure off the scroll, not to make the preview
        // look broken while it does.
        NotificationCenter.default.addObserver(
            forName: NSScrollView.willStartLiveScrollNotification,
            object: nil,
            queue: .main,
        ) { [weak view] _ in
            MainActor.assumeIsolated { view?.preferredFramesPerSecond = 30 }
        }
        NotificationCenter.default.addObserver(
            forName: NSScrollView.didEndLiveScrollNotification,
            object: nil,
            queue: .main,
        ) { [weak view] _ in
            MainActor.assumeIsolated { view?.preferredFramesPerSecond = 60 }
        }
        view.delegate = context.coordinator
        context.coordinator.configure(view: view)

        // The export shares this renderer rather than building a second: the
        // atlas is tens of megabytes and its sprites are already uploaded.
        model.writeVideo = { [weak coordinator = context.coordinator, weak view] url, range, progress in
            guard let renderer = coordinator?.rendererForExport,
                  let device = view?.device
            else { return }
            try await VideoExport(renderer: renderer, device: device)
                .write(range: range, to: url, audio: model.trackURL, progress: progress)
        }

        return view
    }

    func updateNSView(_: MTKView, context: Context) {
        context.coordinator.setWidescreen(model.isWidescreen)
    }

    /// Owns the renderer and advances the clock once per frame.
    @MainActor
    final class Coordinator: NSObject, MTKViewDelegate {
        private let model: PlaybackModel
        private let source: any StoryboardSource
        private var renderer: MetalStoryboardRenderer?

        /// The renderer, for an export to draw frames with.
        ///
        /// Sharing the editor's rather than building a second: the atlas is
        /// tens of megabytes and its sprites are already uploaded.
        var rendererForExport: MetalStoryboardRenderer? { renderer }
        private var lastFrameTimestamp: CFTimeInterval?
        private var smoothedFPS: Double = 60
        /// The sprite revision already on the GPU.
        private var uploadedRevision: Int?

        init(model: PlaybackModel, source: any StoryboardSource) {
            self.model = model
            self.source = source
        }

        /// Loads the storyboard, keeping the window responsive while it does.
        ///
        /// Parsing a `.osb` and resolving its commands is seconds of work on a
        /// real beatmap, so it runs off the main thread; only the texture
        /// upload has to stay, because the renderer owns GPU resources and is
        /// main-actor bound.
        func configure(view: MTKView) {
            guard let device = view.device else {
                model.contentFailed("No Metal device available.")
                return
            }

            model.contentLoading()

            let source = source
            Task { [weak self] in
                do {
                    let sprites = try await Task.detached(priority: .userInitiated) {
                        try source.loadSprites()
                    }.value

                    guard let self else { return }

                    let renderer = try MetalStoryboardRenderer(
                        device: device,
                        pixelFormat: view.colorPixelFormat,
                    )
                    try renderer.setSprites(sprites) { path in
                        Self.imageData(for: path, source: source).map { .data($0) }
                    }

                    renderer.isWidescreen = model.isWidescreen
                    self.renderer = renderer
                    model.hitTester = { [weak renderer] point, owner in
                        renderer?.clip(at: point, owner: owner)
                    }
                    // Names only: no hit object is parsed until the overlay
                    // is first switched on.
                    model.connectGameplay(
                        difficulties: source.gameplayDifficulties,
                        defaultPath: source.defaultGameplayDifficultyPath,
                        loader: { path in source.loadGameplay(path: path) },
                    )
                    model.contentLoaded(
                        name: source.displayName,
                        sprites: sprites,
                        duration: StoryboardResolver.duration(of: sprites),
                        audioURL: source.audioURL,
                        timing: source.timing,
                        missingImagePaths: source.missingImagePaths,
                    )
                } catch {
                    self?.model.contentFailed("\(error)")
                }
            }
        }

        /// Resolves a sprite path to image data, wherever it comes from.
        ///
        /// Three places, in order. A *derived* path is made on demand — a glow's
        /// blurred copy of some other sprite — and it needs the resolver itself
        /// to find its source, which is why this is one function rather than a
        /// chain of `??`. A *built-in* is an image the app ships, because an
        /// effect has to draw something before any file has been chosen. Failing
        /// both, the beatmap's own folder.
        static func imageData(for path: String, source: any StoryboardSource) -> Data? {
            if DerivedSprite.isDerived(path) {
                return DerivedTextures.data(for: path) { original in
                    imageData(for: original, source: source)
                }
            }
            return TextTextures.data(for: path)
                ?? BuiltInTextures.data(for: path)
                ?? source.imageData(for: path)
        }

        func setWidescreen(_ isWidescreen: Bool) {
            renderer?.isWidescreen = isWidescreen
        }

        /// Uploads the model's sprites when they differ from what the GPU holds.
        ///
        /// Guarded by a revision rather than by comparing the arrays: a real
        /// beatmap carries thousands of sprites, and this runs on every SwiftUI
        /// update.
        func syncSprites() {
            guard let renderer, uploadedRevision != model.spritesRevision else { return }
            uploadedRevision = model.spritesRevision

            let source = source
            do {
                try renderer.setSprites(model.sprites) { path in
                    Self.imageData(for: path, source: source).map { .data($0) }
                }
                // On the frame these are drawn, so a released drag preview
                // and the sprites that commit it swap without a gap.
                model.spritesUploaded(revision: model.spritesRevision)
            } catch {
                model.contentFailed("\(error)")
            }
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            // Checked here rather than from `updateNSView`, which only runs
            // when SwiftUI re-evaluates this view — and it has no reason to,
            // since nothing in the view's own body reads the revision. The
            // display link is already running, and the check is one integer
            // comparison per frame.
            syncSprites()

            let now = CACurrentMediaTime()
            if let last = lastFrameTimestamp {
                let delta = now - last
                if delta > 0 {
                    smoothedFPS = smoothedFPS * 0.9 + (1 / delta) * 0.1
                }
                model.advance(by: delta * 1000)
            }
            lastFrameTimestamp = now

            guard let renderer else { return }
            renderer.measuredClipIDs = model.selectedClipIDs
            // The part of the canvas the view shows. The view fills the whole
            // space the canvas has, so even fitted this reaches past the
            // stage on one axis — the letterbox shows what is there, dimmed.
            renderer.visibleArea = model.canvasViewport
                .layout(container: view.bounds.size, stage: model.canvasStageSize)
                .visible
            renderer.hoveredClipID = model.hoveredClipID
            renderer.preview = model.clipPreview
            // The one place the renderer learns of the overlay. Set here, on
            // the display link, so exports and previews — which never pass
            // through `draw(in:)` — cannot see it; nil when off, so the
            // renderer builds and draws nothing.
            renderer.gameplay = model.showsGameplayOverlay ? model.gameplayMap : nil
            renderer.draw(at: model.currentTime, in: view)
            model.frameRendered(
                drawnCount: renderer.lastDrawnCount,
                framesPerSecond: smoothedFPS,
                selectionBounds: renderer.measuredBounds,
                hoverBounds: renderer.hoveredBounds,
            )
        }
    }
}



/// The drawable size for a view whose resolution is capped.
///
/// Scaled down as a whole, so the stage keeps its shape and the layer stretches
/// it back over the view: behind a scrim and a fade, a trailer at a third of
/// the pixels reads the same and costs the GPU a fraction of the fill.
enum CappedDrawable {
    static func size(bounds: CGSize, scale: CGFloat, maximumWidth: CGFloat) -> CGSize {
        let full = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let factor = full.width > maximumWidth ? maximumWidth / full.width : 1
        return CGSize(
            width: max(1, (full.width * factor).rounded()),
            height: max(1, (full.height * factor).rounded()),
        )
    }
}

/// An `MTKView` that sizes its own drawable instead of matching the backing.
///
/// `autoResizeDrawable` off, so MetalKit stops resetting the size to the
/// window's full resolution on every layout.
final class CappedMTKView: MTKView {
    private let maximumWidth: CGFloat

    init(maximumWidth: CGFloat) {
        self.maximumWidth = maximumWidth
        super.init(frame: .zero, device: nil)
        autoResizeDrawable = false
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layout() {
        super.layout()
        resizeDrawable()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        resizeDrawable()
    }

    private func resizeDrawable() {
        let size = CappedDrawable.size(
            bounds: bounds.size,
            scale: window?.backingScaleFactor ?? 2,
            maximumWidth: maximumWidth,
        )
        if drawableSize != size { drawableSize = size }
    }
}
