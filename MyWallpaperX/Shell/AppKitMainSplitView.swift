//
//  AppKitMainSplitView.swift
//  MyWallpaperX
//

import SwiftUI
import AppKit

struct AppKitMainSplitView: NSViewControllerRepresentable {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @Binding var selectedItem: SelectedItem

    func makeNSViewController(context: Context) -> AppKitMainSplitViewController {
        let controller = AppKitMainSplitViewController()
        controller.update(
            wallpaperManager: wallpaperManager,
            selectedItem: bindingForSelection()
        )
        return controller
    }

    func updateNSViewController(_ nsViewController: AppKitMainSplitViewController, context: Context) {
        nsViewController.update(
            wallpaperManager: wallpaperManager,
            selectedItem: bindingForSelection()
        )
    }

    private func bindingForSelection() -> Binding<SelectedItem> {
        Binding(
            get: { selectedItem },
            set: { selectedItem = $0 }
        )
    }
}

private struct SidebarRootView: View {
    @ObservedObject var wallpaperManager: WallpaperManager
    @Binding var selectedItem: SelectedItem

    var body: some View {
        AppKitSidebarView(selectedItem: $selectedItem)
            .environmentObject(wallpaperManager)
            .ignoresSafeArea(.container, edges: .top)
    }
}

private struct DetailRootView: View {
    @ObservedObject var wallpaperManager: WallpaperManager
    @Binding var selectedItem: SelectedItem

    var body: some View {
        DetailView(selectedItem: $selectedItem)
            .environmentObject(wallpaperManager)
            .ignoresSafeArea(.container, edges: .top)
    }
}

final class AppKitMainSplitViewController: NSSplitViewController {
    private enum LayoutConstants {
        static let defaultSidebarWidth: CGFloat = 220
        static let splitAutosaveName = "MainSplitViewV2"
        static let splitAutosaveFramesKeyPrefix = "NSSplitView Subview Frames "
    }

    private let sidebarController = NSHostingController(
        rootView: SidebarRootView(
            wallpaperManager: .shared,
            selectedItem: .constant(.category(.myWallpapers))
        )
    )
    private let detailController = NSHostingController(
        rootView: DetailRootView(
            wallpaperManager: .shared,
            selectedItem: .constant(.category(.myWallpapers))
        )
    )
    private var hasConfiguredSplitItems = false
    private var sidebarMinWidth: CGFloat = 200
    private var sidebarMaxWidth: CGFloat = 320
    private var currentManagerIdentity: ObjectIdentifier?
    private var currentSelectedItem: SelectedItem?

    func update(wallpaperManager: WallpaperManager, selectedItem: Binding<SelectedItem>) {
        if !hasConfiguredSplitItems {
            configureSplitItems()
        }

        let managerIdentity = ObjectIdentifier(wallpaperManager)
        let selectedValue = selectedItem.wrappedValue
        // 这里只在 manager 实例变化或首次绑定时重绑，避免选中态变化触发整棵侧边栏/详情树重建。
        let shouldRebindRootViews = currentManagerIdentity != managerIdentity || currentSelectedItem != selectedValue
        guard shouldRebindRootViews else { return }

        currentManagerIdentity = managerIdentity
        currentSelectedItem = selectedValue

        sidebarController.rootView = SidebarRootView(
            wallpaperManager: wallpaperManager,
            selectedItem: selectedItem
        )
        detailController.rootView = DetailRootView(
            wallpaperManager: wallpaperManager,
            selectedItem: selectedItem
        )
    }

    private func configureSplitItems() {
        hasConfiguredSplitItems = true
        guard splitViewItems.isEmpty else { return }

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarController)
        sidebarItem.minimumThickness = sidebarMinWidth
        sidebarItem.maximumThickness = sidebarMaxWidth
        sidebarItem.preferredThicknessFraction = 0.22
        sidebarItem.canCollapse = false
        sidebarItem.isCollapsed = false
        sidebarItem.allowsFullHeightLayout = true

        let detailItem = NSSplitViewItem(viewController: detailController)
        detailItem.allowsFullHeightLayout = false

        addSplitViewItem(sidebarItem)
        addSplitViewItem(detailItem)
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autosaveName = LayoutConstants.splitAutosaveName
        DispatchQueue.main.async { [weak self] in
            guard let self, self.splitView.subviews.count >= 2 else { return }
            if self.splitViewItems.count > 0 {
                self.splitViewItems[0].isCollapsed = false
            }
            self.applyInitialSidebarWidthIfNeeded()
        }
    }

    private func applyInitialSidebarWidthIfNeeded() {
        let autosaveFramesKey = LayoutConstants.splitAutosaveFramesKeyPrefix + LayoutConstants.splitAutosaveName
        let hasAutosavedFrames = UserDefaults.standard.object(forKey: autosaveFramesKey) != nil
        guard !hasAutosavedFrames else { return }
        splitView.setPosition(LayoutConstants.defaultSidebarWidth, ofDividerAt: 0)
    }
}
