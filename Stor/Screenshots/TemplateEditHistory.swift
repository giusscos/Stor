import Foundation
import SwiftUI

/// Everything the canvas editor can change about a template. Small enough to snapshot on
/// every edit now that image bytes live in `ScreenshotImageStore` rather than in layers.
struct TemplateEditState: Equatable {
    var name: String
    var deviceType: DeviceType
    var layers: [ScreenshotLayer]
    var background: CanvasBackground

    init(_ template: ScreenshotTemplate) {
        name = template.name
        deviceType = template.deviceType
        layers = template.layers
        background = template.background
    }

    func apply(to template: ScreenshotTemplate) {
        template.name = name
        template.deviceType = deviceType
        template.layers = layers
        template.background = background
    }
}

/// Undo support for the screenshot editor, backed by the window's `UndoManager` so the
/// standard Edit ▸ Undo / Redo menu items and ⌘Z work without custom key handling.
///
/// Edits register a snapshot of the state *before* the change. Rapid edits of the same
/// kind — dragging a layer, typing in a text field — collapse into a single undo step
/// instead of one per event.
@MainActor
final class TemplateEditHistory {
    private var lastActionName: String?
    private var lastRecordedAt: Date = .distantPast

    private static let coalescingWindow: TimeInterval = 0.75

    /// Call immediately before mutating the template.
    func record(
        on template: ScreenshotTemplate,
        undoManager: UndoManager?,
        actionName: String,
        coalesce: Bool = true
    ) {
        guard let undoManager, !undoManager.isUndoing, !undoManager.isRedoing else { return }

        if coalesce,
           lastActionName == actionName,
           Date().timeIntervalSince(lastRecordedAt) < Self.coalescingWindow {
            lastRecordedAt = .now
            return
        }

        lastActionName = actionName
        lastRecordedAt = .now
        register(TemplateEditState(template), on: template, undoManager: undoManager, actionName: actionName)
    }

    /// Ends the current coalescing run so the next edit always starts a new undo step.
    func endCoalescing() {
        lastActionName = nil
        lastRecordedAt = .distantPast
    }

    private func register(
        _ state: TemplateEditState,
        on template: ScreenshotTemplate,
        undoManager: UndoManager,
        actionName: String
    ) {
        undoManager.registerUndo(withTarget: template) { [weak self, weak undoManager] target in
            guard let undoManager else { return }
            // Registering from inside an undo puts the inverse on the redo stack, so
            // capture the current state before overwriting it.
            self?.register(
                TemplateEditState(target),
                on: target,
                undoManager: undoManager,
                actionName: actionName
            )
            state.apply(to: target)
        }
        undoManager.setActionName(actionName)
    }
}
