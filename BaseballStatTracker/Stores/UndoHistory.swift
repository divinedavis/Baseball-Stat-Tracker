import Foundation
import Combine

/// Unlimited undo/redo stack of paired closures.
///
/// Register an edit with a matching `undo` (how to reverse it) and `redo` (how
/// to re-apply it after an undo). Any fresh `register` clears the redo stack,
/// matching what users expect from standard document editors.
@MainActor
final class UndoHistory: ObservableObject {
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    private struct Step {
        let undo: () -> Void
        let redo: () -> Void
    }

    private var undoStack: [Step] = []
    private var redoStack: [Step] = []

    func register(undo: @escaping () -> Void, redo: @escaping () -> Void) {
        undoStack.append(Step(undo: undo, redo: redo))
        redoStack.removeAll()
        refresh()
    }

    func undo() {
        guard let step = undoStack.popLast() else { return }
        step.undo()
        redoStack.append(step)
        refresh()
    }

    func redo() {
        guard let step = redoStack.popLast() else { return }
        step.redo()
        undoStack.append(step)
        refresh()
    }

    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
        refresh()
    }

    private func refresh() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }
}
