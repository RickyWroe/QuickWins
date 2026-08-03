# QuickWins

**A macOS menu-bar app that turns "where did today go?" into an answer you can look at.**

You name what you're working on. It runs a timer on exactly one thing at a time, notices when your
Mac goes quiet, and keeps a record. After a few weeks you have a contribution graph of your own
attention — when you focus, for how long, and how often something breaks it.

```
TODAY 2/5                      35m          ●  34:18        ← beside your cursor
                                            Still here. Still going.
  Current focus
  🐢 Build landing page
  34:18 elapsed
  10:42 left of 45m
  [ Pause ]  [ Finish ]  …

Upcoming
  ○ Send proposal
  ○ Review campaign

+ Add task
```

---

## The outcome

Three things, in order of how much they change your day:

**One task runs at a time — enforced, not suggested.** Starting something pauses whatever was
running. You cannot have four things "in progress." Every switch is a decision you have to make on
purpose, and the app records that you made it.

**Time is measured, not estimated.** Elapsed time comes from timestamps, so it survives quitting,
sleeping and crashing. What you see is what actually happened, including the parts you'd rather
round up.

**Your attention becomes a picture.** A GitHub-style graph over six months, plus streaks, session
lengths, interruption rate and — once there's enough data — the hours you actually focus best.

What it deliberately does **not** do: tell you that you were unproductive. The app can see one
thing, seconds since your last keypress. It never claims to know more than that.

---

## The three surfaces

| Surface | Shortcut | For |
|---|---|---|
| **Mini HUD** | `⌥Q` | A capsule beside your cursor: task colour, elapsed time, and a tortoise that dozes off when the Mac goes quiet. Click-through, so it never blocks anything. |
| **Panel** | `⌥Space` | Today's list. Add, start, pause, finish, reorder, undo. Opens beside your pointer, closes on Escape. |
| **Dashboard** | menu bar → Statistics | The graph and the numbers. |

**Accountability** is deliberately weak. At 3 minutes of no input the indicator changes; at 5 and
10 a notification asks *"still on this?"*; at 15 the session is flagged interrupted — the task
itself is never touched. Every prompt offers *Still working*, *Pause*, *Switch*, *Snooze*. Snooze
for reading or meetings, or switch check-ins off per task.

---

## Quick start

```bash
./Scripts/build_app.sh && open dist/QuickWins.app
```

```bash
./Scripts/test.sh    # 248 tests, 25 suites
```

macOS 14+, Swift 6. **No dependencies** — Apple frameworks only. Xcode optional; Command Line
Tools are enough.

> `./Scripts/test.sh` rather than `swift test`: the Swift Testing framework bundled with Command
> Line Tools isn't on the default search path, so the script passes the framework and rpath flags.

---

## Architecture

Two targets, one hard boundary.

```
QuickWinsCore/          no SwiftUI, no AppKit — all behaviour lives here
  Domain/               DailyTask · TaskRules · TaskStatus · TaskColor · DayKey
                        FocusSession · FocusSessionRecord · DayRules · PetState
                        AccountabilityState · ContributionGrid · FocusStatistics
  Data/                 CoreDataStack · MigrationPlan · TaskRepository
                        HistoryRepository · AppSettings · SettingsStore
  Services/             TaskCoordinator · AccountabilityEngine · IdleDetection
                        ScreenPositioning · Notifications · TimeSource · Logger

QuickWins/              the executable
  App/                  QuickWinsApp · AppDelegate · AppEnvironment · AppModel
  Services/             FloatingPanelController · MiniHUDController · GlobalShortcut
  Features/             panel · HUD · dashboard · settings · menu bar
```

Everything system-facing sits behind a protocol — clock, idle time, notifications, storage,
launch-at-login — so the whole lifecycle runs in tests with no UI and no waiting.

### Five decisions that shaped it

**Task transitions are pure functions.** `TaskRules` takes the day's tasks and returns a new array.
The one-active-task rule lives there, not in a view, so it holds no matter which surface triggered
the change. The result is written as a single transaction — switching tasks can't be half-applied.

**Elapsed time is derived, never counted.** Banked seconds plus the instant the session started.
No per-second writes. A once-a-minute heartbeat bounds what a crash can over-count: on relaunch,
anything past the last heartbeat is discarded rather than credited as focus.

**Accountability is a pure state machine.** Given a state, an idle reading and an instant,
`AccountabilityEngine.evaluate` returns the next state and a list of effects — so the whole
escalation ladder is tested without waiting fifteen real minutes.

**History is separate from tasks.** A task stores a total, which says how long but never when, and
"Clear completed" deletes it. Sessions live in their own table and outlive the tasks that made
them. Sessions crossing midnight are split so each day is credited correctly.

**Window sizes are owned by controllers, never negotiated with SwiftUI.** Earned the hard way —
see below.

### Core Data, not SwiftData

The brief asked for SwiftData. SwiftData's `@Model` macro is expanded by a plugin that ships
**only with Xcode**, and this was built on a machine with Command Line Tools alone — any `@Model`
type fails to compile. Core Data is SwiftData's own engine, sits behind the same
`TaskRepository` protocol, and the model is built programmatically in `MigrationPlan.swift`.
Swapping SwiftData back in means writing one new repository implementation; domain, views and
tests don't move.

---

