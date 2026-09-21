# Changelog

## Qstats [1.2.0] - 2026-09-21

- Change the default region screenshot shortcut to Option-D.
- Add a native shortcut recorder, persistent custom shortcuts, conflict detection and one-click reset.
- Replace the flat text-entry field with a compact glass editor and smaller placeholder text.
- Add distinct high-contrast cursors for selection and every annotation tool.
- Add hover, pressed and selected feedback to all screenshot toolbar buttons.
- Fix the Save PNG action appearing to freeze by presenting the save panel asynchronously above the capture overlay.
- Continue shipping exactly two macOS installers: Apple Silicon and Intel.

## Qstats [1.1.0] - 2026-09-21

- Add on-demand multi-display region screenshots with a global Control-Shift-2 shortcut.
- Add a compact native annotation toolbar with rectangles, arrows, pen, mosaic, text, colors, widths and undo.
- Add PNG copy/save, screenshot pinning and clipboard image pinning.
- Add draggable always-on-top image windows with zoom and opacity controls.
- Keep screen access isolated from the continuously running system monitors.
- Build and validate separate Apple Silicon and Intel DMG installers.
- Document the screenshot architecture, privacy behavior and release plan.

## Qstats [1.0.0] - 2026-09-21

- Rename the application, executable, bundle and distribution files to `Qstats`.
- Replace the wordmark icon with a minimal, text-free activity pulse.
- Add persistent, immediate menu-bar selection for any 1–4 metrics (all enabled by default).
- Add per-metric ring, horizontal bar, vertical bar and percentage text menu controls.
- Refine spacing, ring weight, rounded tracks and two-row network typography.
- Preserve an entry point when GPU data is unavailable or a config hides every metric.
- Migrate legacy preferences and preserve advanced YAML settings when saving selections.
- Add macOS CI tests, style preview renders and Universal DMG/ZIP packaging.
- Publish new versions to GitHub Releases after successful main builds, preserving existing releases.
- Reset this fork's version to 1.0.0; prior upstream releases are retained below for attribution.

## Upstream history — OSX Stats Nano

## [1.0.10] - 2026-04-06

### Fix: remove unnecessary StatusBarController recreation on wake

**Symptom observed (Apr 6 2026):**
After connecting an external monitor and rearranging displays, the system log showed
recurring `[BSBlockSentinel:FBSWorkspaceScenesClient] failed!` errors from the BaseBoard
framework. These appeared immediately after the display reconfiguration event and then
continued at ~10-minute intervals, suggesting the ControlCenter scene for the status bar
item was failing to reconnect after being torn down.

**Root cause analysis:**
`systemDidWake` was recreating the entire `StatusBarController` (and therefore a new
`NSStatusItem`) on every wake. The original justification (PR #2, Mar 28 2026) was that
"NSStatusItem can become invalid after a long overnight sleep". However:

1. On modern macOS, `NSStatusItem` is retained and managed by ControlCenter across
   sleep/wake cycles — it does not become invalid.
2. The actual post-sleep crash (PR #3, Apr 3 2026) was caused by `NetworkMonitor`'s stale
   `previousTime` causing a UInt64 overflow, and was already fixed by calling `reset()` in
   `StatsPoller.start()`.
3. Recreating `NSStatusItem` during an already-unstable window (display reconfiguration,
   system wake) tears down the active ControlCenter scene and requests a new one, which
   times out → `BSBlockSentinel` failures.

**Hypothesis:**
The `StatusBarController` recreation was never necessary and was masking the real fix
(monitor state reset). Removing it eliminates the scene churn and the `BSBlockSentinel`
errors. If the status bar item ever genuinely disappears after a long sleep in a future
macOS version, that would need a targeted investigation rather than a blanket recreation.

**Change:**
`systemDidWake` now only restarts the poller (which already calls `cpuMonitor.reset()` and
`networkMonitor.reset()` internally). No `StatusBarController` recreation. No display
change notification handler needed — ControlCenter repositions status items automatically
when display topology changes.

---

## [1.0.9] - 2026-04-03

- Fix: reset monitor state on wake to prevent post-sleep crash (NetworkMonitor UInt64 overflow)

## [1.0.8] - 2026-03-28

- Fix: cache arrow font as stored property to prevent nil crash during draw

## [1.0.7] and earlier

- See git log
