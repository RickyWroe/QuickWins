# Manual QA checklist

Scenarios are marked:

- **[AUTO]** — covered by an automated test that has been executed. The test name is given.
- **[VERIFIED]** — checked by hand in a running build, with the observed result recorded.
- **[CONFIRMED]** — exercised and confirmed by the repository owner in normal use. Recorded on
  their word rather than from an observed measurement, which is why it is kept distinct from
  **[VERIFIED]**.
- **[PENDING]** — needs a person. A procedure is given. **Not yet performed.**

Nothing below is claimed as tested unless it was actually run.

Run the automated suite with:

```bash
./Scripts/test.sh
```

Last executed: **156 tests in 15 suites, all passing.**

---

## Install and first launch

| # | Scenario | Status | Notes |
|---|---|---|---|
| 1 | Fresh install creates its database | **[VERIFIED]** | `~/Library/Application Support/QuickWins/QuickWins.sqlite` created on first launch. |
| 2 | Menu-bar item appears; no Dock icon | **[VERIFIED]** | Item rendered with the "no task in focus" dashed-circle symbol; `LSUIElement` keeps it out of the Dock. |
| 3 | First launch with no tasks | **[VERIFIED]** | Panel shows "No tasks yet" with an *Add a task* button. |
| 4 | Notification permission accepted | **[PENDING]** | Reset with `tccutil reset Notifications com.rickywroe.quickwins`, relaunch, open Settings › Check-ins, click *Allow notifications…*, accept. Expect no banner in the panel. |
| 5 | Notification permission denied | **[PENDING]** | As above but deny. Expect the panel banner "Notifications are turned off." and check-ins continuing in-panel. Partially covered by **[AUTO]** *Delivery is refused while permission has not been granted* and *An unbundled process reports notifications unavailable rather than trapping*. |

## Core task flow

| # | Scenario | Status | Notes |
|---|---|---|---|
| 6 | Add the first task | **[VERIFIED]** | Typed into quick-add; task appeared under *Upcoming* and survived relaunch. |
| 7 | Add task — validation | **[AUTO]** | *A blank title is rejected rather than creating an unnamed task*; *An empty title surfaces an actionable error and creates nothing*. |
| 8 | Start a task | **[VERIFIED]** | Active-task card showed *Current focus* with a running timer. |
| 9 | Pause and resume | **[VERIFIED]** | Card showed `0:43 elapsed` and the *Paused* status line with a pause glyph. **[AUTO]** *Pause and resume cycles accumulate without double counting*. |
| 10 | Complete a task | **[VERIFIED]** | Task moved to *Done*, struck through, with `34m` focus retained and progress `1/2`. |
| 11 | Skip a task | **[AUTO]** | *Skipping preserves focus time already spent but sets no completion date*. |
| 12 | Reorder tasks | **[AUTO]** | *Reordering renumbers the day so order stays dense*; *Results come back in manual order, and that order is preserved across reloads*. |
| 13 | Delete and undo | **[AUTO]** | *A deleted task can be restored, so deletion needs no confirmation dialog*. |
| 14 | Restore a completed task | **[AUTO]** | *Restoring a completed task with banked time returns it as paused, not upcoming*. |
| 15 | Move unfinished task to tomorrow | **[AUTO]** | *Moving a task to tomorrow takes it out of today's list*. |
| 16 | Clear completed | **[AUTO]** | *Clearing completed tasks leaves open ones alone and is still undoable*. |
| 17 | Exactly one active task | **[AUTO]** | *Only one task can be active no matter how many starts are issued*; *Two tasks stored as active are repaired to one on load*. |
| 18 | Auto-select next task | **[AUTO]** | *Completing promotes the next task when that setting is on* / *…leaves nothing running when auto-advance is off*. |

## Timer durability

| # | Scenario | Status | Notes |
|---|---|---|---|
| 19 | Relaunch with an active task | **[VERIFIED]** | A session seeded as started 2,058 s earlier was restored and reported `34m` — elapsed time reconstructed from timestamps alone. **[AUTO]** *Relaunching mid-session keeps the timer running when the heartbeat is fresh*. |
| 20 | Relaunch with a paused task | **[AUTO]** | *A stopped task reports only its banked time*. |
| 21 | Sleep and wake with an active task | **[AUTO]** | *Sleeping through a session does not credit the sleep as focus time*. **[PENDING]** on real hardware: start a task, close the lid for 10 min, reopen. Expect the task paused, banked time ≈ pre-sleep, and an *Interrupted* marker. |
| 22 | Force quit mid-session | **[AUTO]** | *A crash or force quit banks time only up to the last heartbeat*. |
| 23 | No per-second writes | **[AUTO]** | *A running session writes at most one heartbeat per minute* — 120 ticks produce exactly 2 writes. |
| 24 | Midnight rollover | **[AUTO]** | *Crossing midnight flags yesterday's unfinished work as overdue*; *A session running across midnight is banked rather than left open*. **[PENDING]** on real hardware: leave a task open overnight. |
| 25 | No active task | **[AUTO]** | *No alerts are produced while nothing is running*. **[VERIFIED]** panel shows "Nothing in focus". |

