// swift-tools-version: 6.0
import PackageDescription

// ─────────────────────────────────────────────────────────────────────────────
//  Architecture
//
//  Dependencies point inwards. A layer may depend on the layers above it in
//  this list, never below:
//
//    Core        StoryboardCore — parsing, animation resolution, types.
//                No platform frameworks, so it is testable without a GPU or a
//                window. This is the layer that must stay clean.
//
//    Platform    StoryboardShaderTypes, StoryboardRendering, DesignSystem.
//                Talks to Metal, AppKit and SwiftUI on the core's behalf.
//
//    Features    PlaybackFeature, and later Scripting, Exporting, …
//                One vertical slice per product capability: its own domain
//                logic, its own UI, its own tests. Features never import each
//                other — when two need to share, the shared part belongs in
//                Core behind a protocol.
//
//    Apps        RendererHarness today; the shipping app later.
//                Composition only: windows, menus, wiring.
// ─────────────────────────────────────────────────────────────────────────────

let package = Package(
    name: "AnimateEditor",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "StoryboardCore", targets: ["StoryboardCore"]),
        .library(name: "StoryboardRendering", targets: ["StoryboardRendering"]),
        .library(name: "StoryboardPersistence", targets: ["StoryboardPersistence"]),
        .library(name: "StoryboardScripting", targets: ["StoryboardScripting"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "PlaybackFeature", targets: ["PlaybackFeature"]),
        .library(name: "ProjectBrowserFeature", targets: ["ProjectBrowserFeature"]),
        .library(name: "EditorShellFeature", targets: ["EditorShellFeature"]),
        .executable(name: "AnimateEditor", targets: ["AnimateEditorApp"]),
        .executable(name: "RendererHarness", targets: ["RendererHarness"]),
        .executable(name: "DesignSystemGallery", targets: ["DesignSystemGallery"]),
    ],
    dependencies: [],
    targets: [
        // ── Core ────────────────────────────────────────────────────────────
        .target(
            name: "StoryboardCore",
        ),

        // Helpers two test targets need and neither can own: placing a preset
        // the way the editor does, and the overlap guard. A target rather than
        // a copy in each, because two copies drift; and not inside
        // `StoryboardCore`, which ships. Depends on Core alone — a Core test
        // reaching `StoryboardScripting` would invert the rule `Package.swift`
        // exists to enforce.
        .target(
            name: "StoryboardTestSupport",
            dependencies: ["StoryboardCore"],
        ),
        .testTarget(
            name: "StoryboardCoreTests",
            dependencies: ["StoryboardCore", "StoryboardTestSupport"],
            resources: [.copy("Fixtures")],
        ),

        // ── Platform ────────────────────────────────────────────────────────

        // C struct definitions shared between Swift and the Metal shaders, so
        // both sides agree on memory layout.
        .target(
            name: "StoryboardShaderTypes",
        ),

        // `Shaders.metal` is copied verbatim, not compiled: SwiftPM has no Metal
        // compilation step, so the renderer builds the library from source at
        // startup. See MetalStoryboardRenderer.makeLibrary(device:).
        .target(
            name: "StoryboardRendering",
            dependencies: ["StoryboardCore", "StoryboardShaderTypes", "PixelKernels"],
            resources: [.copy("Shaders.metal"), .copy("Particles")],
        ),
        // Per-pixel loops for the derived Look textures, optimised even in a
        // debug build: unoptimised Swift ran Ink on a full-HD image in 3.2s
        // against 70ms, on the main thread. Depends on nothing, so turning
        // the optimiser on here touches nothing else's debugging.
        .target(
            name: "PixelKernels",
            swiftSettings: [.unsafeFlags(["-O"], .when(configuration: .debug))],
        ),
        .testTarget(
            name: "PixelKernelsTests",
            dependencies: ["PixelKernels"],
        ),
        .testTarget(
            name: "StoryboardRenderingTests",
            dependencies: ["StoryboardRendering", "StoryboardShaderTypes"],
            resources: [.copy("../../Sources/StoryboardRendering/Shaders.metal")],
        ),

        // Reading beatmap folders and remembering which ones were opened.
        .target(
            name: "StoryboardPersistence",
            dependencies: ["StoryboardCore"],
        ),
        .testTarget(
            name: "StoryboardPersistenceTests",
            dependencies: ["StoryboardPersistence"],
            resources: [.copy("Fixtures")],
        ),
        .testTarget(
            name: "ProjectBrowserFeatureTests",
            dependencies: ["ProjectBrowserFeature"],
        ),

        // The code editor: highlighting, line numbers, bracket matching.
        //
        // Running author-written scripts on JavaScriptCore.
        //
        // Platform, not a feature: it has no UI, and it talks to a framework on
        // the core's behalf exactly as the renderer talks to Metal. Core
        // declares what it needs and this target provides it, so the core's
        // tests still run with no JS engine involved.
        .target(
            name: "StoryboardScripting",
            dependencies: ["StoryboardCore"],
        ),
        .testTarget(
            name: "StoryboardScriptingTests",
            dependencies: ["StoryboardScripting", "StoryboardCore", "StoryboardTestSupport"],
        ),

        .target(
            name: "DesignSystem",
            // Geist and its OFL licence; registered at launch by
            // `Theme.registerFonts()`.
            resources: [.process("Fonts")],
        ),

        // ── Features ────────────────────────────────────────────────────────
        .target(
            name: "PlaybackFeature",
            dependencies: [
                "StoryboardCore",
                "StoryboardRendering",
                "StoryboardPersistence",
                "DesignSystem",
            ],
        ),
        .testTarget(
            name: "DesignSystemTests",
            dependencies: ["DesignSystem"],
        ),

        .testTarget(
            name: "PlaybackFeatureTests",
            dependencies: ["PlaybackFeature", "StoryboardCore", "StoryboardPersistence"],
        ),

        .target(
            name: "ProjectBrowserFeature",
            dependencies: ["StoryboardPersistence", "DesignSystem"],
        ),

        // Arrangement only: panels, rail, track timeline. The canvas and
        // transport are injected, so this target knows nothing about rendering
        // or playback.
        .target(
            name: "EditorShellFeature",
            dependencies: ["StoryboardCore", "DesignSystem"],
        ),
        .testTarget(
            name: "EditorShellFeatureTests",
            dependencies: ["EditorShellFeature", "StoryboardCore", "StoryboardScripting"],
        ),

        // ── Apps ────────────────────────────────────────────────────────────

        // The shipping app. Composition only: it wires features together and
        // owns the window.
        .executableTarget(
            name: "AnimateEditorApp",
            dependencies: [
                "PlaybackFeature",
                "ProjectBrowserFeature",
                "EditorShellFeature",
                // The app installs the scripting runtime into the core's
                // seam, which is why no feature needs to know it exists.
                "StoryboardScripting",
                // Declared although `PlaybackFeature` already brings it: this
                // target imports it directly, and an undeclared import
                // compiles only because another target's artefacts happen to
                // be in `.build`. That is the accident CI caught the first
                // time it ran, when a Core test reached a feature and passed
                // locally for the same reason.
                "StoryboardPersistence",
            ],
            // The Dock icon. Without a bundle there is no `Info.plist` to name
            // one, so `main.swift` hands it to AppKit at launch.
            resources: [.copy("Resources/AppIcon.png")],
        ),

        // Development harness: runs the renderer against a generated storyboard
        // so rendering work needs no beatmap folder on disk.
        .executableTarget(
            name: "RendererHarness",
            dependencies: ["StoryboardCore", "StoryboardRendering", "PlaybackFeature"],
        ),

        // Every component on one screen, so the system can be reviewed as a
        // whole. Inconsistencies between two controls are invisible while each
        // one is only ever seen in its own corner of the app.
        .executableTarget(
            name: "DesignSystemGallery",
            // The features too, for their composed components: a clip block or
            // a poster card is where the tokens meet the domain, and judging the
            // tokens without them is judging half the system. A leaf
            // executable, like the app, so nothing depends back on it.
            //
            // And the renderer, for real previews: cards judged against frames
            // the app never shows are cards judged against nothing.
            dependencies: [
                "DesignSystem", "EditorShellFeature", "ProjectBrowserFeature",
                "StoryboardCore", "StoryboardRendering",
            ],
        ),
    ],
)
