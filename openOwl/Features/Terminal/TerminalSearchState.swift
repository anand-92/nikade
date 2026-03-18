import Foundation
import Observation

@Observable @MainActor
final class TerminalSearchState {
    var isSearching = false
    var needle = ""
    /// nil = not yet computed; 0+ = valid count
    var total: UInt?
    /// nil = no selection; 0+ = selected match index (0-based from ghostty)
    var selected: UInt?
    /// Pending debounce task for short queries (< 3 chars).
    /// Stored here (not as @State in the view) so the AppDelegate Esc path
    /// can cancel it via endSearch() before the ghostty command fires.
    var debounceTask: Task<Void, Never>?

    /// Formatted display string: "3/15" or "--" when unknown
    /// Ghostty's `selected` is 0-based; display as 1-based.
    var matchDisplay: String {
        guard let total else { return "" }
        guard let selected else { return "0/\(total)" }
        return "\(selected + 1)/\(total)"
    }
}
