# Playback Architecture

This document maps playback-layer responsibilities for quick debugging and safe edits.

## Core Entry

- `MyWallpaperX/Core/Playback/WallpaperEngine.swift`
  - Engine singleton lifecycle
  - Daemon session creation / teardown
  - Play command dispatch and daemon event parsing
  - Display-session maintenance and screen scan

## System State Policy

- `MyWallpaperX/Core/Playback/WallpaperEngine+SystemState.swift`
  - macOS notifications wiring
  - Sleep / wake / lock / unlock handlers
  - Active app / active space reactions
  - Unified evaluation scheduling (`requestPlaybackStateEvaluation`) with immediate/debounced paths
  - Pause/resume decision pipeline (`checkAndUpdatePlaybackState`)
  - Fullscreen-space detection (Space API only)
  - Power-adapter and idle-time checks

## Shared Types

- `MyWallpaperX/Core/Playback/WallpaperEngineTypes.swift`
  - CGS symbol bindings
  - Daemon command/event transport types

## Debug Routing

- Playback not starting / daemon command issue:
  - Start from `WallpaperEngine.swift` (`applyWallpaper`, `sendPlayCommand`, `handleDaemonEvent`).
- Pause/resume condition issue:
  - Start from `WallpaperEngine+SystemState.swift` (`checkAndUpdatePlaybackState`).
- Fullscreen pause mismatch:
  - Check `isOtherAppFullscreenSpaceActiveViaSpaceAPI` and `activeSpaceChanged` debounce timing.
- Power/idle pause mismatch:
  - Check `powerStatusChanged`, `refreshPowerStateFallbackMonitoring`, `isPowerAdapterConnected`, `isSystemIdlePastThreshold`.
