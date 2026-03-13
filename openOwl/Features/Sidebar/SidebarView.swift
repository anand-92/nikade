import SwiftUI

struct SidebarView: View {
    var body: some View {
        List {
            Section("Terminal") {
                Label("Terminal", systemImage: "terminal")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(AppConstants.appName)
    }
}
