import Testing
import Foundation
@testable import openOwl

@Suite("RightDockStore")
struct RightDockStoreTests {
    private static let keyExpanded = "openowl.rightDock.isExpanded"
    private static let keyActiveTab = "openowl.rightDock.activeTab"
    private static let keyWidth = "openowl.rightDock.width"

    private static func clearDefaults() {
        UserDefaults.standard.removeObject(forKey: keyExpanded)
        UserDefaults.standard.removeObject(forKey: keyActiveTab)
        UserDefaults.standard.removeObject(forKey: keyWidth)
    }

    // MARK: - init / defaults

    @Test @MainActor func init_defaultsToCollapsed() {
        Self.clearDefaults()
        let store = RightDockStore()
        #expect(store.isExpanded == false)
        Self.clearDefaults()
    }

    @Test @MainActor func init_defaultsToGitTab() {
        Self.clearDefaults()
        let store = RightDockStore()
        #expect(store.activeTab == .git)
        Self.clearDefaults()
    }

    @Test @MainActor func init_defaultWidthAtLeastMin() {
        Self.clearDefaults()
        let store = RightDockStore()
        #expect(store.width >= RightDockStore.minWidth)
        Self.clearDefaults()
    }

    @Test @MainActor func init_isFullscreenDefaultsFalse() {
        Self.clearDefaults()
        let store = RightDockStore()
        #expect(store.isFullscreen == false)
        Self.clearDefaults()
    }

    // MARK: - toggle(tab:)

    @Test @MainActor func toggle_whenCollapsed_expandsAndSetsTab() {
        Self.clearDefaults()
        let store = RightDockStore()
        #expect(store.isExpanded == false)

        store.toggle(tab: .files)
        #expect(store.isExpanded == true)
        #expect(store.activeTab == .files)
        Self.clearDefaults()
    }

    @Test @MainActor func toggle_whenExpandedAndSameTab_collapses() {
        Self.clearDefaults()
        let store = RightDockStore()
        store.toggle(tab: .git)
        #expect(store.isExpanded == true)

        store.toggle(tab: .git)
        #expect(store.isExpanded == false)
        #expect(store.activeTab == .git)
        Self.clearDefaults()
    }

    @Test @MainActor func toggle_whenExpandedAndDifferentTab_switchesTab() {
        Self.clearDefaults()
        let store = RightDockStore()
        store.toggle(tab: .files)

        store.toggle(tab: .deploy)
        #expect(store.isExpanded == true)
        #expect(store.activeTab == .deploy)
        Self.clearDefaults()
    }

    // MARK: - expand / collapse

    @Test @MainActor func expand_setsTabAndOpens() {
        Self.clearDefaults()
        let store = RightDockStore()

        store.expand(tab: .deploy)
        #expect(store.isExpanded == true)
        #expect(store.activeTab == .deploy)
        Self.clearDefaults()
    }

    @Test @MainActor func collapse_closesPanel() {
        Self.clearDefaults()
        let store = RightDockStore()
        store.toggle(tab: .git)

        store.collapse()
        #expect(store.isExpanded == false)
        Self.clearDefaults()
    }

    // MARK: - persistence

    @Test @MainActor func isExpanded_persistsToDefaults() {
        Self.clearDefaults()
        let store = RightDockStore()
        store.isExpanded = true

        let saved = UserDefaults.standard.object(forKey: Self.keyExpanded) as? Bool
        #expect(saved == true)
        Self.clearDefaults()
    }

    @Test @MainActor func activeTab_persistsToDefaults() {
        Self.clearDefaults()
        let store = RightDockStore()
        store.activeTab = .deploy

        let saved = UserDefaults.standard.string(forKey: Self.keyActiveTab)
        #expect(saved == RightDockTab.deploy.rawValue)
        Self.clearDefaults()
    }

