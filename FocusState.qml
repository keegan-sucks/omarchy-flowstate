pragma Singleton

import QtQuick
import Quickshell

// Shared, long-lived timer + focus-session state. Modeled on Clockwork's
// TimerState but trimmed to two modes (Stopwatch, Pomodoro) and extended with
// the "focus session" orchestration: when a session starts we shell out to
// scripts/flowstate-session.sh to block sites, start Spotify, and open
// Obsidian; when it ends we unblock and pause Spotify.
Item {
  id: root

  readonly property int stopwatchMode: 0
  readonly property int pomodoroMode: 1

  property int mode: pomodoroMode
  property bool running: false
  property bool completed: false
  property double startedAt: 0
  property double storedElapsedMs: 0
  property double nowMs: Date.now()
  property int completionBellsRemaining: 0

  // --- Pomodoro configuration / progress -----------------------------------
  property int pomodoroWorkMinutes: 25
  property int pomodoroShortBreakMinutes: 5
  property int pomodoroCycles: 4
  property int pomodoroLongBreakMinutes: 15
  property bool pomodoroSoundEnabled: true
  property color pomodoroBreakColor: "#a6e3a1"
  property string pomodoroPhaseKind: "focus"   // focus | short-break | long-break
  property int pomodoroCurrentCycle: 1
  property int pomodoroCompletedCycles: 0
  property bool pomodoroSessionStarted: false

  // --- Focus-session configuration (pushed in from BarWidget settings) -----
  property bool focusEffects: true

  // Soundtrack slots — each an editable {label, uri}, chosen/edited in the
  // panel. Slot 3 is empty by default and hidden until the user configures it.
  property string slot1Label: "Lofi"
  property string slot1Uri: "spotify:playlist:37i9dQZF1DWWQRwui0ExPn"
  property string slot2Label: "Nature"
  property string slot2Uri: "spotify:playlist:37i9dQZF1DX4PP3DA4J0N8"
  property string slot3Label: "Liked"
  property string slot3Uri: "liked"             // sentinel: ncspot Liked Songs (see script)
  property int activeSlot: 0                    // 0-based index of the chosen slot

  property int spotifyVolume: 40

  // Blocklist categories (domains come from the bundled blocklists/*.txt).
  property bool blockSites: true
  property bool catSocial: true
  property bool catVideo: true
  property bool catShopping: true
  property bool catNews: true
  property bool catAdult: false
  property string extraDomains: ""

  property bool openSpotify: true              // open the music player on start
  property bool openObsidian: true
  property int spotifyWorkspace: 9             // 0 disables the placement
  property string musicPlayer: "auto"          // auto | ncspot | spotify
  property bool alwaysShuffle: true            // honored by ncspot

  // True while a focus session's side-effects are engaged. Stays true across
  // pauses and breaks — released only on reset() or full completion.
  property bool focusActive: false

  // Absolute path to the orchestration script, resolved relative to this file
  // so the plugin keeps working if the directory is renamed or relocated.
  readonly property string sessionScript: {
    var u = Qt.resolvedUrl("scripts/flowstate-session.sh").toString()
    return u.replace(/^file:\/\//, "")
  }

  readonly property double pomodoroWorkMs: Math.max(1, pomodoroWorkMinutes) * 60000
  readonly property double pomodoroShortBreakMs: Math.max(1, pomodoroShortBreakMinutes) * 60000
  readonly property double pomodoroLongBreakMs: Math.max(1, pomodoroLongBreakMinutes) * 60000
  readonly property double pomodoroPhaseDurationMs: pomodoroPhaseKind === "long-break"
    ? pomodoroLongBreakMs
    : pomodoroPhaseKind === "short-break"
      ? pomodoroShortBreakMs
      : pomodoroWorkMs
  readonly property double targetMs: mode === pomodoroMode ? pomodoroPhaseDurationMs : 0
  readonly property double elapsedMs: Math.max(0, Math.round(running ? storedElapsedMs + nowMs - startedAt : storedElapsedMs))

  readonly property var pomodoroPhase: ({
    kind: pomodoroPhaseKind,
    cycle: pomodoroCurrentCycle,
    label: pomodoroPhaseKind === "focus"
      ? "Focus " + pomodoroCurrentCycle + " of " + pomodoroCycles
      : pomodoroPhaseKind === "long-break"
        ? "Long break"
        : "Short break · Cycle " + pomodoroCurrentCycle + " of " + pomodoroCycles,
    durationMs: pomodoroPhaseDurationMs,
    elapsedMs: Math.min(elapsedMs, pomodoroPhaseDurationMs),
    remainingMs: Math.max(0, pomodoroPhaseDurationMs - elapsedMs)
  })

  readonly property double displayMs: mode === stopwatchMode
    ? elapsedMs
    : pomodoroPhase.remainingMs
  readonly property real progress: mode === stopwatchMode
    ? 0
    : pomodoroPhase.durationMs > 0
      ? Math.min(1, pomodoroPhase.elapsedMs / pomodoroPhase.durationMs)
      : 0

  readonly property string modeName: mode === stopwatchMode ? "Stopwatch" : "Pomodoro"
  readonly property bool onBreak: mode === pomodoroMode
    && pomodoroSessionStarted
    && pomodoroPhaseKind !== "focus"

  readonly property string statusText: {
    if (completed) return mode === pomodoroMode ? "Pomodoro complete" : "Time is up"
    if (mode === pomodoroMode) {
      if (running) return pomodoroPhase.label
      if (pomodoroSessionStarted) return "Paused · " + pomodoroPhase.label
      return pomodoroCycles + " cycles · " + pomodoroWorkMinutes + " / " + pomodoroShortBreakMinutes + " min"
    }
    if (running) return "Counting up"
    if (storedElapsedMs > 0) return "Paused"
    return "Ready"
  }

  readonly property string displayText: formatTime(displayMs, mode === stopwatchMode)
  readonly property string barTimeText: running || storedElapsedMs > 0 || completed
    || (mode === pomodoroMode && pomodoroSessionStarted)
    ? formatTime(displayMs, false)
    : ""

  function formatTime(milliseconds, showCentiseconds) {
    var safeMilliseconds = Math.max(0, Math.floor(milliseconds))
    var totalSeconds = showCentiseconds || mode === stopwatchMode
      ? Math.floor(safeMilliseconds / 1000)
      : Math.ceil(milliseconds / 1000)
    var hours = Math.floor(totalSeconds / 3600)
    var minutes = Math.floor((totalSeconds % 3600) / 60)
    var seconds = totalSeconds % 60
    var mm = minutes < 10 ? "0" + minutes : String(minutes)
    var ss = seconds < 10 ? "0" + seconds : String(seconds)
    var result = hours > 0 ? hours + ":" + mm + ":" + ss : mm + ":" + ss
    if (!showCentiseconds) return result
    var centiseconds = Math.floor((safeMilliseconds % 1000) / 10)
    return result + "." + (centiseconds < 10 ? "0" : "") + centiseconds
  }

  function pad2(value) {
    return value < 10 ? "0" + value : String(value)
  }

  // --- Mode / transport ----------------------------------------------------

  function selectMode(nextMode) {
    nextMode = nextMode === stopwatchMode ? stopwatchMode : pomodoroMode
    if (nextMode === mode) return
    mode = nextMode
    reset()
  }

  function startPause() {
    if (running) {
      pause()
      return
    }
    if (completed) reset()
    if (mode === pomodoroMode && targetMs <= 0) return
    if (mode === pomodoroMode) pomodoroSessionStarted = true
    nowMs = Date.now()
    startedAt = nowMs
    running = true
    engageFocus()
  }

  function pause() {
    if (!running) return
    nowMs = Date.now()
    storedElapsedMs = elapsedMs
    running = false
    // Deliberately does NOT release focus — a paused session stays "in focus".
  }

  function reset() {
    running = false
    completed = false
    storedElapsedMs = 0
    nowMs = Date.now()
    startedAt = nowMs
    if (mode === pomodoroMode) {
      pomodoroPhaseKind = "focus"
      pomodoroCurrentCycle = 1
      pomodoroCompletedCycles = 0
      pomodoroSessionStarted = false
    }
    disengageFocus()
  }

  // --- Pomodoro configuration setters (called from BarWidget/Panel) --------

  function setPomodoroWorkMinutes(value) {
    pomodoroWorkMinutes = Math.max(1, Math.min(999, Number(value)))
    reset()
  }

  function setPomodoroShortBreakMinutes(value) {
    pomodoroShortBreakMinutes = Math.max(1, Math.min(999, Number(value)))
    reset()
  }

  function setPomodoroCycles(value) {
    pomodoroCycles = Math.max(1, Math.min(99, Number(value)))
    reset()
  }

  function setPomodoroLongBreakMinutes(value) {
    pomodoroLongBreakMinutes = Math.max(1, Math.min(999, Number(value)))
    reset()
  }

  function setPomodoroSoundEnabled(enabled) {
    pomodoroSoundEnabled = Boolean(enabled)
  }

  function slotLabel(i) { return i === 0 ? slot1Label : i === 1 ? slot2Label : slot3Label }
  function slotUri(i) { return i === 0 ? slot1Uri : i === 1 ? slot2Uri : slot3Uri }
  function slotConfigured(i) { return String(slotUri(i)).length > 0 }

  function setActiveSlot(i) { activeSlot = Math.max(0, Math.min(2, Math.round(Number(i)))) }

  function setSpotifyVolume(value) {
    spotifyVolume = Math.max(0, Math.min(100, Math.round(Number(value))))
  }

  // Bulk-apply pomodoro numbers without a reset per field (used on settings load).
  function configurePomodoro(workMinutes, shortBreakMinutes, cycles, longBreakMinutes, soundEnabled) {
    var nextWork = Math.max(1, Math.min(999, Number(workMinutes)))
    var nextShort = Math.max(1, Math.min(999, Number(shortBreakMinutes)))
    var nextCycles = Math.max(1, Math.min(99, Number(cycles)))
    var nextLong = Math.max(1, Math.min(999, Number(longBreakMinutes)))
    var changed = nextWork !== pomodoroWorkMinutes
      || nextShort !== pomodoroShortBreakMinutes
      || nextCycles !== pomodoroCycles
      || nextLong !== pomodoroLongBreakMinutes
    pomodoroWorkMinutes = nextWork
    pomodoroShortBreakMinutes = nextShort
    pomodoroCycles = nextCycles
    pomodoroLongBreakMinutes = nextLong
    pomodoroSoundEnabled = Boolean(soundEnabled)
    if (changed && mode === pomodoroMode && !pomodoroSessionStarted) reset()
  }

  // --- Pomodoro phase machine ---------------------------------------------

  function beginPomodoroPhase(kind, cycle, autoRun) {
    pomodoroPhaseKind = kind
    pomodoroCurrentCycle = Math.max(1, Math.min(pomodoroCycles, Number(cycle)))
    storedElapsedMs = 0
    nowMs = Date.now()
    startedAt = nowMs
    running = Boolean(autoRun)
    completed = false
    pomodoroSessionStarted = true
  }

  function skipPomodoroPhase() {
    if (mode !== pomodoroMode || !pomodoroSessionStarted || completed) return
    if (pomodoroPhaseKind === "focus") {
      beginPomodoroPhase("short-break", pomodoroCurrentCycle, true)
      notify("Focus skipped · Short break starts now")
      return
    }
    if (pomodoroPhaseKind === "short-break") {
      beginPomodoroPhase("focus", pomodoroCompletedCycles + 1, false)
      notify("Break skipped · Ready for focus " + pomodoroCurrentCycle)
      return
    }
    finishPomodoroCycle(false)
  }

  function completePomodoroPhase() {
    if (pomodoroPhaseKind === "focus") {
      pomodoroCompletedCycles = Math.min(pomodoroCycles, pomodoroCompletedCycles + 1)
      var longBreak = pomodoroCompletedCycles >= pomodoroCycles
      beginPomodoroPhase(longBreak ? "long-break" : "short-break", pomodoroCompletedCycles, true)
      playPomodoroSound()
      notify(longBreak
        ? "Focus " + pomodoroCompletedCycles + " complete · Long break starts now"
        : "Focus " + pomodoroCompletedCycles + " complete · Short break starts now")
      return
    }
    if (pomodoroPhaseKind === "long-break") {
      finishPomodoroCycle(true)
      return
    }
    beginPomodoroPhase("focus", pomodoroCompletedCycles + 1, false)
    playPomodoroSound()
    notify("Break complete · Ready for focus " + pomodoroCurrentCycle)
  }

  function finishPomodoroCycle(withSound) {
    storedElapsedMs = pomodoroPhaseDurationMs
    running = false
    completed = true
    pomodoroSessionStarted = true
    if (withSound) playCompletionSequence()
    notify("All " + pomodoroCycles + " focus cycles complete")
    disengageFocus()
  }

  function tick() {
    nowMs = Date.now()
    if (!running || mode === stopwatchMode) return
    if (elapsedMs >= targetMs) completePomodoroPhase()
  }

  // --- Focus-session side effects -----------------------------------------

  function focusPlaylist() {
    var u = slotUri(activeSlot)
    if (u && u.length) return u
    for (var i = 0; i < 3; i++) if (slotConfigured(i)) return slotUri(i)
    return ""
  }

  // Comma-separated list of enabled blocklist categories for the script.
  function focusCategoriesCsv() {
    var c = []
    if (catSocial) c.push("social")
    if (catVideo) c.push("video")
    if (catShopping) c.push("shopping")
    if (catNews) c.push("news")
    if (catAdult) c.push("adult")
    return c.join(",")
  }

  function runSession(action) {
    Quickshell.execDetached([
      "bash", sessionScript, action,
      focusPlaylist(), String(spotifyVolume),
      blockSites ? "1" : "0",
      openSpotify ? "1" : "0",
      openObsidian ? "1" : "0",
      focusCategoriesCsv(), String(extraDomains),
      String(spotifyWorkspace), String(musicPlayer),
      alwaysShuffle ? "1" : "0"
    ])
  }

  function engageFocus() {
    if (!focusEffects || focusActive) return
    focusActive = true
    runSession("on")
  }

  function disengageFocus() {
    if (!focusActive) return
    focusActive = false
    runSession("off")
  }

  // --- Sounds / notifications ---------------------------------------------

  function playSound(soundFile) {
    Quickshell.execDetached([
      "pw-play",
      "--volume", "1.0",
      "/usr/share/sounds/freedesktop/stereo/" + soundFile
    ])
  }

  function playCompletionSequence() {
    if (mode === pomodoroMode && !pomodoroSoundEnabled) return
    completionBellTimer.stop()
    completionBellsRemaining = 3
    playNextCompletionBell()
  }

  function playPomodoroSound() {
    if (pomodoroSoundEnabled) playSound("complete.oga")
  }

  function playNextCompletionBell() {
    if (completionBellsRemaining <= 0) return
    playSound("complete.oga")
    completionBellsRemaining -= 1
    if (completionBellsRemaining > 0) completionBellTimer.restart()
  }

  function notify(message) {
    Quickshell.execDetached([
      "omarchy-notification-send",
      "-g", "◷",
      "Flowstate",
      message
    ])
  }

  Timer {
    interval: root.mode === root.stopwatchMode ? 10 : 100
    repeat: true
    running: root.running
    onTriggered: root.tick()
  }

  Timer {
    id: completionBellTimer
    interval: 625
    repeat: false
    onTriggered: root.playNextCompletionBell()
  }
}
