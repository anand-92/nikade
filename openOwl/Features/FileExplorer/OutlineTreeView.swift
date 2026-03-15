import Combine
import SwiftUI

struct OutlineTreeView: NSViewControllerRepresentable {
    @EnvironmentObject private var store: FileExplorerStore

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

        // Initial data load
        controller.updateData(rootNodes: store.rootNodes, nodeIndex: store.nodeIndex)
        controller.expandTopLevel()

        // Subscribe to store changes
        context.coordinator.subscribe(store: store, controller: controller)

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
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private var cancellable: AnyCancellable?

        @MainActor
        func subscribe(store: FileExplorerStore, controller: OutlineTreeViewController) {
            cancellable?.cancel()
            // Only reload when the actual tree data changes, not on every store property change
            // (selectedNodeID, previewState, quickOpen etc. don't need a tree reload)
            cancellable = store.$rootNodes
                .dropFirst() // skip initial value (already loaded in makeNSViewController)
                .receive(on: RunLoop.main)
                .sink { [weak controller, weak store] newRootNodes in
                    guard let controller, let store else { return }
                    controller.updateData(rootNodes: newRootNodes, nodeIndex: store.nodeIndex)
                }
        }

        deinit {
            cancellable?.cancel()
        }
    }
}
