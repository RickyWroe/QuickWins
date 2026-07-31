# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] — 2026-07-31

### Added

- **Focus-session history (schema v3).** Every completed stretch of focus is recorded with its
  own start, end and duration. A task only ever stored a running total, which says how long but
  never when — and "Clear completed" deleted it. History now lives in its own entity and outlives
  the tasks that produced it. A stretch crossing midnight is split so each day is credited
  separately; a zero or backwards span records nothing, so a clock change cannot invent focus.
- **Day types.** Days are working days or days off, resolved from a weekly pattern with per-day
  overrides. Only overrides are stored, so a normal week writes nothing. Days off are skipped in
  streak maths — they neither break a streak nor extend it — which is what lets a contribution
  graph tell "I did not work" from "I chose not to work".
- **Statistics**: totals, average and longest session, interruption rate, per-task breakdown, and
  focus by hour of day. Long sessions are spread across the hours they spanned rather than
  credited to whichever hour they began in.
- **The companion.** A tortoise that gets sleepy while nothing is happening and wakes the moment
  you touch the keyboard, shown in the mini HUD and on the active-task card. Its body takes the
  task's colour and brightens as the day approaches its goal.
- Working weekdays, a daily focus goal, and a toggle for the companion in Settings.

### Notes

- **The companion gets sleepy, not sick.** QuickWins can only observe how long the system has
  gone without input; it cannot see whether you are working. A creature that sickened would
  assert knowledge the app does not have, and would wilt through every meeting and every long
  read. Sleep is literally true, recovers instantly, and is the floor — there is no state below
  it and nothing to repair. A test asserts no state description implies harm.
- **Backfilled history is flagged and quarantined from time-of-day analysis.** Existing tasks are
  reconstructed once from their stored totals, but their clock times are a guess. Reporting a
  guess back as your best working hours would be fabrication, so those records count toward
  totals and nothing else.
- Peak hours are withheld until at least ten genuinely observed sessions exist, rather than
  naming an hour on thin evidence.

## [1.1.1] — 2026-07-29

### Fixed

- **The app crashed repeatedly while the mini HUD was on screen.** Four `EXC_BAD_ACCESS` /
  "stack size exceeded due to excessive recursion" crashes in normal use, with the faulting stack
  running `MiniHUDController.reposition` → `-[NSWindow _setFrameCommon:display:fromServer:]` →
  `displayIfNeeded` → view layout → `NSISEngine` and back again.

  Setting a window frame runs a synchronous layout pass. Because the HUD's hosting controller was
  configured with `sizingOptions = [.preferredContentSize]`, that layout could resize the window,
  which re-entered the frame change — move, layout, resize, move, until the stack was exhausted.
  Moving the window at pointer rate made it near-certain, and a resting message resizing the
  capsule made it worse.

  The window is now sized explicitly by the controller and never by SwiftUI layout, measured with
  `sizeThatFits(in:)` against a fixed proposal rather than the view's own `fittingSize` — feeding
  the latter back in as the window size makes each pass measure a smaller view, ratcheting the HUD
  down to nothing. A re-entrancy guard around every frame change backs this up.

  Two earlier attempts did not fix it and are recorded here because the stack trace, not
  reasoning, is what identified the cause: removing `layoutIfNeeded()` (a real hazard, and still
  removed) and replacing a flexible `.frame(maxWidth:)` with a fixed width (also still in place).
  Both were contributing hazards; neither was sufficient.

### Changed

- The resting message sits in a fixed-width block, so the HUD is a consistent size whenever a
  message is showing rather than hugging each message's length. Predictable geometry is what keeps
  the layout non-recursive.
- The size-change animation on the HUD was removed; animating a window's content size fights
  explicit sizing.

## [1.1.0] — 2026-07-29

### Added

- **Mini HUD.** A compact capsule beside the pointer showing the current task's colour and elapsed
  time, on `⌥Q` by default. It never takes keyboard focus and hides itself after a configurable
  delay.
- **Resting messages in the HUD.** After the pointer has been still for a configurable 15 seconds,
  the capsule grows to show one short line and holds it until the pointer moves. Shown only while
  a task is running and while idle detection reads calm, so encouragement never collides with an
  accountability prompt. Sixteen messages, each capped at ten words and none of them claiming to
  know how the work is going; both constraints are enforced by tests.
- **The HUD stays on screen by default**, restored at launch, with `⌥Q` and the menu-bar item
  acting as a show/hide switch whose state persists. *Keep the HUD on screen* can be switched off
  in Settings to get peek-and-auto-hide behaviour instead.
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

### Performance

- The follow loop adapts its cadence: 30 Hz while the pointer moves, 2 Hz once it has been still.
  Measured with `top` (100% = one core), an on-screen HUD with a still pointer costs 2.3–3.6%,
  indistinguishable from the 2–4% baseline with it switched off.
- The window shadow is disabled and the material backdrop replaced with a flat fill while
  following. Both were measured; the shadow made no difference and the material only a small one,
  so the remaining cost is the window move itself.

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

[1.2.0]: https://github.com/RickyWroe/QuickWins/releases/tag/v1.2.0
[1.1.1]: https://github.com/RickyWroe/QuickWins/releases/tag/v1.1.1
[1.1.0]: https://github.com/RickyWroe/QuickWins/releases/tag/v1.1.0
[1.0.0]: https://github.com/RickyWroe/QuickWins/releases/tag/v1.0.0
