# QuickWins

A lightweight native macOS daily task tracker that lives in the menu bar and opens as a compact
floating panel beside your pointer.

QuickWins is an accountability tool, not a project manager. It asks one question — *what are you
working on right now?* — keeps a timer on it, and checks in when your Mac has seen no input for a
while. It never claims you are slacking; it asks, and every prompt has a way out that is not
"complete the task".

```
TODAY 2/5                      35m

  Current focus
  Build landing page
  34:18 elapsed
  10:42 left of 45m
  [ Pause ]  [ Finish ]  …

Upcoming
  ○ Send proposal
  ○ Review campaign
  ○ Exercise

+ Add task
```

---

## Requirements

| | |
|---|---|
| macOS | 14.0 (Sonoma) or later |
| Toolchain | Swift 6.0+ — Xcode 15+, or Command Line Tools alone |
| Dependencies | None. Apple frameworks only. |

No account, no network, no backend, no third-party packages.

---

## Build and run

```bash
./Scripts/build_app.sh
```

That compiles a release build, assembles `dist/QuickWins.app`, and ad-hoc signs it. Then:

```bash
open dist/QuickWins.app
```

QuickWins appears in the menu bar with no Dock icon. To keep it around, drag `dist/QuickWins.app`
into `/Applications` and enable **Launch at login** in Settings.

To build without bundling:

```bash
swift build -c release
```

> The executable must run from the `.app` bundle for notifications and launch-at-login to work —
> both need a bundle identifier. QuickWins detects the unbundled case and disables those two
> features rather than crashing, so `swift run` is still useful for development.

---

## Test

```bash
./Scripts/test.sh
```

141 tests across 13 suites, written with **Swift Testing**. They cover the domain rules, the
repository, timer durability, the accountability state machine, screen positioning, notification
scheduling, settings storage, schema migration, and defensive handling of corrupt data — all with
injected clocks and idle values, so nothing sleeps and nothing is flaky.

The script exists because the Swift Testing framework bundled with Command Line Tools is not on
the default search path the way it is inside Xcode. With a full Xcode install, plain `swift test`
also works.

---

## Architecture

Two targets, with a hard boundary between them.

**`QuickWinsCore`** — a library with no SwiftUI and no AppKit. All behaviour lives here, which is
why the full lifecycle is testable without a UI.

```
Domain/     DailyTask, TaskStatus, TaskColor, DayKey, FocusSession,
            AccountabilityState, TaskRules
Data/       CoreDataStack, MigrationPlan, TaskRepository (+ Core Data
            and in-memory implementations), AppSettings, SettingsStore
Services/   TimeSource, IdleDetectionService, AccountabilityEngine,
            NotificationService, TimerService, LaunchAtLoginService,
            ScreenPositioning, DiagnosticLogger, TaskCoordinator
```

**`QuickWins`** — the executable: app lifecycle, the `NSPanel`, and the SwiftUI views.

```
App/        QuickWinsApp, AppDelegate, AppEnvironment, AppModel
Services/   FloatingPanel, FloatingPanelController, MiniHUDController,
            GlobalShortcutService
Features/   PanelRootView, ProgressHeader, ActiveTaskCard, TaskListView,
            QuickAddField, TaskEditorView, SettingsView, MenuBarViews,
            MiniHUDView, ShortcutRecorder, Theme
```

### Decisions worth knowing

**Task state transitions are pure functions.** `TaskRules` takes the day's tasks and returns a new
array. The *never more than one active task* invariant is enforced there, not in a view, so it
holds no matter which surface — panel, menu bar, or notification action — initiated the change. A
whole-day result is then written as one transaction, so switching tasks (which pauses one and
starts another) can never be persisted half-applied. The coordinator also reconciles the invariant
on load, in case a crash or an older build left two active rows behind.

**Elapsed time is derived from timestamps, never counted.** A task stores banked focus seconds plus
the instant the current session started. Elapsed time is arithmetic on those two values, so it is
correct after the panel closes, after a relaunch, and after sleep — with no per-second writes.

**A heartbeat bounds what a crash can over-count.** Pure wall-clock arithmetic would credit an
eight-hour sleep as eight hours of focus. A running session writes a heartbeat once a minute; on
launch or wake, anything past the last heartbeat is discarded and the session is flagged
interrupted. One write per minute, not sixty.

**The accountability engine is a deterministic state machine.** Given a state, an idle reading, a
config and an instant, `AccountabilityEngine.evaluate` returns the next state and a list of
effects. The escalation ladder is tested exhaustively without waiting fifteen real minutes.

**Screen positioning is pure geometry.** It operates on plain rectangles, not `NSScreen`, so
multi-monitor behaviour, edge flipping and clamping are all verified headlessly. The panel and the
mini HUD share it, so both appear in a consistent spot relative to the pointer.

**One Carbon event handler, many hot keys.** `InstallEventHandler` refuses a duplicate
registration of the same callback on the same target, so the handler is installed once per process
and dispatches by hot-key id. Installing per service instance silently breaks every hot key after
the first.

