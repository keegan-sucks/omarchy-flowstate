<div align="center">

# 🍅 Flowstate

### A Pomodoro focus timer for the [Omarchy](https://omarchy.org) bar

Start a session and a shuffled Spotify soundtrack plays quietly out of the way —
**pausing itself on every break** and resuming when you're back — while distinct
sounds mark each phase boundary. When the last block finishes, the music stops and
your volume is restored.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Omarchy plugin](https://img.shields.io/badge/Omarchy-bar_widget-8839ef)
![Technique](https://img.shields.io/badge/technique-Pomodoro-e11d48)
![Theme](https://img.shields.io/badge/theme-follows_Omarchy-1e8a5c)

<img src="preview.jpeg" alt="Flowstate panel in the Omarchy bar" width="720">

</div>

> **A companion to [Flowstate for macOS](https://github.com/keegan-sucks/flowstate-macos)** —
> the two are kept intentionally in step. Same Pomodoro model, same soundtrack behaviour
> (the **official Spotify app**, shuffled, random start, pause on breaks), same phase
> sounds, same Liked-Songs approach.

---

## Contents

- [What it does](#what-it-does)
- [Requirements](#requirements)
- [Install](#install)
- [Liked Songs](#liked-songs-optional)
- [Usage](#usage)
- [Soundtracks](#soundtracks)
- [Phase sounds](#phase-sounds)
- [Settings reference](#settings-reference)
- [Scripting (IPC)](#scripting-ipc)
- [Update](#update)
- [Uninstall](#uninstall)
- [Releasing](#releasing)
- [License](#license)

---

## What it does

The bar shows a live focus glyph, round dots, and the clock — e.g. `⌖ ●●○○ 12:34`.
Start a session and Flowstate runs a **Pomodoro cycle**:

> focus 1 → short break → focus 2 → short break → … → focus `N`, then it **ends**.

There is **no timed long break** — after the last focus block the session finishes
with a distinct chime; take your break whenever you like.

While a session runs, the **soundtrack** plays through the **official Spotify desktop
app** — no extra player, no CLI, no login inside Flowstate; it simply remote-controls
the Spotify you already use (over MPRIS/D-Bus):

- starts **shuffled**, on a varied track (not always track 1), ducked to a quiet focus
  volume, with repeat on so a block never falls silent;
- everything happens **in the background**: if Flowstate has to launch Spotify, it opens
  straight on a far-off workspace (default **9**), unfocused; and while a session runs
  Spotify is barred from yanking you to its workspace when it loads a playlist (Hyprland
  honours Spotify's "activate me" request by default). An already-open Spotify is never moved;
- **pauses during each short break** and **resumes** when focus returns;
- at the end, **restores your previous volume and pauses** (Spotify is left open).

Point each of the three slots at any Spotify **playlist, album, or artist**. Your
**Liked Songs** work too, via a mirror playlist ([see below](#liked-songs-optional)).
Prefer just the timer? Turn **Play soundtrack** off.

The widget lives in the bar and **follows your Omarchy theme automatically**.

---

## Requirements

| Dependency | Why | Notes |
|---|---|---|
| **Omarchy** (Quickshell shell + Hyprland) | Host for the bar widget | Already present on Omarchy |
| **Spotify** desktop app | Soundtrack playback, shuffle, volume | Ships with Omarchy (`omarchy pkg aur add spotify` if missing). Premium recommended for ad-free focus |
| `busctl` (systemd) · `hyprctl` · `jq` | Drive Spotify over MPRIS; place its window | Already present on Omarchy |
| `pw-play` | Phase-boundary sounds | Omarchy's PipeWire audio stack |
| `python3` | **Optional** Liked-Songs auto-refresh only | Ships with Omarchy; standard library only, nothing to pip-install |

No sudo or pkexec is required. Flowstate installs nothing system-wide.

---

## Install

**From the [Omarchy plugin store](https://plugins.omarchy.org)** — search for *Flowstate*, or from a terminal:

```sh
omarchy plugin add https://github.com/keegan-sucks/omarchy-flowstate.git --enable
```

Pick a bar section when asked (or later: `omarchy bar move io.github.keegan-sucks.flowstate --section center`).
That's it — log into the Spotify app if you aren't already, then left-click the bar icon
and press **Start**. The three default slots are Spotify's own public focus playlists
(*Lofi Beats*, *Deep Focus*, *Peaceful Piano*), so a fresh install plays with zero setup.

---

## Liked Songs (optional)

Everything above needs zero setup. Liked Songs is the one extra: Spotify can't shuffle
*Liked Songs* directly, so point a slot at a **mirror playlist**. Two ways —

**Recommended — by hand, no account setup (~30s).** In Spotify open *Liked Songs* →
`Ctrl-A` → right-click → *Add to playlist* → *New playlist*, then paste that playlist's
link into a slot (panel → **⚙ Edit → Soundtrack slots**). That's the whole thing — no
developer account, no login, nothing. (Re-do it occasionally as your Liked Songs change.)

**Optional — auto-refresh (power user).** If you'd rather the mirror rebuild itself every
week, use the in-panel **⚙ Edit → Liked Songs → "Auto-refresh Liked Songs…"** button
(or run `bash scripts/setup-liked.sh`). It creates a "Liked (Flowstate)" playlist, offers
to point slot 3 at it, and installs a weekly refresh (a per-user systemd timer, Sundays
04:00, catching up after downtime).

Only this optional path needs a **free Spotify app of your own** — Spotify no longer lets
one shared app serve many users, so each person registers their own at
[developer.spotify.com/dashboard](https://developer.spotify.com/dashboard) (redirect URI
`http://127.0.0.1:8888/callback`, Web API). You supply only a **Client ID — no secret, no
password** (the PKCE flow, so nothing sensitive is stored). Under the hood:
`scripts/sync-liked-playlist.py` syncs (Python standard library only),
`scripts/install-sync-schedule.sh` installs the `flowstate-liked-sync.timer` user timer and
copies the runtime into `~/.config/flowstate/`, and your Client ID lives in
`~/.config/flowstate/sync.env` (`scripts/sync.env.example`). Remove it any time with
`bash scripts/install-sync-schedule.sh --remove`.

---

## Usage

**On the bar:** left-click opens the panel · middle-click starts/pauses · right-click resets.

**In the panel** the main view is deliberately short — dots, phase, clock, the
transport buttons, and your soundtrack buttons (switch slots live during focus).
Everything else lives under **⚙ Edit**.

**Keyboard** (while the panel is focused):

| Key | Action |
|---|---|
| `Space` | Start / pause |
| `R` | Reset |
| `S` | Skip the current phase |
| `N` | Skip the current **song** |
| `E` | Toggle the Edit view |

---

## Soundtracks

Three soundtrack slots. Open the panel → **⚙ Edit** and set each slot's name and target:

- a share URL — `https://open.spotify.com/playlist/…` (albums and artists work too)
- a URI — `spotify:playlist:…`
- for Liked Songs, a [mirror playlist](#liked-songs-optional)

Clear a slot's target to hide its button. **Always shuffle** starts on a random track
(the context starts muted, shuffle is switched on, a few tracks are skipped, then the
volume comes up — a varied first song with no blips). The **Focus volume** slider sets
Spotify's volume during the session; your pre-session volume is restored on stop.

---

## Phase sounds

Distinct cues mark each boundary, each with its own sound + volume + preview under
**⚙ Edit → Phase sounds**:

| Cue | When | Default |
|---|---|---|
| Short break | a focus block ended | `bell` |
| Back to work | a short break ended | `complete` |
| Session end | the final focus block ended | `alarm-clock-elapsed` |

Sounds are the standard freedesktop system sounds (played with `pw-play`).

---

## Settings reference

Editable in the panel's **⚙ Edit** view, the widget's settings pane, or the CLI:

```sh
omarchy bar set io.github.keegan-sucks.flowstate <key> <value>
```

| Key | Default | Meaning |
|---|---|---|
| `workMinutes` / `shortBreakMinutes` / `cycles` | 25 / 5 / 4 | Pomodoro cycle (no timed long break) |
| `playSoundtrack` | `true` | Drive the Spotify app during sessions |
| `spotifyVolume` | `35` | Focus volume (0–100); previous restored on stop |
| `alwaysShuffle` | `true` | Shuffle + random start |
| `spotifyWorkspace` | `9` | Workspace a *freshly launched* Spotify opens on, silently (0 = where you are, still unfocused) |
| `slot1Label`/`slot1Uri` … `slot3*` | Lofi / Deep Focus / Piano | Soundtrack slots (playlist/album/artist URI or link) |
| `activeSlot` | `0` | Selected slot (0–2) |
| `soundsEnabled` | `true` | Play phase-boundary sounds |
| `shortBreakSound` / `backToWorkSound` / `longBreakSound` | bell / complete / alarm-clock-elapsed | Per-cue sound |
| `shortBreakVolume` / `backToWorkVolume` / `longBreakVolume` | 1.0 | Per-cue volume (0–1) |
| `focusGlyph` / `breakGlyph` | ⌖ / ☾ | Bar glyphs |

> Upgrading from the `spotify_player` era? A slot target of `liked` no longer plays —
> the panel flags it; replace it with a mirror playlist as described above.

---

## Scripting (IPC)

```sh
id=io.github.keegan-sucks.flowstate
omarchy-shell "$id" status
omarchy-shell "$id" start        # pause | toggleTimer | skip | next | reset
omarchy-shell "$id" open         # close | toggle
```

**How the background behaviour works (Hyprland):** Spotify is launched via Hyprland's exec
dispatcher with per-launch rules (`[workspace N silent; noinitialfocus]`), so nothing
persists. When it receives a playlist, Spotify asks the compositor to activate its
window and Omarchy's Hyprland honours that (`misc.focus_on_activate`), so for the
duration of a session Flowstate enables a runtime window rule
(`focus_on_activate = false` for the Spotify class) and disables it again at stop —
Hyprland can only disable, not remove, runtime rules. If you'd rather Spotify *never*
steal focus, make it permanent in `~/.config/hypr/hyprland.lua`:

```lua
o.window("Spotify", { focus_on_activate = false })
```

The soundtrack script can also be driven by hand for debugging
(`bash scripts/flowstate-session.sh on <target> <volume> <workspace> <shuffle>`); it logs
to `~/.local/state/flowstate/session.log`.

---

## Update

```sh
omarchy plugin update io.github.keegan-sucks.flowstate
```

---

## Uninstall

```sh
omarchy plugin remove io.github.keegan-sucks.flowstate
```

If you set up the optional Liked-Songs auto-refresh, remove its timer first
(`bash scripts/install-sync-schedule.sh --remove` from the plugin folder, or
`systemctl --user disable --now flowstate-liked-sync.timer`), and delete
`~/.config/flowstate/` (your Client ID + OAuth token) and `~/.local/state/flowstate/`
(logs). The "Liked (Flowstate)" playlist in your Spotify library is yours to keep or delete.
Spotify itself is untouched.

---

## Releasing

Omarchy installs plugins straight from git, so a release is a version bump + tag:

```sh
scripts/release.sh 0.3.0
```

Then ask the [plugin store](https://plugins.omarchy.org) to verify the new commit via its
*Plugin verification* issue form (see the marketplace's `SUBMISSION.md`).

---

## License

MIT — see [LICENSE](LICENSE).
