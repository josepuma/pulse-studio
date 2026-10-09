import DesignSystem
import SwiftUI

/// The canvas controls for the gameplay overlay: a switch, and once it is on,
/// which difficulty's hit objects to show.
///
/// Absent when the source has no difficulty to read — a switch that can turn
/// nothing on is a control that lies. Takes the model and nothing else, and
/// never the clock: the overlay is drawn by the canvas on its own frames, so
/// nothing here has a reason to rebuild at 60 Hz.
struct GameplayOverlayControls: View {
    let model: PlaybackModel

    var body: some View {
        if !model.gameplayDifficulties.isEmpty {
            HStack(spacing: Theme.Spacing.compact) {
                IconButton(
                    systemImage: model.showsGameplayOverlay ? "circle.circle.fill" : "circle.circle",
                    size: Theme.Size.controlSmall,
                    isActive: model.showsGameplayOverlay,
                    help: model.showsGameplayOverlay
                        ? "Hide the gameplay overlay (⇧⌘G)"
                        : "Show the map's hit objects over the storyboard (⇧⌘G)",
                ) {
                    model.showsGameplayOverlay.toggle()
                }
                // ⇧⌘ rather than a bare key, for the reason ⇧⌘C is: a bare
                // letter is claimed window wide and would be swallowed out of
                // every field being typed in.
                .keyboardShortcut("g", modifiers: [.command, .shift])

                if model.showsGameplayOverlay {
                    difficultyMenu
                }
            }
        }
    }

    /// A menu of named difficulties, like the speed menu beside it: a short
    /// list the user can name, and the choice is shown on the control.
    private var difficultyMenu: some View {
        Menu {
            Picker("Difficulty", selection: Binding(
                get: { model.selectedGameplayDifficultyPath ?? "" },
                set: { model.selectGameplayDifficulty($0) },
            )) {
                ForEach(model.gameplayDifficulties, id: \.path) { difficulty in
                    Text(difficulty.name).tag(difficulty.path)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Text(Self.shortName(model.selectedGameplayDifficultyName ?? ""))
                .font(Theme.Typography.micro)
                .lineLimit(1)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Which difficulty's hit objects the overlay shows: \(model.selectedGameplayDifficultyName ?? "")")
    }

    /// How many characters of a difficulty's name the bar shows.
    static let nameLimit = 14
    private static let timingMarker = " (timing)"

    /// A difficulty name bounded for the bar. Cut in the string, not with a
    /// frame: a menu is an AppKit control and claims its label's full width
    /// whatever frame it is given, so a long name pushed the timecode onto two
    /// lines. The "(timing)" marker is kept, since it says why this one is the
    /// default; the whole name is in the menu and the tooltip.
    static func shortName(_ name: String) -> String {
        let marker = name.hasSuffix(timingMarker) ? timingMarker : ""
        let version = String(name.dropLast(marker.count))
        guard version.count > nameLimit else { return name }
        return String(version.prefix(nameLimit - 1)) + "…" + marker
    }
}