## Accountability

| # | Scenario | Status | Notes |
|---|---|---|---|
| 26 | Idle escalation ladder | **[AUTO]** | Six tests, one per rung: quiet below 3 min, indicator at 3, gentle notification at 5, stronger + panel at 10, interrupted at 15, and *the interruption is flagged once*. |
| 27 | Only one notification per escalation | **[AUTO]** | *Sustained idle time on a running task produces exactly one notification*. |
| 28 | "Still working" acknowledgment | **[AUTO]** | *Still working clears escalation and opens a grace window*; *An acknowledgment stops the very next evaluation from re-alerting*; *Alerts resume once the grace period expires*. |
| 29 | Snooze | **[AUTO]** | *Snoozing suppresses alerts for its duration*; *Alerts return once the snooze expires*; *Snooze until resumed has no expiry*. |
| 30 | Quiet hours | **[AUTO]** | *Quiet hours suppress delivery while still advancing the alert clock*; *A quiet-hours window that wraps past midnight is evaluated correctly*. |
| 31 | Alerts off while paused / no task | **[AUTO]** | *No alerts fire while the active task is paused*; *No alerts fire while no task is running*. |
| 32 | Per-task opt-out | **[AUTO]** | *A task with idle detection switched off is never escalated*. |
| 33 | Task switch resets escalation | **[AUTO]** | *Switching tasks restarts escalation from calm*. |
| 34 | Notification actions | **[PENDING]** | Set thresholds to their minimum, start a task, stop touching the Mac. When the banner appears, exercise each of *Still working*, *Pause task*, *Switch task*, *Complete task*, *Snooze*. Expect the matching state change in the panel. Routing is implemented in `AppDelegate.handle(actionIdentifier:taskIDString:)`; the action set is **[AUTO]**-checked by *Every alert action offers a way out that is not completing the task*. |
| 35 | Idle source unavailable | **[AUTO]** | *An unavailable idle source disables escalation instead of assuming absence*. |

## Panel behaviour

| # | Scenario | Status | Notes |
|---|---|---|---|
| 36 | Opens beside the pointer | **[VERIFIED]** | Opened at the pointer's display, offset down-and-right, fully inside the visible frame. |
| 37 | Multiple monitors | **[VERIFIED]** | On a three-display setup (built-in plus two externals at negative origins) the panel opened on the display containing the pointer. **[AUTO]** *The pointer's own display is chosen on a multi-monitor desk*; *A display arranged to the left of the main one is handled*. |
| 38 | Screen-edge positioning | **[AUTO]** | *Near the right edge the panel mirrors to the pointer's left*; *…bottom edge…*; *A bottom-right corner pointer flips on both axes at once*; and a sweep asserting *The panel always ends up fully on screen* across the whole display. |
| 39 | Display change while open | **[AUTO]** | *An open panel is pulled back when its display disappears*. **[PENDING]** on real hardware: open the panel on an external display, unplug it. |
| 40 | Escape dismisses | **[PENDING]** | Open the panel, press Escape. Implemented via `FloatingPanel.cancelOperation`. |
| 41 | Click outside dismisses | **[PENDING]** | Open the panel, click another app. Expect dismissal and focus returning to that app. |
| 42 | Click outside does *not* dismiss mid-edit | **[PENDING]** | Open a task in the editor sheet, click outside. Expect the panel to stay (guarded by `model.isEditingModally`). |
| 43 | Focus returns on dismiss | **[PENDING]** | Note the frontmost app, open the panel, press Escape. Expect that app frontmost again. |
| 44 | Panel above normal windows | **[VERIFIED]** | Window level 3 (`.floating`), drawn over other applications' windows. |
| 45 | Works across Spaces | **[PENDING]** | Switch Space, press the shortcut. `collectionBehavior` includes `.canJoinAllSpaces`. |
| 46 | Full-screen app behaviour | **[PENDING]** | Enter full screen in another app, press the shortcut. `.fullScreenAuxiliary` is set; macOS does not always allow this — see README limitation 5. |
| 47 | Reopening the app shows the panel | **[VERIFIED]** | `open dist/QuickWins.app` while running raised the panel. |

## Mini HUD and task colours