    @Test @MainActor func width_persistsToDefaults() {
        Self.clearDefaults()
        let store = RightDockStore()
        store.width = 500

        let saved = UserDefaults.standard.object(forKey: Self.keyWidth) as? Double
        #expect(saved == 500)
        Self.clearDefaults()
    }

    @Test @MainActor func init_restoresSavedValues() {
        UserDefaults.standard.set(true, forKey: Self.keyExpanded)
        UserDefaults.standard.set(RightDockTab.files.rawValue, forKey: Self.keyActiveTab)
        UserDefaults.standard.set(450.0, forKey: Self.keyWidth)

        let store = RightDockStore()
        #expect(store.isExpanded == true)
        #expect(store.activeTab == .files)
        #expect(store.width == 450)
        Self.clearDefaults()
    }

    @Test @MainActor func init_invalidTab_fallsBackToGit() {
        Self.clearDefaults()
        UserDefaults.standard.set("invalid", forKey: Self.keyActiveTab)

        let store = RightDockStore()
        #expect(store.activeTab == .git)
        Self.clearDefaults()
    }

    // MARK: - isFullscreen

    @Test @MainActor func toggleFullscreen_doesNothingWhenCollapsed() {
        Self.clearDefaults()
        let store = RightDockStore()
        #expect(store.isExpanded == false)

        store.toggleFullscreen()
        #expect(store.isFullscreen == false)
        Self.clearDefaults()
    }

    @Test @MainActor func toggleFullscreen_togglesWhenExpanded() {
        Self.clearDefaults()
        let store = RightDockStore()
        store.toggle(tab: .git)

        store.toggleFullscreen()
        #expect(store.isFullscreen == true)

        store.toggleFullscreen()
        #expect(store.isFullscreen == false)
        Self.clearDefaults()
    }

    @Test @MainActor func collapse_resetsFullscreen() {
        Self.clearDefaults()
        let store = RightDockStore()
        store.toggle(tab: .git)
        store.toggleFullscreen()
        #expect(store.isFullscreen == true)

        store.collapse()
        #expect(store.isFullscreen == false)
        Self.clearDefaults()
    }

    @Test @MainActor func toggleSameTab_collapsesAndResetsFullscreen() {
        Self.clearDefaults()
        let store = RightDockStore()
        store.toggle(tab: .git)
        store.toggleFullscreen()
        #expect(store.isFullscreen == true)

        store.toggle(tab: .git)
        #expect(store.isExpanded == false)
        #expect(store.isFullscreen == false)
        Self.clearDefaults()
    }

    @Test @MainActor func isFullscreen_notPersisted() {
        Self.clearDefaults()
        let store = RightDockStore()
        store.toggle(tab: .git)
        store.toggleFullscreen()
        #expect(store.isFullscreen == true)

        let store2 = RightDockStore()
        #expect(store2.isFullscreen == false)
        Self.clearDefaults()
    }

    // MARK: - setWidth(_:maxWidth:)

    @Test @MainActor func setWidth_clampsToMin() {
        Self.clearDefaults()
        let store = RightDockStore()

        store.setWidth(100, maxWidth: 800)
        #expect(store.width == RightDockStore.minWidth)
        Self.clearDefaults()
    }

    @Test @MainActor func setWidth_clampsToMax() {
        Self.clearDefaults()
        let store = RightDockStore()

        store.setWidth(2000, maxWidth: 600)
        #expect(store.width == 600)
        Self.clearDefaults()
    }

    @Test @MainActor func setWidth_normalRange() {
        Self.clearDefaults()
        let store = RightDockStore()

        store.setWidth(400, maxWidth: 800)
        #expect(store.width == 400)
        Self.clearDefaults()
    }

    @Test @MainActor func setWidth_handlesMaxBelowMin() {
        Self.clearDefaults()
        let store = RightDockStore()

        store.setWidth(500, maxWidth: 100)
        #expect(store.width == RightDockStore.minWidth)
        Self.clearDefaults()
    }
}
