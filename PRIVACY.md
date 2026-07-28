# Privacy

QuickWins is a local application. This document describes exactly what it does and does not do,
and every claim here is backed by the source in this repository.

## What is stored, and where

| Data | Location | Leaves your Mac? |
|---|---|---|
| Tasks (title, notes, times, status) | `~/Library/Application Support/QuickWins/QuickWins.sqlite` | No |
| Preferences | `UserDefaults` — `com.rickywroe.quickwins.settings` | No |
| Diagnostic log | In memory, last 500 entries | Only if you export it yourself |

## What QuickWins does not do

- **No account.** There is nothing to register, sign into, or recover.
- **No network.** The app makes no HTTP requests, opens no sockets, and contacts no server. There
  is no analytics SDK, no telemetry, no crash reporting, and no update check.
- **No content monitoring.** QuickWins does not read what you type, your keystrokes, your
  clipboard, your browser history, your files, your screen contents, or the titles of your windows.
- **No third-party code.** The package has zero external dependencies. Apple frameworks only.
- **No credentials.** The app has no reason to handle a password or token, and never does.

## What QuickWins does measure

One number: **how many seconds since the system last received hardware input**.

It is read with `CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType:)`, in
`Sources/QuickWinsCore/Services/IdleDetectionService.swift`.

That API returns a duration and nothing else. It cannot report which key was pressed, which app was
in front, or what was on screen. It requires no permission prompt, which is precisely why it was
chosen over an event tap — an event tap would work too, but would demand Accessibility access far
broader than deciding when to ask "still working?".

The `.hidSystemState` source counts hardware input only, so events synthesised by scripts are not
mistaken for a person being at the keyboard.

## Permissions

| Permission | Requested | Purpose |
|---|---|---|
| Notifications | Optional, on first use | Delivering accountability check-ins |
| Launch at login | Optional, from Settings | Starting QuickWins when you log in |
| Accessibility | **Never** | — |
| Screen Recording | **Never** | — |
| Full Disk Access | **Never** | — |
| Camera / Microphone / Contacts / Calendar / Location | **Never** | — |

Denying notifications is fully supported: check-ins appear in the floating panel instead, and a
banner explains how to change your mind.

## The diagnostic log

The log records app events — session started, save failed, shortcut registration refused — and
identifies tasks by **UUID only**. Task titles and notes are never written to it. An exported log
can be shared without revealing what you were working on.

It is capped at 500 entries in memory and is never written to disk unless you choose
**Settings › Advanced › Export diagnostic log**.

## Deleting your data

**Settings › Advanced › Reset all data** removes every task and restores default settings.

To remove everything manually:

```bash
rm -rf ~/Library/Application\ Support/QuickWins
defaults delete com.rickywroe.quickwins
```

## Verifying these claims

This repository is the whole application. Two greps worth running:

```bash
# No networking anywhere in the source.
grep -rIn "URLSession\|NWConnection\|CFNetwork\|Network\.framework\|http://\|https://" Sources/

# The only idle-detection call site.
grep -rIn "secondsSinceLastEventType" Sources/
```

The first returns nothing. The second returns a single call site in one file, alongside the doc
comment above it.
