pragma Singleton

import QtQuick
import Quickshell

// Shared, long-lived Pomodoro timer + focus-session state — a port of the macOS
// Flowstate's TimerEngine, kept in lockstep with it:
//
//   focus 1 → short → focus 2 → short → … → focus `cycles`, then the session
//   ENDS with a long-break cue (there is NO timed long break).
//
// A running session drives a Spotify soundtrack via scripts/flowstate-session.sh
// (spotify_player): started once at the beginning, PAUSED during short breaks and
// RESUMED when focus returns, and stopped (volume restored + paused) at the end.
// Distinct phase-boundary sounds play at each transition.
Item {
  id: root

  // --- Timer configuration -------------------------------------------------
  property int workMinutes: 25
  property int shortBreakMinutes: 5
  property int cycles: 4

  // --- Live state ----------------------------------------------------------
  property string phase: "idle"                // idle | focus | short-break
  property int round: 1
  property int completedFocusBlocks: 0
  property bool running: false
  property double startedAt: 0
  property double storedElapsedMs: 0
  property double nowMs: Date.now()
  property int completionBellsRemaining: 0

  property color breakColor: "#a6e3a1"

  // --- Soundtrack (spotify_player) ----------------------------------------
  property bool playSoundtrack: true
  property int spotifyVolume: 35
  property bool alwaysShuffle: true
  property int spotifyWorkspace: 9             // 0 leaves the player where it is
  property bool nowPlaying: false              // notify on each song change

  // Three editable soundtrack slots. A target of "liked" plays Liked Songs.
  property string slot1Label: "Lofi"
  property string slot1Uri: "spotify:playlist:37i9dQZF1DWWQRwui0ExPn"
  property string slot2Label: "Nature"
  property string slot2Uri: "spotify:playlist:37i9dQZF1DX4PP3DA4J0N8"
  property string slot3Label: "Liked"
  property string slot3Uri: "liked"
  property int activeSlot: 2                    // 0-based; Liked by default

  // --- Phase-boundary sounds (freedesktop .oga names, minus extension) -----
  property bool soundsEnabled: true
  property string shortBreakSound: "bell"
  property string backToWorkSound: "complete"
  property string longBreakSound: "alarm-clock-elapsed"
  property real shortBreakVolume: 1.0
  property real backToWorkVolume: 1.0
  property real longBreakVolume: 1.0

  // --- Menu/bar glyphs -----------------------------------------------------
  property string focusGlyph: "⌖"
  property string breakGlyph: "☾"

  // True while the soundtrack side-effect is engaged (start → stop). Stays true
  // across pauses and breaks; the break/resume actions pause/play within it.
  property bool focusActive: false

  readonly property string sessionScript: {
    var u = Qt.resolvedUrl("scripts/flowstate-session.sh").toString()
    return u.replace(/^file:\/\//, "")
  }

  // --- Derived state -------------------------------------------------------
  readonly property bool isSessionActive: phase !== "idle"
  readonly property bool onBreak: phase === "short-break"

  readonly property double phaseDurationMs:
    (phase === "short-break" ? Math.max(1, shortBreakMinutes) : Math.max(1, workMinutes)) * 60000
  readonly property double elapsedMs:
    Math.max(0, Math.round(running ? storedElapsedMs + nowMs - startedAt : storedElapsedMs))
  readonly property double remainingMs: Math.max(0, phaseDurationMs - elapsedMs)
  readonly property real progress: phaseDurationMs > 0 ? Math.min(1, elapsedMs / phaseDurationMs) : 0

  // Idle shows the (possibly just-edited) focus length; otherwise the countdown.
  readonly property double displayMs: phase === "idle" ? Math.max(1, workMinutes) * 60000 : remainingMs

  readonly property string phaseLabel: phase === "idle"
    ? "Ready"
    : phase === "focus"
      ? "Focus " + round + " of " + cycles
      : "Short break"

  readonly property string statusText: {
    if (phase === "idle") return cycles + " cycles · " + workMinutes + " / " + shortBreakMinutes + " min"
    if (!running) return "Paused · " + phaseLabel
    return phaseLabel
  }

  // Filled/empty round dots, e.g. "●●○○".
  readonly property int filledDots: phase === "idle" ? 0 : (phase === "focus" ? round : completedFocusBlocks)
  readonly property string dotsText: {
    var total = Math.max(1, cycles)
    var filled = Math.min(Math.max(0, filledDots), total)
    var s = ""
    for (var i = 0; i < filled; i++) s += "●"
    for (var j = filled; j < total; j++) s += "○"
    return s
  }

  readonly property string glyph: onBreak ? breakGlyph : focusGlyph
  readonly property string displayText: formatTime(displayMs)
  readonly property string barTimeText: isSessionActive ? formatTime(displayMs) : ""

  function formatTime(milliseconds) {
    var total = Math.ceil(Math.max(0, milliseconds) / 1000)
    var m = Math.floor(total / 60)
    var s = total % 60
    return m + ":" + (s < 10 ? "0" + s : String(s))
  }

  // --- Transport (Space / R / S) ------------------------------------------

  function startPause() {
    if (running) { pause(); return }
    if (phase === "idle") beginSession()
    else resumeTimer()
  }

  function pause() {
    if (!running) return
    nowMs = Date.now()
    storedElapsedMs = elapsedMs
    running = false
    // Music intentionally stays engaged while paused (matches macOS).
  }

  function reset() {
    var wasActive = isSessionActive
    running = false
    phase = "idle"
    round = 1
    completedFocusBlocks = 0
    storedElapsedMs = 0
    nowMs = Date.now()
    startedAt = nowMs
    if (wasActive) musicStop()      // stop the soundtrack once (no cue on manual reset)
  }

  function skip() {
    if (phase === "idle") return
    if (phase === "focus") {
      if (round >= cycles) {
        finishSession()
        playCue("long-break")
      } else {
        enterPhase("short-break")
        playCue("short-break")
        musicBreak()
      }
    } else {                          // short-break
      round = completedFocusBlocks + 1
      enterPhase("focus")
      playCue("back-to-work")
      musicResume()
    }
  }

  // Skip the current SONG (not the phase).
  function nextTrack() { musicNext() }

  // --- Transitions ---------------------------------------------------------

  function completeCurrentPhase() {
    if (phase === "focus") {
      completedFocusBlocks = Math.min(cycles, completedFocusBlocks + 1)
      if (completedFocusBlocks >= cycles) {
        finishSession()
        playCue("long-break")         // no timed long break — just the cue
      } else {
        enterPhase("short-break")
        playCue("short-break")
        musicBreak()
      }
    } else if (phase === "short-break") {
      round = completedFocusBlocks + 1
      enterPhase("focus")
      playCue("back-to-work")
      musicResume()
    }
  }

  function beginSession() {
    phase = "focus"
    round = 1
    completedFocusBlocks = 0
    storedElapsedMs = 0
    nowMs = Date.now()
    startedAt = nowMs
    running = true
    musicStart()                      // start the soundtrack once
  }

  function resumeTimer() {
    if (running || phase === "idle") return
    nowMs = Date.now()
    startedAt = nowMs - storedElapsedMs
    running = true
  }

  function enterPhase(next) {
    phase = next
    storedElapsedMs = 0
    nowMs = Date.now()
    startedAt = nowMs
    // running unchanged — the ticker keeps counting (continuous advance).
  }

  function finishSession() {
    running = false
    phase = "idle"
    round = 1
    completedFocusBlocks = 0
    storedElapsedMs = 0
    nowMs = Date.now()
    startedAt = nowMs
    musicStop()
  }

  function tick() {
    nowMs = Date.now()
    if (!running) return
    if (elapsedMs >= phaseDurationMs) completeCurrentPhase()
  }

  // --- Config setters (called from BarWidget / Panel) ----------------------

  function setWorkMinutes(v)       { workMinutes = clampInt(v, 1, 999);  if (!isSessionActive) reset() }
  function setShortBreakMinutes(v) { shortBreakMinutes = clampInt(v, 1, 999); if (!isSessionActive) reset() }
  function setCycles(v)            { cycles = clampInt(v, 1, 99);        if (!isSessionActive) reset() }
  function setActiveSlot(i)        { activeSlot = clampInt(i, 0, 2) }
  function setSpotifyVolume(v)     { spotifyVolume = clampInt(v, 0, 100) }
  function clampInt(v, lo, hi)     { return Math.max(lo, Math.min(hi, Math.round(Number(v)))) }

  function slotLabel(i) { return i === 0 ? slot1Label : i === 1 ? slot2Label : slot3Label }
  function slotUri(i)   { return i === 0 ? slot1Uri : i === 1 ? slot2Uri : slot3Uri }
  function slotConfigured(i) { return String(slotUri(i)).length > 0 }

  function focusPlaylist() {
    var u = slotUri(activeSlot)
    if (u && u.length) return u
    for (var i = 0; i < 3; i++) if (slotConfigured(i)) return slotUri(i)
    return ""
  }

  // --- Soundtrack orchestration (scripts/flowstate-session.sh) --------------
  // Arg order MUST match the script: <action> <playlist> <volume> <workspace>
  //                                  <shuffle 0|1> <nowPlaying 0|1>
  function runSession(action) {
    Quickshell.execDetached([
      "bash", sessionScript, action,
      focusPlaylist(), String(spotifyVolume), String(spotifyWorkspace),
      alwaysShuffle ? "1" : "0", nowPlaying ? "1" : "0"
    ])
  }

  function musicStart() {
    if (!playSoundtrack || focusActive) return
    focusActive = true
    runSession("on")
  }
  function musicStop() {
    if (!focusActive) return
    focusActive = false
    runSession("off")
  }
  function musicBreak()  { if (playSoundtrack && focusActive) runSession("break") }
  function musicResume() { if (playSoundtrack && focusActive) runSession("resume") }
  function musicNext()   { if (playSoundtrack && focusActive) runSession("next") }

  // --- Phase-boundary sounds ----------------------------------------------

  function playCue(cue) {
    if (!soundsEnabled) return
    if (cue === "short-break") playSoundFile(shortBreakSound, shortBreakVolume)
    else if (cue === "back-to-work") playSoundFile(backToWorkSound, backToWorkVolume)
    else playSoundFile(longBreakSound, longBreakVolume)
  }

  function playSoundFile(name, volume) {
    if (!name || name.length === 0) return
    Quickshell.execDetached([
      "pw-play", "--volume", String(Math.max(0, Math.min(1, volume))),
      "/usr/share/sounds/freedesktop/stereo/" + name + ".oga"
    ])
  }

  function notify(message) {
    Quickshell.execDetached(["omarchy-notification-send", "-g", "◷", "Flowstate", message])
  }

  Timer {
    interval: 250
    repeat: true
    running: root.running
    onTriggered: root.tick()
  }
}
