import SwiftUI

/// Layer actions the screenshot editor publishes to the scene so the menu bar can drive
/// them. Going through the menu bar (rather than `.keyboardShortcut` on in-view buttons)
/// is what gives these real, discoverable ⌘ shortcuts on macOS.
struct ScreenshotLayerCommands {
    var hasSelection = false
    var canPaste = false
    var canMoveForward = false
    var canMoveBackward = false

    var duplicate: () -> Void = {}
    var copy: () -> Void = {}
    var paste: () -> Void = {}
    var bringToFront: () -> Void = {}
    var bringForward: () -> Void = {}
    var sendBackward: () -> Void = {}
    var sendToBack: () -> Void = {}
    var delete: () -> Void = {}
    var isLocked = false
    var toggleLock: () -> Void = {}
}

struct ScreenshotLayerCommandsKey: FocusedValueKey {
    typealias Value = ScreenshotLayerCommands
}

extension FocusedValues {
    var screenshotLayerCommands: ScreenshotLayerCommands? {
        get { self[ScreenshotLayerCommandsKey.self] }
        set { self[ScreenshotLayerCommandsKey.self] = newValue }
    }
}

/// The Layer menu. Items stay visible but disabled when no screenshot layer is selected,
/// so the shortcuts are discoverable from anywhere in the app.
struct ScreenshotLayerMenu: Commands {
    @FocusedValue(\.screenshotLayerCommands) private var commands

    var body: some Commands {
        CommandMenu("Layer") {
            Button("Duplicate", action: commands?.duplicate ?? {})
                .keyboardShortcut("d", modifiers: .command)
                .disabled(!(commands?.hasSelection ?? false))

            Button("Copy Layer", action: commands?.copy ?? {})
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!(commands?.hasSelection ?? false))

            Button("Paste Layer", action: commands?.paste ?? {})
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .disabled(!(commands?.canPaste ?? false))

            Divider()

            Button("Bring to Front", action: commands?.bringToFront ?? {})
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled(!(commands?.canMoveForward ?? false))

            Button("Bring Forward", action: commands?.bringForward ?? {})
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!(commands?.canMoveForward ?? false))

            Button("Send Backward", action: commands?.sendBackward ?? {})
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!(commands?.canMoveBackward ?? false))

            Button("Send to Back", action: commands?.sendToBack ?? {})
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled(!(commands?.canMoveBackward ?? false))

            Divider()

            Button(commands?.isLocked == true ? "Unlock" : "Lock") {
                (commands?.toggleLock ?? {})()
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(!(commands?.hasSelection ?? false))

            Divider()

            Button("Delete Layer", action: commands?.delete ?? {})
                .disabled(!(commands?.hasSelection ?? false))
        }
    }
}
