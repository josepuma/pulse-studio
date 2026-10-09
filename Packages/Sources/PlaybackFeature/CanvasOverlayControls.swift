import DesignSystem
import SwiftUI

/// Playback controls floating over the canvas, revealed on hover.
///
/// Keeping them on the canvas rather than in a bar below leaves the whole
/// bottom of the window to the timeline, and matches how video editors present
/// preview controls.
struct CanvasOverlayControls: View {
    /// Whether the space bar should reach play/pause.
    ///
    /// A named function rather than an inline `guard` so it can be asserted:
    /// a SwiftUI `keyboardShortcut` cannot be fired from a test, so the
    /// decision has to be reachable on its own or it is untested.
    static func shouldToggleOnSpace(whileEditing isEditing: Bool) -> Bool {
        !isEditing
    }

    @Bindable var model: PlaybackModel

    /// The "view through camera" switch, when the shell offers one.
    var cameraView: CameraViewSwitch?

    var body: some View {
        HStack(spacing: Theme.Spacing.compact) {
            aspectRatio
            transport
            tools
        }
    }

    // ─── Groups ──────────────────────────────────────────────────────────────

    /// Switches the stage between the wide and narrow frames.
    ///
    /// A button rather than a `Menu`: on macOS a menu is an AppKit control
    /// underneath, and an AppKit view ignores the `.opacity` SwiftUI applies to
    /// its container — it draws straight through, so the pill stayed visible
    /// with the controls hidden and dragged the whole row into view with it.
    /// With two states there is nothing to choose from anyway.
    private var aspectRatio: some View {
        Button {
            model.isWidescreen.toggle()
        } label: {
            HStack(spacing: Theme.Spacing.tight) {
                Text(model.isWidescreen ? "16 : 9" : "4 : 3")
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Palette.secondary)

                // Marked when it disagrees with the beatmap, so an override is
                // visible rather than mistaken for what the map asked for.
                if model.isWidescreen != model.beatmapIsWidescreen {
                    Circle()
                        .fill(Theme.Palette.warning)
                        .frame(width: Theme.Spacing.tight, height: Theme.Spacing.tight)
                }
            }
            .padding(.horizontal, Theme.Spacing.compact)
            .frame(height: Theme.Size.pill)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .capsuleSurface(.bar)
        .help(aspectRatioHelp)
    }

    private var aspectRatioHelp: String {
        let target = model.isWidescreen ? "4:3" : "16:9"
        let asAuthored = model.isWidescreen == model.beatmapIsWidescreen

        return asAuthored
            ? "Switch to \(target) — this beatmap was authored for \(model.isWidescreen ? "16:9" : "4:3")"
            : "Switch back to \(target), as the beatmap asks for"
    }

