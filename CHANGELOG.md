# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] — 2026-07-29

### Added

- **Mini HUD.** A compact capsule beside the pointer showing the current task's colour and elapsed
  time, on `⌥Q` by default. It never takes keyboard focus and hides itself after a configurable
  delay.
- **The HUD follows the pointer**, flipping at screen edges and crossing between displays. While
  following it is click-through, so it never intercepts a click meant for what is underneath —
  a window attached to the cursor could not be clicked anyway. Turn *Follow the pointer* off to
  place it once where the pointer was, which makes it clickable to open the full panel.
- **Per-task colours.** Eight colours, assigned in rotation as tasks are created and changeable
  from the task editor, the row context menu, or the active card's ⋯ menu. Shown as a dot in the
  HUD, the active card, and every task row, always alongside a status glyph and a spoken colour
  name so nothing depends on colour alone.
- Schema v2 adding the colour attribute, with lightweight migration from v1 verified against a
  real v1 store.
- A second configurable global shortcut, with its own conflict reporting in Settings.
- `Show mini HUD` in the menu-bar menu.

### Fixed

- **Only the first global hot key worked.** Each `GlobalShortcutService` installed its own Carbon
  event handler on the shared dispatcher target, and `InstallEventHandler` rejects a duplicate
  with `eventHandlerAlreadyInstalledErr` — so adding the HUD shortcut left it silently dead. The
  handler is now installed once per process and dispatches by hot-key id.

### Notes

- The schema version stamp is written with the next store save rather than at launch. It is used
  only for diagnostics, and the comment in `CoreDataStack` now says so.

## [1.0.0] — 2026-07-28

Initial implementation.

### Added

**Tasks**
- Daily tasks with title, notes, estimate, manual order, status, and focus time.
- Add, edit, delete with undo, reorder, start, pause, resume, complete, skip, restore, move to
  tomorrow, pull an overdue task back into today, and clear completed.
- Six statuses: upcoming, active, paused, completed, skipped, overdue.
- At most one active task, enforced in the domain layer and reconciled on load.
- Automatic day rollover: unfinished tasks from earlier days become overdue and any session
  running at the boundary is banked.
- Optional automatic promotion of the next task on completion.

**Focus timer**
- Elapsed time derived from persisted timestamps, so it survives panel closure, relaunch, and
  sleep with no per-second writes.
- Estimate, remaining time, and overtime.
- Once-a-minute heartbeat bounding how much time an unclean termination can over-count; stale
  sessions are banked at the last heartbeat and flagged interrupted.

**Accountability**
- System idle detection through `CGEventSource`, requiring no Accessibility permission and
  exposing only a duration.
- Four configurable thresholds — indicator, gentle notification, stronger notification, session
  interrupted — defaulting to 3 / 5 / 10 / 15 minutes.
- Reaching the final threshold flags the session only; it never completes or fails a task.
- Notification actions: Still working, Pause task, Switch task, Complete task, Snooze.
- "Still working" resets escalation and opens a configurable grace period.
- Snooze for 5, 15, or 30 minutes, or until manually resumed.
- Quiet hours, including windows that wrap past midnight.
- Repeat reminders with a configurable cooldown.
- Per-task opt-out for reading, watching, or reviewing.
- Alerts suppressed while paused, while no task is active, and while snoozed.

**Interface**
- 340-point floating `NSPanel` opening beside the pointer, above normal windows, on all Spaces,
  with edge flipping, clamping, multi-monitor support, and recovery when a display is removed.
- Daily progress header, dominant active-task card, task list, and quick-add.
- Menu-bar item with three display styles and full task controls.
- Native settings window: shortcut, launch at login, thresholds, notification behaviour, quiet
  hours, menu-bar style, data reset, diagnostic export, and about.
- Configurable global shortcut, default `⌥Space`, with conflict reporting.
- Keyboard navigation throughout: `⌘N`, `⌘↩`, `⌘⇧↩`, `Space`, arrows, `Delete`, `⌘Z`, `Escape`.
- Light and dark mode, reduced-motion support, VoiceOver labels, durations spoken as durations,
  and status never conveyed by colour alone.
- Empty, error, permission-denied, and degraded-storage states.

**Data**
- Local Core Data store with a programmatic model and a versioned migration plan.
- Repository boundary with Core Data and in-memory implementations.
- Whole-day writes as single transactions.
- Defensive reads repairing negative durations, unknown statuses, corrupt day values, orphaned
  sessions, and empty titles.
- Corrupt stores quarantined rather than deleted, with an in-memory fallback if that also fails.
- Preferences in `UserDefaults`, tolerant of blobs written by other versions.
- Bounded in-memory diagnostic log that never records task content.

**Tests**
- Tests in Swift Testing, with injected clocks, idle values, notification recorders, and
  repositories.

### Notes

- Uses Core Data rather than SwiftData. The SwiftData `@Model` macro plugin ships only with Xcode
  and is unavailable in a Command Line Tools toolchain; Core Data is the same storage engine and
  sits behind the same `TaskRepository` protocol. See the README for the swap path.
- Tests use Swift Testing rather than XCTest, since `XCTest.framework` is likewise Xcode-only.
- Ships without an app icon, which needs Xcode's asset tooling.
- Ad-hoc signed. Distribution to other Macs requires Developer ID signing and notarization.

[1.1.0]: https://github.com/RickyWroe/QuickWins/releases/tag/v1.1.0
[1.0.0]: https://github.com/RickyWroe/QuickWins/releases/tag/v1.0.0
