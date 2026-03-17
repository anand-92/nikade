import SwiftUI

struct OutlineTreeView: NSViewControllerRepresentable {
    @Environment(FileExplorerStore.self) private var store

    var onSelectFile: ((FileExplorerNode) -> Void)?
    var onStage: ((FileExplorerNode) -> Void)?
    var onDiscard: ((FileExplorerNode) -> Void)?
    var onOpenDiff: ((FileExplorerNode) -> Void)?
    var onDelete: (([URL]) -> Void)?
    var onRename: ((FileExplorerNode, String) -> Void)?
    var onCopy: (([URL]) -> Void)?
    var onCut: (([URL]) -> Void)?
    var onPaste: ((URL) -> Void)?
    var onCopyPath: ((URL) -> Void)?
    var onDropFiles: ((URL, [URL]) -> Void)?
    var onExpandDirectory: ((String) -> Void)?

    func makeNSViewController(context: Context) -> OutlineTreeViewController {
        let controller = OutlineTreeViewController()
        controller.onSelectFile = onSelectFile
        controller.onStage = onStage
        controller.onDiscard = onDiscard
        controller.onOpenDiff = onOpenDiff
        controller.onDelete = onDelete
        controller.onRename = onRename
        controller.onCopy = onCopy
        controller.onCut = onCut
        controller.onPaste = onPaste
        controller.onCopyPath = onCopyPath
        controller.onDropFiles = onDropFiles
        controller.onExpandDirectory = onExpandDirectory

        // Initial data load
        controller.updateData(rootNodes: store.rootNodes, nodeIndex: store.nodeIndex)
        // Start collapsed — user expands directories manually

        return controller
    }

    func updateNSViewController(_ controller: OutlineTreeViewController, context: Context) {
        // Update callbacks (they may capture new closures)
        controller.onSelectFile = onSelectFile
        controller.onStage = onStage
        controller.onDiscard = onDiscard
        controller.onOpenDiff = onOpenDiff
        controller.onDelete = onDelete
        controller.onRename = onRename
        controller.onCopy = onCopy
        controller.onCut = onCut
        controller.onPaste = onPaste
        controller.onCopyPath = onCopyPath
        controller.onDropFiles = onDropFiles
        controller.onExpandDirectory = onExpandDirectory

        // @Observable triggers updateNSViewController when store properties change
        controller.updateData(rootNodes: store.rootNodes, nodeIndex: store.nodeIndex)

        if let newID = store.selectedNodeID {
            controller.selectAndReveal(nodeID: newID)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {}
}