    private var transport: some View {
        HStack(spacing: Theme.Spacing.compact) {
            IconButton(
                systemImage: "backward.fill",
                size: Theme.Size.controlSmall,
                help: "Back 5 seconds",
            ) {
                model.seek(to: model.currentTime - 5000)
            }

            // The primary action gets a ring, as in the reference: it is the
            // one control worth finding without looking.
            Button(action: model.togglePlayback) {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Palette.primary)
                    .frame(width: Theme.Size.control, height: Theme.Size.control)
                    .overlay {
                        Circle().strokeBorder(Theme.Border.handle, lineWidth: Theme.Size.ring)
                    }
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .help(model.isPlaying ? "Pause" : "Play")

            // The space bar, on a button of its own, hidden behind the one
            // above.
            //
            // Separate because the guard belongs to the *shortcut*, not to the
            // action: space is claimed at window level and reaches play/pause
            // while somebody is typing — a one-line field survives that, a code
            // editor does not, since space is the most-typed character in code.
            // Clicking the visible button has to keep working either way, and
            // gating the shared action would have broken that too.
            //
            // Every ⌘ shortcut in the shell already had this guard. The space
            // bar was the one that did not, and it took a code editor for that
            // to matter.
            Button("") {
                guard Self.shouldToggleOnSpace(whileEditing: EditingFocus.isActive) else { return }
                model.togglePlayback()
            }
            .keyboardShortcut(.space, modifiers: [])
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)

            IconButton(
                systemImage: "forward.fill",
                size: Theme.Size.controlSmall,
                help: "Forward 5 seconds",
            ) {
                model.seek(to: model.currentTime + 5000)
            }

            HStack(spacing: Theme.Spacing.tight) {
                Text(model.timecode)
                    .font(Theme.Typography.readout)
                    .foregroundStyle(Theme.Palette.primary)
                Text("/")
                    .font(Theme.Typography.readout)
                    .foregroundStyle(Theme.Palette.tertiary)
                Text(model.durationTimecode)
                    .font(Theme.Typography.readout)
                    .foregroundStyle(Theme.Palette.tertiary)
            }

            ScrubBar(model: model)
                .frame(width: 150)
        }
        .padding(.horizontal, Theme.Spacing.regular)
        .frame(height: Theme.Size.pill)
        .capsuleSurface(.bar)
    }

    /// The speeds offered, in the order they read on a dial.
    ///
    /// Stopping at a quarter and at double: past those the time-stretching
    /// artefacts are louder than the music, so the track stops working as the
    /// reference it is being slowed down to be.
    private static let rates: [Float] = [0.25, 0.5, 0.75, 1, 1.5, 2]

    /// A zoom as a percentage, 100% being the stage fitted to the canvas.
    static func zoomLabel(_ zoom: Double) -> String {
        "\(Int((zoom * 100).rounded()))%"
    }

    /// A rate as it is spoken: `1×`, `0.5×`.
    private static func label(for rate: Float) -> String {
        rate == rate.rounded()
            ? "\(Int(rate))×"
            : "\(String(format: "%g", rate))×"
    }

    private var tools: some View {
        HStack(spacing: Theme.Spacing.compact) {
            // Only while the camera is being edited: anywhere else the canvas
            // already shows the finished picture, and a switch that does
            // nothing is a control that lies.
            if let cameraView, cameraView.isAvailable() {
                let isOn = cameraView.isOn()
                IconButton(
                    systemImage: isOn ? "video.fill" : "video",
                    size: Theme.Size.controlSmall,
                    isActive: isOn,
                    help: isOn
                        ? "Back to the world with the camera frame (⇧⌘C)"
                        : "View through the camera (⇧⌘C)",
                    action: cameraView.toggle,
                )
                // ⇧⌘ rather than a bare key: a bare letter is claimed window
                // wide and would be swallowed out of every field being typed
                // in — the trap the space bar already needed a guard for.
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }

            IconButton(
                systemImage: model.showsGuides ? "grid" : "square.grid.2x2",
                size: Theme.Size.controlSmall,
                help: model.showsGuides ? "Hide guides" : "Show guides",
            ) {
                model.showsGuides.toggle()
            }

            // The map's hit objects over the picture. Part of how the canvas is
            // looked at, like the guides: not saved, not an edit.
            GameplayOverlayControls(model: model)

            // Playback speed, behind the button that was already here for it.
            //
            // A menu rather than a slider: the useful rates are a short list
            // anyone can name — half speed to place a hit, double to scan a
            // section — and a slider turns "half speed" into aiming at 0.5.
            Menu {
                Picker("Speed", selection: Binding(
                    get: { model.rate },
                    set: { model.rate = $0 },
                )) {
                    ForEach(Self.rates, id: \.self) { rate in
                        Text(Self.label(for: rate)).tag(rate)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .frame(width: Theme.Size.controlSmall, height: Theme.Size.controlSmall)
            .help("Playback speed")

            // Zoom, beside full screen: both are about how the canvas is
            // looked at, and neither reaches the storyboard. A menu of named
            // steps rather than a slider, for the reason the speed menu is one.
            Menu {
                ForEach(CanvasViewport.presets, id: \.self) { zoom in
                    Button {
                        model.setCanvasZoom(zoom)
                    } label: {
                        if abs(model.canvasViewport.zoom - zoom) < 0.001 {
                            Label(Self.zoomLabel(zoom), systemImage: "checkmark")
                        } else {
                            Text(Self.zoomLabel(zoom))
                        }
                    }
                }
                Divider()
                Button("Fit") { model.fitCanvas() }
            } label: {
                Text(Self.zoomLabel(model.canvasViewport.zoom))
                    .font(Theme.Typography.micro)
                    .monospacedDigit()
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Canvas zoom — ⌘+ in, ⌘− out, ⌘0 fit. ⌘ and the wheel, or a pinch, zoom at the pointer; the wheel alone pans.")
            .background {
                // The shortcuts, bound here so they live while the controls
                // do. ⌘ rather than bare keys, which would be swallowed out of
                // every field being typed in.
                Group {
                    // Both: on a US keyboard + is ⇧= and ⌘= is the habit; on a
                    // Spanish or Latin American one + has its own key and =
                    // is ⇧0, so ⌘= never arrives — reported as zoom-in not
                    // working from the keyboard.
                    Button("") { model.stepCanvasZoom(in: true) }
                        .keyboardShortcut("=", modifiers: .command)
                    Button("") { model.stepCanvasZoom(in: true) }
                        .keyboardShortcut("+", modifiers: .command)
                    Button("") { model.stepCanvasZoom(in: false) }
                        .keyboardShortcut("-", modifiers: .command)
                    Button("") { model.fitCanvas() }
                        .keyboardShortcut("0", modifiers: .command)
                }
                .opacity(0)
                .allowsHitTesting(false)
            }

            IconButton(
                systemImage: model.isCanvasFullScreen
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right",
                size: Theme.Size.controlSmall,
                help: model.isCanvasFullScreen ? "Exit full screen" : "Full screen",
                action: toggleFullScreen,
            )
            // Escape leaves, as it does everywhere else on the platform: a
            // full-screen view whose only way out is a button that fades with
            // the rest of the controls is a trap. Bound only while full
            // screen, so Escape does not enter it from the editor.
            .modifier(EscapeToExit(isActive: model.isCanvasFullScreen))
        }
        .padding(.horizontal, Theme.Spacing.regular)
        .frame(height: Theme.Size.pill)
        .capsuleSurface(.bar)
    }

}

extension CanvasOverlayControls {
    /// Fills the screen, not just the window.
    ///
    /// Two things at once: the shell drops everything but the picture, and the
    /// window takes over the display. Either alone falls short of what the
    /// control promises — panels around a full-screen window, or a bare canvas
    /// still boxed inside the desktop.
    private func toggleFullScreen() {
        model.isCanvasFullScreen.toggle()

        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }

        if model.isCanvasFullScreen != window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
    }
}

/// Binds Escape only while there is something to escape from.
private struct EscapeToExit: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        if isActive {
            content.keyboardShortcut(.escape, modifiers: [])
        } else {
            content
        }
    }
}

