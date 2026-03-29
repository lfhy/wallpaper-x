//
//  ContentView.swift
//  MyWallpaperX
//
//  Created by 宋子强 on 2026/3/12.
//  本项目遵循macOS26设计规范，请尽量调用原生接口实现
//

import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @State private var selectedItem: SelectedItem = .category(.myWallpapers)
    @State private var contentReloadToken = UUID()

    var body: some View {
        AppKitMainSplitView(selectedItem: $selectedItem)
            .id(contentReloadToken)
            .ignoresSafeArea(.container, edges: .top)
            .onAppear {
                syncSelectedItemFromManager()
            }
            .onChange(of: selectedItem) { _, newValue in
                syncManagerSelection(from: newValue)
            }
            .onChange(of: wallpaperManager.selectedCategory) { _, _ in
                syncSelectedItemFromManager()
            }
            .onChange(of: wallpaperManager.selectedTag) { _, _ in
                syncSelectedItemFromManager()
                syncQuickLookPreviewIfNeeded()
            }
            .onChange(of: wallpaperManager.selectedWallpaperId) { _, _ in
                syncQuickLookPreviewIfNeeded()
            }
            .onChange(of: wallpaperManager.selectedWallpaperIds) { _, _ in
                syncQuickLookPreviewIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: .wallpaperManagerDidResetToFreshInstallState)) { _ in
                selectedItem = .category(.myWallpapers)
                contentReloadToken = UUID()
                syncQuickLookPreviewIfNeeded()
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    if wallpaperManager.isSearchFieldActive {
                        wallpaperManager.isSearchFieldActive = false
                        NSApp.keyWindow?.makeFirstResponder(nil)
                    }

                    if isCurrentTapInsideWallpaperGrid() {
                        return
                    }

                    if wallpaperManager.consumePendingCardInteraction() {
                        return
                    }

                    wallpaperManager.clearSingleSelectionIfNeeded()
                }
            )
    }

    private func isCurrentTapInsideWallpaperGrid() -> Bool {
        guard let event = NSApp.currentEvent,
              let window = NSApp.keyWindow,
              let contentView = window.contentView else {
            return false
        }

        let point = contentView.convert(event.locationInWindow, from: nil)
        guard let hitView = contentView.hitTest(point) else { return false }

        var view: NSView? = hitView
        while let current = view {
            if current is AppKitWallpaperCollectionView {
                return true
            }
            view = current.superview
        }
        return false
    }

    private func syncSelectedItemFromManager() {
        let managerSelection = SelectedItem(selectionContext: wallpaperManager.currentSelectionContext)
        if selectedItem != managerSelection {
            selectedItem = managerSelection
        }
    }

    private func syncManagerSelection(from item: SelectedItem) {
        item.apply(to: wallpaperManager)
    }

    private func syncQuickLookPreviewIfNeeded() {
        QuickLookPreviewController.shared.syncVisiblePreview(for: wallpaperManager.selectedWallpaperForQuickLook)
    }

}
