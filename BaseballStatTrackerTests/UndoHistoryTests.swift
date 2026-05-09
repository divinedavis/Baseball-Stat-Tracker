import XCTest
@testable import BaseballStatTracker

@MainActor
final class UndoHistoryTests: XCTestCase {
    func testInitialState() {
        let history = UndoHistory()
        XCTAssertFalse(history.canUndo)
        XCTAssertFalse(history.canRedo)
    }

    func testRegisterEnablesUndo() {
        let history = UndoHistory()
        history.register(undo: {}, redo: {})
        XCTAssertTrue(history.canUndo)
        XCTAssertFalse(history.canRedo)
    }

    func testUndoCallsClosureAndEnablesRedo() {
        let history = UndoHistory()
        var value = 0
        history.register(undo: { value -= 1 }, redo: { value += 1 })
        value += 1 // simulate the original action
        XCTAssertEqual(value, 1)
        history.undo()
        XCTAssertEqual(value, 0)
        XCTAssertFalse(history.canUndo)
        XCTAssertTrue(history.canRedo)
    }

    func testRedoReplaysAndEnablesUndo() {
        let history = UndoHistory()
        var value = 0
        history.register(undo: { value -= 1 }, redo: { value += 1 })
        value += 1
        history.undo()
        history.redo()
        XCTAssertEqual(value, 1)
        XCTAssertTrue(history.canUndo)
        XCTAssertFalse(history.canRedo)
    }

    func testNewRegisterClearsRedoStack() {
        let history = UndoHistory()
        history.register(undo: {}, redo: {})
        history.undo()
        XCTAssertTrue(history.canRedo)
        history.register(undo: {}, redo: {})
        XCTAssertFalse(history.canRedo, "Fresh edits must invalidate the redo stack")
    }

    func testClearWipesBothStacks() {
        let history = UndoHistory()
        history.register(undo: {}, redo: {})
        history.register(undo: {}, redo: {})
        history.clear()
        XCTAssertFalse(history.canUndo)
        XCTAssertFalse(history.canRedo)
    }

    func testUndoAndRedoNoOpWhenStacksEmpty() {
        let history = UndoHistory()
        // Should not crash.
        history.undo()
        history.redo()
        XCTAssertFalse(history.canUndo)
        XCTAssertFalse(history.canRedo)
    }

    func testStacksAreUnlimited() {
        let history = UndoHistory()
        var counter = 0
        for _ in 0..<200 {
            history.register(undo: { counter -= 1 }, redo: { counter += 1 })
            counter += 1
        }
        XCTAssertEqual(counter, 200)
        for _ in 0..<200 { history.undo() }
        XCTAssertEqual(counter, 0)
        XCTAssertFalse(history.canUndo)
    }
}
