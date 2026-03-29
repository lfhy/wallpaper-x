# UI Architecture

This document maps the main-window UI structure so behavior can be located quickly without scanning large mixed files.

## Main Window

- `MyWallpaperX/App/MainWindowController.swift`
  - Window creation and style
  - Hosts `ContentView`

- `MyWallpaperX/App/MainWindowToolbarController.swift`
  - Toolbar item lifecycle
  - Toolbar state refresh and enable/disable rules
  - Dispatches user actions through `performToolbarAction(...)` to keep gating/refresh policy consistent

- `MyWallpaperX/App/UIActionHelper.swift`
  - Shared UI action implementations
  - Import/select-all, delete, favorite, tag, info dialogs
  - Sidebar tag create/rename/delete dialogs
  - Shared single/multi selection resolution helpers for action consistency
  - Shared selected-item mutation helper for favorite/tag updates
  - Uses global `presentAppAlert(...)` so toolbar/sidebar dialogs share one modal path

## Main Content

- `MyWallpaperX/UI/Main/ContentView.swift`
  - Root split-view container
  - Selection synchronization with `WallpaperManager`
  - QuickLook keyboard handling and selection navigation

- `MyWallpaperX/UI/Main/LibraryBrowserViews.swift`
  - `SidebarView`, `DetailView`, `GridView`, `TagItem`
  - Grid rendering and drag-selection behavior
  - Sidebar tag rename/delete flows

- `MyWallpaperX/UI/Main/ContentViewSupport.swift`
  - `SelectedItem` model
  - QuickLook preview controller
  - Tag drag/drop support types

- `MyWallpaperX/UI/Main/WallpaperSelectionContext.swift`
  - Shared selection context logic across toolbar + content
  - Resolve import scope, deletion scope, and source wallpaper list

- `MyWallpaperX/UI/Main/SettingsView.swift`
  - Settings form rendering and control binding
  - Delegates playback mode transitions to `WallpaperManager+PlaybackSettings`

## Shared UI Components

- `MyWallpaperX/UI/Components/WallpaperCard.swift`
- `MyWallpaperX/UI/Components/ModalPresentation.swift`
- `MyWallpaperX/UI/Components/VisualEffectView.swift`

## Conventions

- Keep shared action/dialog logic inside `UIActionHelper` or `WallpaperManager`, not duplicated in multiple views/controllers.
- Keep selection/scope mapping in `WallpaperSelectionContext` to avoid UI-layer drift.
- Keep `ContentView.swift` focused on orchestration; place heavy view blocks in `LibraryBrowserViews.swift`.
