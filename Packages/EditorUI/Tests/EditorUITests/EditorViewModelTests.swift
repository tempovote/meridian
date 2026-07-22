import AppKit
import DocumentCore
import Testing
@testable import EditorUI

/// Records every call so tests can assert the VM ↔ engine contract
/// without a real NSTextView.
@MainActor
final class MockLayoutEngine: TextLayoutEngine {
    let view: NSView = .init()
    var keyView: NSView {
        view
    }

    var onUserEdit: ((EditTransaction) -> Void)?
    var loaded: [TextBuffer] = []
    var applied: [(transaction: EditTransaction, base: TextBuffer)] = []
    var selectionsSet: [SelectionSet] = []

    func load(buffer: TextBuffer) {
        loaded.append(buffer)
    }

    func apply(_ transaction: EditTransaction, base: TextBuffer) {
        applied.append((transaction, base))
    }

    func selection(in buffer: TextBuffer) -> SelectionSet {
        .empty
    }

    func setSelection(_ selection: SelectionSet, in buffer: TextBuffer) {
        selectionsSet.append(selection)
    }

    func scrollTo(_ offset: ByteOffset, in buffer: TextBuffer) {}

    /// Simulates the user typing `replacement` over `range`: mimics
    /// TextKit2Engine's behavior — the engine applies to its own snapshot
    /// FIRST, then reports the transaction.
    func simulateUserEdit(
        range: Range<ByteOffset>, replacement: String, base: TextBuffer,
    ) -> EditTransaction {
        let transaction = EditTransaction(
            baseVersion: base.version,
            edits: [Edit(range: range, replacement: replacement)],
            coalescingKey: .typing,
        )
        onUserEdit?(transaction)
        return transaction
    }
}

@MainActor
private func makeViewModel(_ buffer: TextBuffer, engine: MockLayoutEngine) -> EditorViewModel {
    EditorViewModel(documentModel: DocumentModel(buffer: buffer), engine: engine)
}

@MainActor
@Suite("EditorViewModel")
struct EditorViewModelTests {
    @Test func initLoadsEngine() {
        let engine = MockLayoutEngine()
        let vm = makeViewModel(TextBuffer("hello"), engine: engine)
        #expect(engine.loaded.count == 1)
        #expect(engine.loaded[0].string == "hello")
        #expect(vm.buffer.string == "hello")
    }

    @Test func userEditAppliesToBufferWithoutMirroringBack() {
        let engine = MockLayoutEngine()
        let vm = makeViewModel(TextBuffer("hello"), engine: engine)
        _ = engine.simulateUserEdit(
            range: ByteOffset(5) ..< ByteOffset(5), replacement: "!", base: vm.buffer,
        )
        #expect(vm.buffer.string == "hello!")
        #expect(engine.applied.isEmpty) // view led — no echo back
    }

    @Test func performAppliesAndMirrors() {
        let engine = MockLayoutEngine()
        let vm = makeViewModel(TextBuffer("hello"), engine: engine)
        let base = vm.buffer
        vm.perform(EditTransaction(
            baseVersion: base.version,
            edits: [Edit(range: ByteOffset(0) ..< ByteOffset(5), replacement: "goodbye")],
            origin: .replaceAll,
        ))
        #expect(vm.buffer.string == "goodbye")
        #expect(engine.applied.count == 1)
        #expect(engine.applied[0].base.version == base.version)
    }

    @Test func undoRedoRoundTripsThroughEngine() {
        let engine = MockLayoutEngine()
        let vm = makeViewModel(TextBuffer("ab"), engine: engine)
        _ = engine.simulateUserEdit(
            range: ByteOffset(2) ..< ByteOffset(2), replacement: "c", base: vm.buffer,
        )
        #expect(vm.buffer.string == "abc")
        #expect(vm.canUndo)
        vm.undo()
        #expect(vm.buffer.string == "ab")
        // Undo is programmatic: it MUST mirror into the engine.
        #expect(engine.applied.count == 1)
        #expect(vm.canRedo)
        vm.redo()
        #expect(vm.buffer.string == "abc")
        #expect(engine.applied.count == 2)
    }

    @Test func coalescedTypingFiresOneUndoEntryCallback() {
        let engine = MockLayoutEngine()
        let vm = makeViewModel(TextBuffer(""), engine: engine)
        var callbacks = 0
        vm.onNewUndoEntry = { callbacks += 1 }
        // Three consecutive same-instant typing inserts coalesce into ONE
        // UndoStack entry → exactly one NSUndoManager registration.
        _ = engine.simulateUserEdit(range: ByteOffset(0) ..< ByteOffset(0), replacement: "a", base: vm.buffer)
        _ = engine.simulateUserEdit(range: ByteOffset(1) ..< ByteOffset(1), replacement: "b", base: vm.buffer)
        _ = engine.simulateUserEdit(range: ByteOffset(2) ..< ByteOffset(2), replacement: "c", base: vm.buffer)
        #expect(callbacks == 1)
        vm.undo()
        #expect(vm.buffer.string == "") // whole burst undone as one entry
    }

    @Test func undoWithNothingRecordedIsANoOp() {
        let engine = MockLayoutEngine()
        let vm = makeViewModel(TextBuffer("x"), engine: engine)
        #expect(!vm.canUndo)
        vm.undo()
        #expect(vm.buffer.string == "x")
    }

    @Test func canUndoObservationFiresOnEdit() {
        let engine = MockLayoutEngine()
        let vm = makeViewModel(TextBuffer(""), engine: engine)
        final class ObservationState: @unchecked Sendable { var fired = false }
        let obsState = ObservationState()
        // Track observation of canUndo across the edit.
        withObservationTracking {
            _ = vm.canUndo
        } onChange: {
            obsState.fired = true
        }
        // Simulate a user edit, which should update canUndo via undoStack
        _ = engine.simulateUserEdit(
            range: ByteOffset(0) ..< ByteOffset(0), replacement: "x", base: vm.buffer,
        )
        #expect(obsState.fired)
        #expect(vm.canUndo)
    }

    @Test func twoViewModelsSharingOneDocumentModelSeeTheSameBuffer() {
        let documentModel = DocumentModel(buffer: TextBuffer("shared"))
        let engineA = MockLayoutEngine()
        let engineB = MockLayoutEngine()
        let vmA = EditorViewModel(documentModel: documentModel, engine: engineA)
        let vmB = EditorViewModel(documentModel: documentModel, engine: engineB)
        vmA.perform(EditTransaction(
            baseVersion: vmA.buffer.version,
            edits: [Edit(range: ByteOffset(0) ..< ByteOffset(6), replacement: "changed")],
            origin: .replaceAll,
        ))
        #expect(vmA.buffer.string == "changed")
        #expect(vmB.buffer.string == "changed")
    }

    @Test func twoViewModelsSharingOneDocumentModelHaveIndependentDisplayToggles() {
        let documentModel = DocumentModel(buffer: TextBuffer("shared"))
        let engineA = MockLayoutEngine()
        let engineB = MockLayoutEngine()
        let vmA = EditorViewModel(documentModel: documentModel, engine: engineA)
        let vmB = EditorViewModel(documentModel: documentModel, engine: engineB)
        vmA.isSoftWrapEnabled = false
        vmA.isGutterVisible = false
        #expect(vmB.isSoftWrapEnabled) // unaffected by vmA's change
        #expect(vmB.isGutterVisible)
        vmB.isSoftWrapEnabled = true // was already true; toggling vmA didn't flip it
        #expect(!vmA.isSoftWrapEnabled) // vmA's own toggle is unaffected by vmB
    }
}