| # | Scenario | Status | Notes |
|---|---|---|---|
| M1 | HUD is on screen at launch, unprompted | **[VERIFIED]** | With no keypress, a 90×28 window at level 3 was present and captured, showing the colour dot and elapsed time. |
| M1b | ⌥Q toggles the HUD off and on | **[CONFIRMED]** 2026-07-29 | Confirmed by the owner, including that the choice survives a relaunch. Registration itself is **[VERIFIED]** — the unified log records `Registered global shortcut ⌥Q` at launch. |
| M2 | HUD does not steal keyboard focus | **[PENDING]** | Start typing in another app, press ⌥Q, keep typing. The panel is created with `acceptsKey: false` and shown with `orderFrontRegardless`. |
| M3 | HUD auto-hides | **[PENDING]** | Default 5 s; set to 0 in Settings for "stays open". |
| M4 | HUD follows the pointer | **[VERIFIED]** | Two independent checks. A harness running the follow loop against a live `NSPanel` recorded 27 repositions across 27 distinct positions, 0 placement mismatches, fully on screen at every sample including edge and menu-bar cases. Then against the **running app**, reading its real window position out of the window server: 13 matches, 0 mismatches. Note `CGWarpMouseCursorPosition` emits no events, so that second run exercised the worst case — pure polling with the monitors never firing. |
| M4d | Idle cost of an always-on HUD | **[VERIFIED]** | `top`, 16 samples, 100% = one core. HUD off: 2–4%. HUD on, pointer still: 2.3–3.6%. HUD on, pointer moving: ~4% typical, ~18% peak. The adaptive backoff makes a parked HUD free. |
| M4b | HUD is click-through while following | **[CONFIRMED]** 2026-07-29 | Confirmed by the owner: a click lands on whatever sits under the HUD rather than being swallowed. `ignoresMouseEvents` is set whenever following is on. |
| M4c | Clicking the HUD opens the panel with following off | **[CONFIRMED]** 2026-07-29 | Confirmed by the owner. Settings › General › Mini HUD › turn off *Follow the pointer*, then click the capsule. |
| M5 | HUD shows the task colour and elapsed time | **[PENDING]** | A pause glyph sits inside the dot when stopped, so run state is not colour-only. |
| M6 | New tasks get distinct colours | **[AUTO]** | *New tasks are handed distinct colours so a day's list is legible at a glance*. |
| M7 | Changing a colour persists | **[AUTO]** | *Changing a task's colour persists it*; *Colour survives a round trip through the store*. |
| M8 | Colour picker in the editor | **[PENDING]** | Selection is marked with a ring **and** a checkmark, not colour alone. |
| M9 | Migration from a pre-colour database | **[AUTO]** + **[VERIFIED]** | *A v1 store opens under v2 with its tasks intact and no data loss*. Also verified live: the running app logged `Store schema 1 opened by app schema 2` against a real v1 database and the existing task survived. |
| M10 | Unknown or missing colour value | **[AUTO]** | *A row written before colours existed reads back as the neutral fallback*; *An unrecognised colour name falls back rather than failing the read*. |
| M12 | Resting message appears after 15s | **[VERIFIED]** | Observed live: the pointer parked, and ~14 s later the HUD window grew from 69×28 to 107×45 and rendered "Small steps are still steps." under the timer. It held for the rest of the still period. |
| M13 | Message clears on movement | **[VERIFIED]** | Same run: the moment the pointer moved, the window shrank back to 69×28 and repositioned. |
| M14 | One message per rest, not a rotation | **[VERIFIED]** | The window stayed at 107×45 across three consecutive 2 s samples without changing size, i.e. no new message was swapped in. |
| M15 | Messages respect the ten-word cap | **[AUTO]** | *Every message is at most ten words*; *No message claims to know how the work is going*. |
| M16 | No message while paused, idle, or snoozed | **[CONFIRMED]** 2026-07-29 | Confirmed by the owner in normal use: no resting message appears while the task is paused, and a visible one clears once idle detection stops reading calm. Gated by `AppModel.canShowHUDMessage`. To re-check: pause the task and rest the pointer, then leave the Mac untouched past the 3-minute idle threshold. |
| M17 | HUD survives sustained message show/hide cycling | **[VERIFIED]** | Regression cover for the recursion crash. A stress harness drives 12 move-then-rest cycles, each forcing the capsule to grow for a message and shrink again, while the HUD follows the pointer. Before the fix this killed the app; after it, three consecutive rounds (36 cycles) with the process alive and zero crash reports. |
| M11 | Both hot keys work together | **[VERIFIED]** | Both `⌥Space` and `⌥Q` register at launch. This regressed once — see the 1.1.0 changelog — and the log is the check. |

## Menu bar and settings

