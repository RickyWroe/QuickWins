# Plan — gamification, history, and the dashboard

Status: **Phases A and B shipped in 1.2.0.** Phases C and D not started.

| Phase | State |
|---|---|
| A — session history and day types | Shipped. Schema v3 live; the owner's database migrated and backfilled. |
| B — the companion | Shipped. Tortoise in the mini HUD and the active-task card. |
| C — the dashboard | Not started. Data is accumulating for it now. |
| D — metrics | Not started. Needs a couple of weeks of Phase A data to say anything. |

Three additions: a pet avatar that reacts to whether you are working, a GitHub-style contribution
graph, and metrics built on real session history.

---

## Decisions taken

| Question | Decision |
|---|---|
| Pet behaviour | **Sleepy, not sick.** Reacts only to idle time while a task runs. Never dies. |
| Avatar source | **SF Symbols** — one species, state carried by tint, form, scale, overlay, motion. |
| Species | Tortoise (slow and steady). Swappable; the state machine is independent of the art. |
| Days off | **Weekly pattern + per-day override.** Working weekdays set once; any day flippable. |
| Heatmap colour | **One hue, five intensities.** System accent by default, GitHub green optional. |
| Daily reset | Pet vitality and daily goal reset each morning. Yesterday never penalises today. |
| Placement | Full graph and metrics in a **Stats window**. Panel keeps at most a small strip, off by default. |

### Two constraints that shaped these

**The app must not assert things it cannot observe.** QuickWins sees one signal: seconds since the
last hardware input. It cannot see whether you are working. A pet that sickens when you stop would
claim knowledge the app does not have, and would wilt during meetings, reading, and thinking. So
the pet gets *sleepy* — a state that is literally true ("no input for a while") and recovers the
instant you touch the keyboard. It inherits every existing suppression rule: paused task, snooze,
per-task idle opt-out, quiet hours.

**Nothing may be conveyed by colour alone.** This holds everywhere else in the app, and a heatmap is
pure colour encoding. Mitigations are in the dashboard section; the important one is that a day off
differs from a worked-zero day by *shape*, not shade.

### Deliberately not doing

- No streak that breaks on a rest day. Days off are skipped, not failed.
- No pet death, no guilt state, no "you lost your progress".
- No claim that any of this measures productivity. It measures time with a timer running.

---

## Phase A — session history and day marks

**Invisible, and first.** Every day this is not shipped is history that cannot be recovered — and
`Clear completed` currently deletes the task rows that hold the only record of past focus.

### Schema v3 (two new entities, additive → lightweight migration, same pattern as v2)

`FocusSessionRecord`

| Field | Notes |
|---|---|
| `id` | UUID, unique constraint |
| `taskID` | UUID of the task |
| `startedAt`, `endedAt` | The window actually worked |
| `seconds` | Denormalised duration |
| `dayPacked` | `yyyymmdd`, for day-scoped queries |
| `wasInterrupted` | Session ended by the idle ceiling or a stale heartbeat |
| `isBackfilled` | Start time is a guess — see below |

`DayMark`

| Field | Notes |
|---|---|
| `dayPacked` | Unique |
| `typeRaw` | `working` \| `off` |

`DayMark` exists only for **overrides**. The default comes from the weekly pattern in settings, so
a normal week stores nothing.

### Recording

The coordinator already owns every transition that ends a session — pause, complete, skip, switch,
move, rollover, stale-session restore. Rather than pushing side effects into `TaskRules` (which is
pure and must stay that way), the coordinator **diffs**: a task that had a `sessionStartedAt` and
no longer does closes a session.

Edge cases that need explicit handling and tests:

- **Midnight split.** A session running across midnight must be split so each day gets its share,
  or the heatmap misattributes a whole evening.
- **Stale restore.** Closes at the last heartbeat, not at `now` — matching the existing timer rule.
- **Implausible length.** A session beyond ~8 hours is flagged rather than trusted.

### Backfill

Existing tasks carry `accumulatedFocus` but no start times. One synthetic session per task with
focus time, ending at `lastInteractionAt`. **These are flagged `isBackfilled` and excluded from
peak-hour analysis** — inventing timestamps and then reporting them as your best working hours
would be fabrication.

### Settings added

- `workingWeekdays` (default Mon–Fri)
- `dailyFocusGoalMinutes` (drives streaks and pet vitality)

