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
        controller.onExpandDirectory = onExpandDirectory
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private var cancellables = Set<AnyCancellable>()

        @MainActor
        func subscribe(store: FileExplorerStore, controller: OutlineTreeViewController) {
            cancellables.removeAll()

            // Reload tree when data changes
            store.$rootNodes
                .dropFirst()
                .receive(on: RunLoop.main)
                .sink { [weak controller, weak store] newRootNodes in
                    guard let controller, let store else { return }
                    controller.updateData(rootNodes: newRootNodes, nodeIndex: store.nodeIndex)
                }
                .store(in: &cancellables)

            // Reveal & select node when selectedNodeID changes (e.g. from Quick Open)
            store.$selectedNodeID
                .dropFirst()
                .removeDuplicates()
                .receive(on: RunLoop.main)
                .sink { [weak controller] newID in
                    guard let controller, let newID else { return }
                    controller.selectAndReveal(nodeID: newID)
                }
                .store(in: &cancellables)
        }

        deinit {
            cancellables.removeAll()
        }
    }
}
