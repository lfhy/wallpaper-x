# Regression Checklist (Fast)

This checklist is for post-change verification with minimal time cost.

## Automated

Run:

```bash
./scripts/run_regression.sh
```

What it validates:
- Project builds.
- Legacy SwiftUI migration paths are not referenced.
- Playback state hooks still exist.

## Manual Smoke (5-8 min)

1. App launch:
- Main window opens quickly.
- Toolbar buttons are enabled/disabled correctly by current selection.

2. Import:
- Import 50+ videos.
- Import result dialog appears quickly (without waiting for thumbnail/frame generation).
- App stays responsive while background assets continue generating.

3. Power pause:
- Enable `未连接电源时暂停`.
- Plugged in: playback continues.
- Unplug: playback pauses without requiring app focus switch.
- Plug back: playback resumes.

4. QuickLook:
- Press `Space`: preview opens.
- Press `Space` again: preview closes.
- Arrow keys switch selection and preview content updates accordingly.

5. Remove semantics:
- In `最近使用`, delete item: only recent reference removed.
- In `我的壁纸`, delete item: removed from library and all linked lists/tags.

6. Persistence:
- Restart app.
- Sidebar width, playback mode, and key settings restore correctly.

## Fail-fast policy

If any item fails:
- Stop adding features.
- Reproduce once with exact steps.
- Fix root cause only.
- Re-run full checklist.