## How this was built

Notes on process, because the interesting parts aren't in the feature list.

**Constraints were found before committing to a design, not after.** The SwiftData blocker was
proven by compiling a minimal `@Model` and reading the error — not assumed. Same for the test
framework, and for whether global mouse monitors fire without Accessibility permission.

**The honesty rules are enforced by tests, not by care.** There's a test that fails if any
motivational message contains "great job" or similar, and another that fails if a companion state
description implies harm. The app can only observe idle seconds; encoding that as a test stops the
constraint eroding as features are added.

**Reconstructed data is quarantined.** When session history was introduced, existing tasks were
backfilled from their stored totals — but those clock times are guesses, so the records are flagged
and excluded from peak-hour analysis. Reporting a guess back as "your best working hours" would be
fabrication.

**Measured rather than assumed.** The HUD follows the pointer all day, so its cost was measured
with `top` at each step. That produced an adaptive cadence — 30 Hz while the pointer moves, 2 Hz
once it's still — and, along the way, disproved two plausible-sounding theories about what the cost
actually was (the drop shadow: nothing; the material backdrop: about 1%).

**Several real bugs were found only by running the app.** Worth naming, because tests didn't catch
any of them:

- *Only the first global hot key worked.* Carbon rejects a duplicate handler registration with
  `eventHandlerAlreadyInstalledErr`, so adding a second shortcut left it silently dead. The log
  said so; nothing else did.
- *Three separate recursive-layout crashes.* All the same root cause: letting SwiftUI and AppKit
  negotiate a window's size. A hosting view resizes the window, that triggers layout, layout
  resizes the window. One killed the app at launch; one killed it when adding a task. Fixed by
  giving controllers sole ownership of window sizing.
- *Backfill could double-count.* Its guard was a preference flag — and preferences reset
  independently of the database. The store is now the witness.

**A screenshot is not evidence.** One "bug" turned out to be image upscaling aliasing solid
borders into dashed ones. Checking at native resolution showed the rendering was correct all along.

**[docs/MANUAL_QA.md](docs/MANUAL_QA.md) separates what was proven from what wasn't** — `[AUTO]`,
`[VERIFIED]`, `[CONFIRMED]` by the owner, and `[PENDING]`. Nothing is marked tested unless it was
actually run.

---

## Privacy

Everything is local. No account, no network, no analytics — the app makes no HTTP requests at all.

It does **not** read what you type, your clipboard, browser history, files, screen contents or
window titles. It reads exactly one number:
`CGEventSource.secondsSinceLastEventType` — seconds since the last hardware input. That needs no
permission prompt, which is precisely why it was chosen over an event tap.

| Permission | Required |
|---|---|
| Notifications | Optional — denial is handled, check-ins move into the panel |
| Launch at login | Optional, via `SMAppService` |
| Accessibility · Screen Recording · Full Disk Access | **Never requested** |

Tasks live in `~/Library/Application Support/QuickWins/QuickWins.sqlite`; preferences in
`UserDefaults`. The diagnostic log records task **identifiers**, never titles or notes, so an
exported log is safe to share. Full statement: [PRIVACY.md](PRIVACY.md).

---

## Keyboard

**Global:** `⌥Space` panel · `⌥Q` HUD — both configurable.

**In the panel:** `⌘N` add · `⌘↩` start · `⌘⇧↩` complete · `Space` pause/resume · `↑`/`↓` select ·
`Delete` remove · `⌘Z` undo · `Esc` dismiss.

> A global hot key *consumes* its keystroke system-wide, so a bare `⇧`+letter would make that
> capital letter untypable everywhere. Defaults avoid it and the recorder rejects modifier-less
> keys.

---

## Known limitations

Stated plainly.

1. **No SwiftData** — see above. Core Data behind the same protocol.
2. **No app icon.** Compiling an `.icns` needs Xcode's asset tooling.
3. **Ad-hoc signed.** Distributing to other Macs needs Developer ID signing and notarization.
4. **Reordering is menu-driven**, not drag-and-drop — dragging inside a borderless non-activating
   panel is unreliable.
5. **Full-screen apps.** The panel is `.fullScreenAuxiliary` and appears over full-screen spaces
   where macOS permits it, which is not always.
6. **Up to 60 seconds of focus can be lost** after a force quit — the heartbeat interval.
   Deliberate: under-counting beats crediting an overnight sleep as work.
7. **The graph starts empty.** History began when session recording shipped.
8. **Some paths are verified by hand**, and a handful remain unverified. See the QA checklist.

---

## Troubleshooting

**`⌥Space` does nothing** — another app may hold it. Settings › General reports the conflict; the
menu-bar item always works.

**The panel opened on the wrong monitor** — it follows your pointer, which isn't always the screen
you're looking at. Turn off *Open beside the pointer*.

**No notifications** — check System Settings › Notifications. Denial is handled; check-ins appear
in the panel instead. Requires running from `QuickWins.app`, not the bare executable.

**Check-ins fire while reading** — snooze from the menu bar (5/15/30 min or until you resume), or
turn off *Inactivity check-ins* for that task.

**Something's wrong** — Settings › Advanced › Export diagnostic log. It contains no task content.

---

## License

MIT — see [LICENSE](LICENSE). Changes: [CHANGELOG.md](CHANGELOG.md).