// ─── Scrub bar ───────────────────────────────────────────────────────────────

/// A slim progress bar that seeks on drag.
///
/// A plain `Slider` brings a knob and platform styling that fight the overlay's
/// look, so this draws the two states it needs and nothing more.
private struct ScrubBar: View {
    @Bindable var model: PlaybackModel
    @State private var isHovered = false

    var body: some View {
        GeometryReader { proxy in
            // Measured against the timeline rather than the track: a storyboard
            // that opens before the music would otherwise show negative
            // progress, and one that outlasts it would fill the bar early.
            let range = model.timelineRange
            let span = max(range.upperBound - range.lowerBound, 1)
            let progress = min(max((model.currentTime - range.lowerBound) / span, 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.Fill.groove)

                Capsule()
                    .fill(Theme.Palette.primary)
                    .frame(width: proxy.size.width * progress)
            }
            .frame(height: isHovered ? 6 : 4)
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .onHover { isHovered = $0 }
            .animation(Theme.Motion.quick, value: isHovered)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let ratio = min(max(0, value.location.x / proxy.size.width), 1)
                        model.seek(to: range.lowerBound + ratio * span)
                    },
            )
        }
        .frame(height: Theme.Size.controlTiny)
    }
}

// ─── Volume ──────────────────────────────────────────────────────────────────

/// A vertical volume slider, as the reference places beside the preview.
struct CanvasVolumeControl: View {
    @Bindable var model: PlaybackModel

    @State private var volume: Double = 1
    /// What to restore on unmute, so silencing is reversible rather than a
    /// one-way trip back to full.
    @State private var volumeBeforeMute: Double = 1

    private static let trackLength: CGFloat = 84

    private func toggleMute() {
        if volume > 0 {
            volumeBeforeMute = volume
            volume = 0
        } else {
            volume = volumeBeforeMute > 0 ? volumeBeforeMute : 1
        }
        model.setVolume(Float(volume))
    }

    var body: some View {
        // A row, matching the bar it now sits in. Standing upright made sense
        // floating over a tall canvas; in a horizontal strip it was a column
        // among pills.
        HStack(spacing: Theme.Spacing.compact) {
            IconButton(
                systemImage: volume > 0 ? "speaker.wave.2.fill" : "speaker.slash.fill",
                size: Theme.Size.controlTiny,
                help: volume > 0 ? "Mute" : "Unmute",
                action: toggleMute,
            )

            track
        }
        .padding(.horizontal, Theme.Spacing.regular)
        // Matches the pills beside it, so the row reads as one band.
        .frame(height: Theme.Size.pill)
        .capsuleSurface(.bar)
        .onAppear { volume = Double(model.volume) }
        // Only the mute jump is animated; a drag already follows the pointer,
        // and animating that would make the thumb lag behind it.
        .animation(Theme.Motion.quick, value: volume == 0)
    }

    /// A capsule track with a pill thumb, drawn rather than built from `Slider`
    /// so it matches the overlay instead of the platform's control styling.
    private var track: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let thumbWidth: CGFloat = 18
            let travel = width - thumbWidth

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.Fill.groove)
                    .frame(height: Theme.Size.grooveThickness)
                    .frame(maxHeight: .infinity)

                Capsule()
                    .fill(.white)
                    .frame(width: thumbWidth, height: Theme.Size.playheadHandleWidth)
                    .offset(x: travel * volume)
                    .elevated(Theme.Elevation.low)
            }
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let position = (value.location.x - thumbWidth / 2) / travel
                        volume = min(max(0, position), 1)
                        model.setVolume(Float(volume))
                    },
            )
        }
        .frame(width: Self.trackLength, height: Theme.Size.controlTiny)
    }
}

/// The seam for switching the canvas between the world and the camera's view.
///
/// Three closures rather than values, like every seam into the shell on this
/// canvas: read as values up the tree, they would rebuild the window on every
/// change.
public struct CameraViewSwitch {
    public let isAvailable: () -> Bool
    public let isOn: () -> Bool
    public let toggle: () -> Void

    public init(isAvailable: @escaping () -> Bool, isOn: @escaping () -> Bool, toggle: @escaping () -> Void) {
        self.isAvailable = isAvailable
        self.isOn = isOn
        self.toggle = toggle
    }
}