| # | Scenario | Status | Notes |
|---|---|---|---|
| 48 | Menu-bar item shows state | **[VERIFIED]** | Dashed circle with no task in focus; symbol and label switch with status. |
| 49 | Menu-bar display styles | **[PENDING]** | Settings › General, switch between icon only / icon and time / icon and title. |
| 50 | Menu commands | **[PENDING]** | Exercise Pause, Complete, Open task panel, Today's tasks, Snooze, Settings, Quit. |
| 51 | Settings persist | **[AUTO]** | *Settings changes are written through immediately*; *Settings survive a store round trip*. |
| 52 | Corrupt settings blob | **[AUTO]** | *A corrupt settings blob falls back to defaults instead of throwing at launch*. |
| 53 | Partial settings blob | **[AUTO]** | *A blob written by an older build keeps its known keys and defaults the rest*. |
| 54 | Global shortcut conflict | **[PENDING]** | Record a combination already held by macOS (for example ⌘Space). Expect Settings to show "That keyboard shortcut is already claimed…" and the menu-bar item to keep working. |
| 55 | Shortcut recording | **[PENDING]** | Settings › General › Record, press a combination with at least one modifier. Bare keys are rejected by design. |
| 56 | Launch at login | **[PENDING]** | Move the app to `/Applications`, enable the toggle, log out and back in. |
| 57 | Data reset | **[AUTO]** | *Resetting data clears tasks and returns settings to defaults*. |
| 58 | Export diagnostic log | **[PENDING]** | Settings › Advanced › Export. Confirm the file contains no task titles. |

## Data integrity

| # | Scenario | Status | Notes |
|---|---|---|---|
| 59 | Corrupt database file | **[AUTO]** | *An unreadable store file is quarantined and the app still opens* — writes garbage to the store path, asserts recovery and that the bad file is retained. |
| 60 | Negative stored duration | **[AUTO]** | *A negative stored duration is repaired on read rather than shown as negative time*. |
| 61 | Unknown status value | **[AUTO]** | *An unrecognised status falls back to upcoming instead of failing the load*. |
| 62 | Corrupt day value | **[AUTO]** | *A nonsense day value falls back to the creation date's day*. |
| 63 | Orphaned session | **[AUTO]** | *A stored session on a non-active task is banked rather than left dangling*. |
| 64 | Empty title in storage | **[AUTO]** | *An empty title is replaced so the row is still renderable*. |
| 65 | Save failure | **[AUTO]** | *A failed write keeps the change on screen and reports it rather than failing silently*. |
| 66 | Schema version stamped | **[AUTO]** | *A fresh store is stamped with the current schema version*. |

## Accessibility and appearance

| # | Scenario | Status | Notes |
|---|---|---|---|
| 67 | Dark mode | **[VERIFIED]** | Panel rendered correctly in dark mode; materials, contrast and accent all correct. |
| 68 | Light mode | **[PENDING]** | System Settings › Appearance › Light. All colours are semantic (`.primary`, `.secondary`, materials, `Color.accentColor`), so this should follow automatically — but it has not been looked at. |
| 69 | Increased contrast | **[PENDING]** | Accessibility › Display › Increase contrast. |
| 70 | Reduced motion | **[PENDING]** | Accessibility › Display › Reduce motion. `PanelRootView` and `ActiveTaskCard` read `accessibilityReduceMotion` and drop animations. |
| 71 | Larger text | **[PENDING]** | All text uses semantic font styles; check the active card and rows do not clip. |
| 72 | Keyboard-only operation | **[PENDING]** | Without touching the mouse: ⌥Space, ⌘N, type, Return, ↑/↓, ⌘↩, Space, ⌘⇧↩, Escape. A focus ring was **[VERIFIED]** visible on the *Start* button. |
| 73 | VoiceOver labels | **[PENDING]** | Enable VoiceOver, navigate the panel. Every control has an explicit `accessibilityLabel`; times are announced through `FocusTimeFormatter.spoken` so `34:18` is read as "34 minutes 18 seconds" rather than a clock time — **[AUTO]** *VoiceOver time is spoken as a duration, not as a time of day*. |
| 74 | Status not by colour alone | **[VERIFIED]** | *Paused* shown as a glyph plus the word; escalation levels carry both a symbol and a text label. |

## Performance

| # | Scenario | Status | Notes |
|---|---|---|---|
| 75 | Idle CPU | **[PENDING]** | Leave QuickWins running with no active task for an hour; check Activity Monitor. The ticker stops entirely when nothing is running and no panel is visible (`AppModel.syncTicker`). |
| 76 | Long focus session | **[PENDING]** | Run a task for several hours; watch memory in Activity Monitor. The diagnostic log is capped at 500 entries — **[AUTO]** *The buffer is bounded so a long-running session cannot grow memory without limit*. |
| 77 | No duplicate timers | **[AUTO]** | *Starting twice replaces the schedule rather than leaving two tickers running*. |
| 78 | Cold launch | **[VERIFIED]** | Menu-bar item present within roughly a second of `open`. |
| 79 | No network | **[VERIFIED]** | `grep -rIn "URLSession\|NWConnection\|CFNetwork\|http://\|https://" Sources/` returns nothing. |
