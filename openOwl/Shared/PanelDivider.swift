import SwiftUI

/// Semantic divider. Currently using system Divider directly,
/// as macOS separatorColor already adapts to dark/light mode.
struct PanelDivider: View {
    var body: some View {
        Divider()
    }
}
