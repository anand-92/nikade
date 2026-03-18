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
        controller.onExpandDirectory = makeExpandDirectoryHandler(controller: controller)

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
        controller.onExpandDirectory = makeExpandDirectoryHandler(controller: controller)

        // Only reload when data actually changed. syncData (from expandDirectory)
        // already updates the controller's local snapshot without reloading,
        // so we skip redundant reloadData() calls that cause expand flicker.
        if controller.rootNodes != store.rootNodes {
            controller.updateData(rootNodes: store.rootNodes, nodeIndex: store.nodeIndex)
        }

        if let newID = store.selectedNodeID {
            controller.selectAndReveal(nodeID: newID)
        }
    }

    /// Build the expand callback: invoke the outer handler (which updates the store),
    /// then immediately sync the controller's local snapshot so NSOutlineView
    /// can query the updated children count during the same expand cycle.
    private func makeExpandDirectoryHandler(controller: OutlineTreeViewController) -> (String) -> Void {
        let storeRef = store
        return { [weak controller] path in
            onExpandDirectory?(path)
            controller?.syncData(rootNodes: storeRef.rootNodes, nodeIndex: storeRef.nodeIndex)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {}
}
