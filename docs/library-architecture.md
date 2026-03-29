# Wallpaper Library Architecture

This document maps the `WallpaperManager` structure so maintenance and code-reading are predictable.

Cross-round refactor history is tracked in:

- `docs/refactor-memo.md`

## Core State

- `MyWallpaperX/Core/Library/WallpaperManager.swift`
  - Singleton state and reactive bindings
  - Queue/cache fields and shared low-level helpers
  - Shared path helpers (`normalizedPath`, `pathExists`, `normalizedSourcePathExists`, `isReadablePath`)
  - Unified auto-switch timer state (`autoSwitchTimer`)
  - Startup wiring and observer subscription bootstrap
  - Path normalization and library index helper methods
  - Recent-list dedupe and library-constraint filtering
  - Upsert/merge semantics for library entries

## Feature Slices

- `MyWallpaperX/Core/Library/WallpaperManager+Persistence.swift`
  - UserDefaults load/save/restore
  - Shared Codable encode/decode helpers to keep key-value persistence path single-source
  - Current/recent/playback state persistence
  - Shared current-wallpaper snapshot writer reused by normal save/flush/removal cleanup
  - Coalesced wallpapers auto-persist scheduling
  - Flush pending persistence

- `MyWallpaperX/Core/Library/WallpaperManager+ImportProcessing.swift`
  - First-run bundled sample bootstrap
  - Import panel entry and host-window modal orchestration
  - Import file validation/dedupe and ingestion
  - Import counters/summary composition centralized to one path
  - Import context application and existing-entry linking
  - Import summary composition and result dialog via shared `presentAppAlert(...)`
  - Async post-import asset scheduling

- `MyWallpaperX/Core/Library/WallpaperManager+CachePipeline.swift`
  - Cache generation versioning
  - Thumbnail generation and in-flight dedupe
  - In-flight dedupe and cache key strategy
  - Shared AVFoundation frame extraction helper
  - Static-frame scheduling and generation
  - Thumbnail/static-frame path synchronization back to model (only writes when values actually change)
  - Card-level missing-cache self-healing trigger
  - Cache invalidation guards
  - Full cache clear/reset

- `MyWallpaperX/Core/Library/WallpaperManager+WallpaperApplication.swift`
  - Apply wallpaper and debounce policy
  - Missing-file fallback and self-healing removal
  - Reuses removal shared helpers to keep missing-file purge consistent with library deletion
  - Missing-indexed-file aggregation and delayed alert presentation via shared `presentAppAlert(...)`
  - Optional sync to system wallpaper

- `MyWallpaperX/Core/Library/WallpaperManager+PlaybackControl.swift`
  - Manual navigation and mode transitions
  - Uses unified playback-mode helpers (`playbackMode`, `isSwitchingPlaybackMode`) to avoid branch drift
  - Playback failure fallback
  - Playback-ended auto-advance rules

- `MyWallpaperX/Core/Library/WallpaperManager+PlaybackSettings.swift`
  - Playback mode normalization
  - Centralized playback-mode/timer/engine-loop policy helpers
  - UI-facing playback mode mutators (`setLoopPlaybackEnabled`, `setRandomPlaybackEnabled`, `setSequentialPlaybackEnabled`)
  - Auto-switch timer scheduling policy (`refreshAutoSwitchTimerIfNeeded`)
  - Engine setting + volume sync
  - System hotkey action dispatch
  - Start-at-login registration/unregistration

- `MyWallpaperX/Core/Library/WallpaperManager+Removal.swift`
  - Removal entry points by scope
  - Async removal orchestration
  - Selected-items bulk deletion entry
  - Favorites/标签/最近使用的引用移除规则
  - Shared reference-removal helper for favorites/tag updates
  - Favorite toggle
  - Library-removal application
  - Shared current-wallpaper reset helpers for removal/missing-file paths
  - Shared collection-removal + selection-cleanup helpers reused by non-UI purge paths
  - Derived asset cleanup (never touching source files)

- `MyWallpaperX/Core/Library/WallpaperManager+Selection.swift`
  - Category/tag selection state
  - Multi-select state transitions and drag-select behavior
  - Card interaction pending-state coordination
  - Unified selection read semantics:
    - `effectiveSelectedWallpaperIDs`
    - `hasAnyWallpaperSelection`
    - `hasSingleWallpaperSelection`
  - Unified selection write entry points:
    - `setSingleSelection(_:)`
    - `replaceMultiSelection(with:)`
    - `clearSingleSelectionIfNeeded()`

## Shared Models

- `MyWallpaperX/Core/Library/WallpaperLibrarySupport.swift`

## Convention

- New behavior belongs in the matching slice extension first.
- Keep `WallpaperManager.swift` centered on state definition and orchestration.
