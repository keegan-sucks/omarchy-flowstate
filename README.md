# Flowstate for Omarchy

A focus timer for the Omarchy bar. Two modes — **Stopwatch** and **Pomodoro** —
and when you start a session it can:

- **Block distracting sites** (an extensive, categorized blocklist)
- **Open your music player** and start a focus **soundtrack** (shuffled), at a set volume
- **Open Obsidian** (if it isn't already running)

Blocking and music persist through Pomodoro breaks and are released only when you
stop or finish the session. Ending a session unblocks the sites, restores the
music player's previous volume, and pauses it; Obsidian is left open.

The widget lives in the bar, follows your Omarchy theme automatically, and its bar
position is chosen at install time (and movable afterwards).

## Install

```sh
omarchy plugin add https://github.com/gopher-boats/omarchy-flowstate.git --enable
omarchy bar move io.github.gopher-boats.flowstate --section right   # left | center | right
```

## Music player: ncspot recommended

Flowstate drives Spotify over MPRIS and works with either client:

- **ncspot** (recommended) — supports **shuffle**, which the official Spotify Linux
  client silently ignores over MPRIS. Flowstate **auto-detects and prefers ncspot**
  when it's installed. Install it and log in once:
  ```sh
  cd ~/.config/omarchy/plugins/io.github.gopher-boats.flowstate/scripts
  ./install-ncspot.sh
  ncspot            # log in once (Spotify Premium required for playback)
  ```
- **Official Spotify** — used as a fallback. Plays your playlists, but **cannot
  shuffle** and cannot play Liked Songs (Spotify client limitations).

### About "Liked Songs"

There is **no reliable way to play your Liked Songs by automation** on Linux (no
playable URI; neither client exposes it over MPRIS/IPC). Instead, point a
soundtrack slot at a **playlist** — with ncspot's always-shuffle, a playlist plays
shuffled, which is the same experience. (Tip: in Spotify you can select your Liked
Songs and "Add to playlist" to mirror them into a normal playlist, then use its URI.)

## Soundtracks (configurable slots)

The panel has up to three soundtrack buttons. Click the **⚙ Edit** button in the
panel to rename each slot and set its **Spotify playlist/album URI** (in Spotify:
right-click → Share → Copy Spotify URI). Defaults: **Lofi** and **Nature**; the
third slot is empty (hidden) until you set it. Set the **volume** with the panel
slider — it's applied on start and the previous volume is restored on stop.

## Site blocking (one-time setup)

Editing `/etc/hosts` needs root, so blocking is opt-in. Run once:

```sh
cd ~/.config/omarchy/plugins/io.github.gopher-boats.flowstate/scripts
sudo ./install-blocker.sh
```

This installs a small root-owned helper (`/usr/local/bin/flowstate-hosts`) and a
scoped `NOPASSWD` sudoers rule so the plugin can toggle blocking without a
password. Everything else works without it; if blocking isn't set up, the plugin
skips it and notifies you. Remove with `sudo ./install-blocker.sh --uninstall`.

The blocklist is **bundled and categorized** (`blocklists/*.txt`): Social, Video,
Shopping, News & forums (incl. Reddit), and Adult (off by default). Toggle
categories and add extra domains in the panel's Edit view.

## Keep the player out of the way (optional)

To always open the music player on a far-off workspace (default 9, silently):

```sh
cd ~/.config/omarchy/plugins/io.github.gopher-boats.flowstate/scripts
./install-workspace-rule.sh 9      # adds a Hyprland window rule; --uninstall to remove
```

(Only applies when Flowstate launches the player itself; if it's already running,
it's left where it is.)

## Usage

- **Left-click** the widget: open the panel. **Middle-click**: start/pause.
  **Right-click**: reset.
- In the panel: pick Stopwatch or Pomodoro, tune the Pomodoro cycle, choose a
  soundtrack, set the volume, and toggle **Focus effects** (the master switch).
- **⚙ Edit** in the panel: rename/set soundtrack URIs, toggle block categories,
  add extra domains.
- Keyboard (panel focused): `Space` start/pause · `R` reset · `1`/`2` mode ·
  `S` skip Pomodoro phase.

## Settings

Editable in the widget settings, or `omarchy bar set io.github.gopher-boats.flowstate <key> <value>`:

| Key | Default | Meaning |
|-----|---------|---------|
| `focusEffects` | `true` | Master switch for all side-effects |
| `musicPlayer` | `auto` | `auto` (prefer ncspot), `ncspot`, or `spotify` |
| `alwaysShuffle` | `true` | Shuffle on start (honored by ncspot) |
| `slot1Label` / `slot1Uri` | Lofi | First soundtrack name + Spotify URI |
| `slot2Label` / `slot2Uri` | Nature | Second soundtrack |
| `slot3Label` / `slot3Uri` | Custom / (empty) | Third soundtrack (hidden if URI empty) |
| `activeSlot` | `0` | Selected soundtrack index |
| `spotifyVolume` | `40` | Focus volume (0–100); previous volume restored on stop |
| `spotifyWorkspace` | `9` | Workspace to place the player on (needs the window rule) |
| `blockSites` | `true` | Toggle site blocking |
| `catSocial`/`catVideo`/`catShopping`/`catNews` | `true` | Blocklist categories |
| `catAdult` | `false` | Adult category |
| `extraDomains` | (empty) | Extra comma/newline-separated domains |
| `openSpotify` | `true` | Open the music player on start |
| `openObsidian` | `true` | Open Obsidian on start |
| `pomodoroWorkMinutes` / `pomodoroShortBreakMinutes` / `pomodoroCycles` / `pomodoroLongBreakMinutes` | 25 / 5 / 4 / 15 | Pomodoro cycle |
| `pomodoroSound` | `true` | Bells between phases / at completion |

## Scripting (IPC)

```sh
id=io.github.gopher-boats.flowstate
omarchy-shell "$id" status
omarchy-shell "$id" stopwatch
omarchy-shell "$id" pomodoro 25 5 4 15
omarchy-shell "$id" start        # pause | toggleTimer | skip | reset
omarchy-shell "$id" open         # close | toggle
```

## Dependencies

`ncspot` (recommended) or `spotify`, `obsidian`, `dbus-send` (MPRIS), `pactl`
(per-app volume), `pgrep`, `resolvectl`, and Omarchy's `omarchy-notification-send`
/ `pw-play`. Requires the Omarchy Quattro shell + Hyprland.

## License

MIT — see [LICENSE](LICENSE).
