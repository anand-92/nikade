import Foundation
import Observation

@Observable @MainActor
final class TerminalSearchState {
    var isSearching = false
    var needle = ""
    /// nil = not yet computed; 0+ = valid count
    var total: UInt?
    /// nil = no selection; 0+ = selected match index (1-based from ghostty)
    var selected: UInt?

    /// Formatted display string: "3/15" or "--" when unknown
    var matchDisplay: String {
        guard let total else { return "" }
        guard let selected else { return "0/\(total)" }
        return "\(selected)/\(total)"
    }
}