**The ticker only runs when something depends on it.** No active task, no visible panel and no
visible HUD means no timer at all.

**The HUD's follow loop adapts to whether the pointer is moving.** Mouse monitors alone are not
enough — a cursor can move without this process seeing an event, and a warp generates none at all
— so polling is the source of truth and the monitors exist only to snap back to the fast cadence
the moment the pointer stirs. Moving it: 30 Hz. Still for three quarters of a second: 2 Hz. That
matters because an always-on HUD spends most of its life parked. Measured on the machine this was
built on, with `top`, where 100% is one core:

| State | CPU |
|---|---|
| HUD off (baseline) | 2–4% |
| HUD on, pointer still | 2.3–3.6% |
| HUD on, pointer moving | ~4% typical, to ~18% during vigorous movement |

At rest the HUD is indistinguishable from having it off. While following, the cost is the window
move itself — measurably not the drop shadow (disabled while following) and only marginally the
material backdrop (swapped for a flat fill while following, which also reads better over
arbitrary content).

### Core Data instead of SwiftData

The brief asked for SwiftData. **This project uses Core Data directly**, behind the same
`TaskRepository` protocol.

SwiftData's `@Model` macro is expanded by `libSwiftDataMacros.dylib`, which ships **only with
Xcode** — it is absent from a Command Line Tools toolchain, and this project was built on a machine
with no Xcode installed. Any `@Model` type fails to compile with
`plugin for module 'SwiftDataMacros' not found`.

Core Data is SwiftData's own storage engine, so nothing is lost functionally: persistence,
migrations, transactions, uniqueness constraints and ordering all behave identically. The model is
built programmatically in `MigrationPlan.swift` rather than from an `.xcdatamodeld` bundle, which
also removes the need for Xcode's model editor.

Swapping in SwiftData later means writing one new `TaskRepository` implementation. The domain
layer, the services, the views and every test stay untouched.

`XCTest.framework` is likewise Xcode-only, so the suite is written entirely in Swift Testing.

---

## Keyboard shortcuts

**Global**

| Shortcut | Action |
|---|---|
| `⌥Space` | Show or hide the full panel (configurable) |
| `⌥Q` | Show or hide the mini HUD beside the pointer (configurable) |

**While the panel is open**

| Shortcut | Action |
|---|---|
| `⌘N` | Focus the quick-add field |
| `⌘↩` | Start the selected task |
| `⌘⇧↩` | Complete the active task |
| `Space` | Pause or resume (ignored while typing) |
| `↑` `↓` | Move the selection |
| `Delete` | Delete the selected task |
| `⌘Z` | Undo the last delete |
| `Escape` | Dismiss the panel |

`⌥Space` is the default because it is unassigned in a stock macOS install — `⌘Space` belongs to
Spotlight and `⌃Space` to input-source switching. If macOS refuses the registration, Settings shows
the conflict and the menu-bar item still opens the panel.

> **Avoid a plain Shift combination.** A global hot key *consumes* the keystroke system-wide, so
> binding `⇧Q` would stop you typing a capital Q in every app on the Mac. Every default here
> carries a non-Shift modifier for that reason. The recorder also rejects a bare key with no
> modifier at all.

## Mini HUD

A capsule roughly the size of a menu-bar item, showing the current task's colour and its elapsed
time and nothing else — for when you want to check in without opening the panel.

```
 ●  34:18
```

- **Stays on screen** until you switch it off with `⌥Q` or the menu-bar item, and that choice
  survives a relaunch. Turn *Keep the HUD on screen* off in Settings and the shortcut becomes a
  peek that hides itself after a few seconds instead.
- **Follows the pointer**, staying 12 points down and to the right of it, flipping at screen
  edges and moving between displays as you do.
- **Click-through while following.** A window glued to the cursor cannot be clicked — you can
  never reach it — and one that accepted clicks would swallow them on whatever is underneath. So
  it ignores mouse events entirely and never gets in your way.
- **Never takes keyboard focus**, so pressing `⌥Q` mid-sentence does not interrupt typing.
- Hides itself after a few seconds (configurable, or set to stay open).
- A pause glyph sits inside the dot when the timer is stopped, so run state is never conveyed by
  colour alone.

Turn **Follow the pointer** off in Settings and it reverts to being placed once where the pointer
was, which makes it clickable — clicking then opens the full panel.

Each task carries one of eight colours, handed out in rotation as tasks are created so a day's
list is legible immediately. Change one from the task editor, the row's context menu, or the
active card's ⋯ menu. Colour is always accompanied by the colour's name in VoiceOver and by a
status glyph on screen — it is identity, never state.

---

## Permissions

QuickWins asks for as little as macOS allows.

| Permission | Required? | Why |
|---|---|---|
| Notifications | Optional | Accountability check-ins. Denied is handled: check-ins become panel-only and a banner explains how to re-enable them. |
| Launch at login | Optional | Registered through `SMAppService`, toggled by you in Settings. |
| Accessibility | **Never requested** | Not needed. |
| Screen Recording | **Never requested** | Not needed. |
| Full Disk Access | **Never requested** | Not needed. |

