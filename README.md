<div align="center">

# 🍅 Flowstate

### A Pomodoro focus timer for the [Omarchy](https://omarchy.org) bar

Start a session and your whole desktop drops into focus mode — Obsidian alone in
front of you, a shuffled Spotify soundtrack playing quietly out of the way, and
the internet's time-sinks blocked at the `/etc/hosts` level until you're done.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Omarchy plugin](https://img.shields.io/badge/Omarchy-bar_widget-8839ef)
![Technique](https://img.shields.io/badge/technique-Pomodoro-e11d48)
![Theme](https://img.shields.io/badge/theme-follows_Omarchy-1e8a5c)

<img src="preview.jpeg" alt="Flowstate panel in the Omarchy bar" width="720">

</div>

---

## Contents

- [What it does](#what-it-does)
- [Requirements](#requirements)
- [Install](#install)
  - [1 · The plugin](#1--the-plugin)
  - [2 · Music — `spotify_player`](#2--music--spotify_player)
  - [3 · Site blocker](#3--site-blocker)
- [Usage](#usage)
- [Configuring soundtracks](#configuring-soundtracks)
- [Settings reference](#settings-reference)
- [Scripting (IPC)](#scripting-ipc)
- [How focus isolation works](#how-focus-isolation-works)
- [Uninstall](#uninstall)
- [License](#license)

---

## What it does

When you start a session, Flowstate runs a set of **focus effects** (all
individually toggleable) and holds them for the whole Pomodoro cycle — through
every short and long break — releasing them only when you **stop** or the cycle
**finishes**:

| | Effect | Details |
|---|---|---|
| 🧘 | **Isolate Obsidian** | Launches or focuses Obsidian on your focus workspace and parks every *other* window out of sight, so Obsidian is the only thing in front of you. |
| 🎧 | **Play a soundtrack** | Starts `spotify_player` on a far-off workspace (default **9**), shuffled, at a quiet volume — including your **Liked Songs**. |
| 🚫 | **Block distractions** | Adds curated blocklists (social, video, shopping, news, adult) to `/etc/hosts` for the duration of the session. |
| ⏱️ | **Run the Pomodoro** | Configurable focus / short-break / long-break lengths and cycle count, with optional bells between phases. |

When the session ends, Flowstate **unblocks** the sites, **restores** Spotify's
previous volume and pauses it, and **un-parks** your windows. Obsidian is left
open. Prefer just the timer? Flip off **Focus effects** and Flowstate is a plain
Pomodoro in your bar.

The widget lives in the bar and **follows your Omarchy theme automatically**.

---

## Requirements

| Dependency | Why | Notes |
|---|---|---|
| **Omarchy** (Quickshell shell + Hyprland) | Host for the bar widget | Already present on Omarchy |
| [`spotify_player`](https://github.com/aome510/spotify-player) | Soundtrack playback, shuffle, volume | AUR · **Spotify Premium required** for streaming |
| **Obsidian** | The app that gets isolated | Optional — turn off *Open Obsidian* if unused |
| `hyprctl` + `jq` | Window placement / parking | `jq` from the repos |
| `pactl` / `pw-play` | Pomodoro bells | Ships with Omarchy's audio stack |

Everything except Obsidian and Spotify Premium is installed for you by the setup
scripts below.

---

## Install

The plugin ships in Omarchy's plugin directory. From there, one script wires up
all three pieces (each step is independently re-runnable):

```sh
cd ~/.config/omarchy/plugins/io.github.keegan-sucks.flowstate/scripts
./install.sh                     # validate → enable → place icon → install deps
```

Prefer non-interactive icon placement? Pass a section:

```sh
./install.sh --section center    # center | left | right
```

`install.sh` walks through:

1. **Plugin** — validates the manifest, enables the widget, and places the bar
   icon where you choose.
2. **`spotify_player`** — installs it from the AUR and offers to authenticate.
3. **Site blocker** — installs the privileged `/etc/hosts` helper (needs sudo).

You can also run any of the three on its own — read on.

### 1 · The plugin

If you only want to (re)enable the widget and place its icon:

```sh
./install.sh --section center
```

### 2 · Music — `spotify_player`

Flowstate drives [`spotify_player`](https://github.com/aome510/spotify-player), a
terminal Spotify client that doubles as its own Spotify Connect device and CLI
server. That combination is what makes **forced shuffle**, **Liked Songs**, and
**scripted volume** work reliably — the official Linux client can't do these over
MPRIS. Streaming requires **Spotify Premium**.

```sh
./install-spotify-player.sh
spotify_player authenticate      # one-time: OAuth login + librespot streaming login
```

It uses `spotify_player`'s bundled client ID, so you **do not** need to register
a Spotify developer app.

### 3 · Site blocker

Editing `/etc/hosts` needs root, so blocking is set up once and then runs
password-free during sessions:

```sh
sudo ./install-blocker.sh            # installs the helper + a scoped NOPASSWD rule
sudo ./install-blocker.sh --uninstall
```

This installs `/usr/local/bin/flowstate-hosts` (root-owned) plus a **narrowly
scoped** `sudoers` rule so sessions can toggle blocking without a prompt. Only a
marked region of `/etc/hosts` is ever touched — the rest of the file is left
exactly as it was.

The blocklist is **bundled and categorized** in `blocklists/*.txt`:

| Category | Source |
|---|---|
| Social | [StevenBlack `alternates/social-only`](https://github.com/StevenBlack/hosts) |
| Adult | [StevenBlack `alternates/porn-only`](https://github.com/StevenBlack/hosts) |
| Video / Shopping / News | Curated, high-signal lists |

Toggle categories and add your own domains from the panel's **⚙ Edit** view, or
edit the `blocklists/*.txt` files directly to change the lists.

---

## Usage

**On the bar:**

| Action | Result |
|---|---|
| **Left-click** | Open / close the panel |
| **Middle-click** | Start / pause the session |
| **Right-click** | Reset |

The bar pill lights up while a session is running.

**In the panel**, the main view is deliberately short — just the timer and your
soundtrack buttons. Everything else lives under **⚙ Edit** so the panel never
scrolls: volume, the **Focus effects** master switch, **Pomodoro sounds**, the
cycle lengths, soundtrack links, and block categories.

**Keyboard** (while the panel is focused):

| Key | Action |
|---|---|
| `Space` | Start / pause |
| `R` | Reset |
| `S` | Skip the current phase |
| `E` | Toggle the Edit view |

---

## Configuring soundtracks

Flowstate gives you **three soundtrack slots**. Open the panel → **⚙ Edit**, then
set each slot's name and Spotify link:

- Paste a share URL — `https://open.spotify.com/playlist/…`
- …or a URI — `spotify:playlist:…` (playlists, albums, and artists all work)
- …or the keyword **`liked`** to shuffle your **Liked Songs**

Defaults are **Lofi**, **Nature**, and **Liked** (selected). Clear a slot's link
to hide its button. The **volume** slider under ⚙ Edit sets the session volume —
applied on start and restored to your previous level on stop.

---

## Settings reference

Every setting is editable three ways: the widget's settings pane, the panel's
**⚙ Edit** view, or the CLI:

```sh
omarchy bar set io.github.keegan-sucks.flowstate <key> <value>
```

| Key | Default | Meaning |
|---|---|---|
| `focusEffects` | `true` | Master switch for all side-effects |
| `alwaysShuffle` | `true` | Shuffle the soundtrack on start |
| `slot1Label` / `slot1Uri` | Lofi | First soundtrack name + link |
| `slot2Label` / `slot2Uri` | Nature | Second soundtrack |
| `slot3Label` / `slot3Uri` | Liked / `liked` | Third soundtrack; `liked` = Liked Songs |
| `activeSlot` | `2` | Selected soundtrack index (0–2) |
| `spotifyVolume` | `35` | Focus volume (0–100); previous volume restored on stop |
| `openSpotify` | `true` | Launch `spotify_player` and start the soundtrack on start |
| `openObsidian` | `true` | Launch / focus Obsidian on start |
| `isolateObsidian` | `true` | Park other windows so Obsidian is alone on the focus workspace |
| `focusWorkspace` | `0` | Obsidian's workspace (`0` = whichever is active on start) |
| `spotifyWorkspace` | `9` | Workspace to place `spotify_player` on (`0` disables placement) |
| `blockSites` | `true` | Toggle site blocking |
| `catSocial` / `catVideo` / `catShopping` / `catNews` | `true` | Blocklist categories |
| `catAdult` | `true` | Adult category |
| `extraDomains` | *(empty)* | Extra comma/newline-separated domains to block |
| `pomodoroWorkMinutes` | `25` | Length of each focus phase |
| `pomodoroShortBreakMinutes` | `5` | Short break length |
| `pomodoroCycles` | `4` | Focus phases before the long break |
| `pomodoroLongBreakMinutes` | `15` | Long break length |
| `pomodoroSound` | `true` | Bells between phases / at completion |

---

## Scripting (IPC)

Drive Flowstate from scripts or keybindings via `omarchy-shell`:

```sh
id=io.github.keegan-sucks.flowstate

omarchy-shell "$id" status               # print current state
omarchy-shell "$id" pomodoro 25 5 4 15   # set work / short / cycles / long
omarchy-shell "$id" start                # also: pause | toggleTimer | skip | reset
omarchy-shell "$id" open                 # also: close | toggle
```

---

## How focus isolation works

On **start**, Obsidian is moved to the focus workspace silently, every *other*
window on that workspace is moved into a hidden `special:flowstate` workspace,
and the focus workspace is activated with Obsidian focused. `spotify_player` is
placed on the music workspace the same way — via `hyprctl`, with **no Hyprland
window rule required**.

On **stop**, the parked windows are moved back where they came from, Spotify's
volume is restored and playback paused, and the `/etc/hosts` block region is
cleared. Obsidian stays open.

---

## Uninstall

```sh
omarchy plugin disable io.github.keegan-sucks.flowstate
sudo ~/.config/omarchy/plugins/io.github.keegan-sucks.flowstate/scripts/install-blocker.sh --uninstall
```

The blocker uninstall removes the helper binary and the scoped `sudoers` rule
and clears any remaining block region from `/etc/hosts`.

---

## License

[MIT](LICENSE) © keegan-sucks
