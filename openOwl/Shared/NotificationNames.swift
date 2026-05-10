import Foundation

extension Notification.Name {
    static let quickOpen = Notification.Name("openowl.quickOpen")
    static let terminalSearch = Notification.Name("openowl.terminalSearch")
    /// Posted when terminal cmd+click resolves to a local file. userInfo
    /// carries `["url": URL]`. FileExplorerView listens and opens the
    /// editor tab, optionally highlighting the node if it's in the tree.
    static let openFileFromTerminal = Notification.Name("openowl.openFileFromTerminal")
}