Inactivity is measured with `CGEventSource.secondsSinceLastEventType`, which returns **a duration
and nothing else**. It needs no permission prompt and cannot report what was typed or clicked. The
`.hidSystemState` source counts hardware input only, so synthetic events from scripts are not
mistaken for a person being present.

---

## Privacy

- Everything is stored **locally**, in `~/Library/Application Support/QuickWins/QuickWins.sqlite`.
- **No account.** There is nothing to sign into.
- **Nothing is transmitted.** The app makes no network requests of any kind.
- **No analytics**, no telemetry, no crash reporting to anyone.
- QuickWins does **not** inspect what you type, your browser history, your files, your screen
  contents, or window titles.
- It uses **system idle duration only** — one number, how many seconds since the last input — to
  decide when to check in.
- Notification and launch-at-login permissions are optional and entirely under your control.
- The diagnostic log records app events and task **identifiers**. It never contains task titles,
  notes, or anything you type, so an exported log is safe to share.

Full statement: [PRIVACY.md](PRIVACY.md).

---

## Data storage

| What | Where |
|---|---|
| Tasks | `~/Library/Application Support/QuickWins/QuickWins.sqlite` |
| Settings | `UserDefaults`, under `com.rickywroe.quickwins.settings` |
| Diagnostic log | In memory (last 500 entries); exported only when you ask |

**Settings › Advanced › Reset all data** deletes every task and restores defaults.

If the database cannot be opened, QuickWins renames it to `QuickWins.sqlite.corrupt-<timestamp>`,
starts a fresh one, and tells you. The bad file is kept rather than deleted, so nothing is
destroyed silently. If even that fails, the app falls back to in-memory storage for the session and
says clearly that nothing will be saved.

---

## Known limitations

These are real, and stated plainly.

1. **No SwiftData.** See the section above. Core Data behind the same protocol.
2. **No app icon.** Compiling an `.icns` asset catalogue needs Xcode's asset tooling. The menu-bar
   item uses SF Symbols and looks correct; only the bundle icon is missing.
3. **Ad-hoc signed only.** Fine on the machine that built it. Distributing to other Macs needs a
   Developer ID signature and notarization, which need a paid Apple Developer account.
4. **Reordering is menu-driven, not drag-and-drop.** `TaskRules.reorder` and the coordinator both
   support arbitrary reordering and are tested; the panel exposes it through commands rather than
   dragging, because drag-and-drop inside a borderless non-activating panel is unreliable.
5. **Full-screen apps.** The panel is `.fullScreenAuxiliary` and appears over full-screen spaces
   where macOS permits it. macOS does not always permit it, and QuickWins cannot override that.
6. **No trackpad haptics for alerts.** A MacBook has no phone-style vibration, and trackpad haptics
   only fire in response to direct interaction — they are useless for an unattended alert, so they
   are not used or advertised.
7. **Timer restoration is bounded by the heartbeat.** After a force quit or long sleep, up to 60
   seconds of genuine focus time may be discarded. That is deliberate: under-counting is safer than
   crediting an overnight sleep as work.
8. **Some UI paths are verified manually.** See [docs/MANUAL_QA.md](docs/MANUAL_QA.md) for exactly
   which, and how to check them.

---

## Troubleshooting

**The panel does not appear when I press ⌥Space.**
Another app may hold the shortcut. Open Settings › General — a conflict is reported there. Record a
different combination, or use the menu-bar item. Launching QuickWins again (Finder, Spotlight, or
`open`) also shows the panel.

**The panel opened on the wrong monitor.**
It opens on the display containing the pointer, which is not always the one you are looking at.
Turn off *Open beside the pointer* in Settings to centre it on the active screen instead.

**No notifications arrive.**
Check System Settings › Notifications › QuickWins. If permission was denied, the panel shows a
banner and check-ins continue there. Notifications also require running from `QuickWins.app`
rather than the bare executable.

**Launch at login is greyed out.**
`SMAppService` needs a real bundle. Run `dist/QuickWins.app`, ideally from `/Applications`.

**Check-ins fire while I am reading or in a meeting.**
Snooze from the menu bar or the panel's ⋯ menu (5/15/30 minutes, or until you resume), or turn off
*Inactivity check-ins* for that specific task in the editor. Thresholds and quiet hours are in
Settings › Check-ins.

**"The task database was rebuilt after a read error."**
The store could not be opened and was quarantined next to the original as
`QuickWins.sqlite.corrupt-<timestamp>`. Your previous data is in that file.

**Something is wrong and I need detail.**
Settings › Advanced › Export diagnostic log. It contains no task content.

---

## Manual QA

[docs/MANUAL_QA.md](docs/MANUAL_QA.md) lists every scenario, which are covered by automated tests,
and step-by-step procedures for the ones that need a person.

---

## License

MIT. See [LICENSE](LICENSE).