---

## Phase B — the pet

Independent of Phase A. Reads the existing `AccountabilityLevel`, so it needs no new data.

| Situation | Tortoise |
|---|---|
| Working, input detected | Alert, occasional blink |
| ~3 min quiet | Looks up |
| ~5 min | Droops |
| ~10 min | Eyes closing |
| ~15 min | Asleep, `zzz` overlay |
| Paused / no task | Sitting, neutral |
| Snoozed or idle-detection off | Contentedly settled — *this is fine* |

- **Colour**: body tint is the active task's `TaskColor`, desaturating toward grey as it dozes.
- **Vitality**: brighter and livelier as the day's focus total approaches the goal. Resets daily.
- **Motion**: `.symbolEffect(.bounce)` on waking, `.pulse` while working. `.breathe` and `.wiggle`
  need macOS 15 and must sit behind availability checks — the deployment target is 14.0.
- **Placement**: mini HUD and the active-task card.

### Hard constraint

The HUD crash of 1.1.1 came from HUD content resizing its window. **The pet must be a fixed-size
element and go through `syncContentSize`.** A pet that grows or shrinks with state would
reintroduce the recursion.

It must also animate only on state *transitions* — never an idle loop. The HUD is on screen all
day at ~2.5% CPU and a continuous animation would undo the adaptive-cadence work.

---

## Phase C — the dashboard

A real window, opened from the menu bar.

```
   347 hours focused in the last year

   Mar   Apr   May   Jun   Jul   Aug   Sep   Oct   Nov
M  ▢▪▪▫▪ ▪▪▫▪▪ ...
W  ▪▫▪▪▫ ...
F  ▪▪▪▫▪ ...

   Less ▫▪▪▪▪ More
```

- 53 columns × 7 rows, month labels across the top, weekday labels down the left.
- Five buckets by focused minutes, thresholds derived from the daily goal.
- One hue, varying by intensity — colour-blind safe, survives increased contrast.

### Accessibility

| Concern | Handling |
|---|---|
| Colour-only encoding | Every cell has a VoiceOver value: *"Tuesday 14 October, 47 minutes, 2 tasks"* |
| Day off vs worked zero | **Dashed outline vs empty fill** — a shape difference, not a shade |
| Today | Ring around the cell |
| Reduced motion | No cell transitions |
| Pointer users | Hover tooltip matching the VoiceOver value |

### Empty start

There is essentially no history — 3 task rows at time of writing. The graph will be blank for
weeks. The UI should say so plainly rather than looking broken.

---

## Phase D — metrics

Needs a couple of weeks of Phase A data before it says anything meaningful.

- Current and longest streak — **days off skipped, never counted as breaks**
- Peak hours: focus minutes bucketed by hour of day, backfilled sessions excluded
- Average and longest session
- Completion rate, interruption rate
- Time by task colour — the closest thing to GitHub's per-repository breakdown

Labelled in the UI as time with a timer running, not productivity.

---

## Test plan

Most of this is pure logic and belongs in `QuickWinsCore` alongside the existing 156 tests.

- Session diffing produces exactly one record per completed session
- Midnight split apportions across both days
- Stale restore closes at the heartbeat
- Streak math: days off skipped; a working day with zero focus breaks it; a day off between two
  worked days keeps it intact
- Day-type resolution: weekly pattern, per-day override wins
- Heatmap bucketing at threshold boundaries
- Backfilled sessions excluded from peak hours
- Migration v2 → v3 against a real v2 store, asserting no task data is lost

---

## Risks

| Risk | Mitigation |
|---|---|
| HUD layout recursion returns | Pet is fixed-size, sized through `syncContentSize` |
| Battery cost of an always-on animated pet | Transition-only animation; no idle loop |
| Privacy scope creep | Session-level history is more granular than today's data. Still local, still no network — but `PRIVACY.md` and the README must say so explicitly rather than expanding quietly |
| Graph looks broken when empty | Explicit empty state |
| Gamification undermining the app's honesty | Reviewed above: no death, no guilt, no rest-day penalty |

---

## Open

- Species is provisional. If the tortoise doesn't feel like *yours*, swapping in drawn artwork
  touches only the view — the state machine does not change.
- SF Symbols are licensed for use in app UI, **not as a logo**. If the pet ever becomes the app
  icon, that needs original art.
