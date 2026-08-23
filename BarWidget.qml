import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "." as Core

BarWidget {
  id: root
  moduleName: "io.github.keegan-sucks.flowstate"

  readonly property bool sessionVisible: Core.FocusState.mode === Core.FocusState.pomodoroMode
    && Core.FocusState.pomodoroSessionStarted
  readonly property bool onBreak: Core.FocusState.onBreak
  readonly property color phaseColor: root.onBreak
    ? Core.FocusState.pomodoroBreakColor
    : Color.accent

  function configuredInt(key, fallback, minimum, maximum) {
    var parsed = Number(root.setting(key, fallback))
    if (!isFinite(parsed)) parsed = fallback
    return Math.max(minimum, Math.min(maximum, Math.round(parsed)))
  }

  function applySettings() {
    var st = Core.FocusState
    st.configurePomodoro(
      root.configuredInt("pomodoroWorkMinutes", 25, 1, 999),
      root.configuredInt("pomodoroShortBreakMinutes", 5, 1, 999),
      root.configuredInt("pomodoroCycles", 4, 1, 99),
      root.configuredInt("pomodoroLongBreakMinutes", 15, 1, 999),
      root.setting("pomodoroSound", true) !== false
    )
    st.focusEffects = root.setting("focusEffects", true) !== false
    st.slot1Label = String(root.setting("slot1Label", st.slot1Label))
    st.slot1Uri = String(root.setting("slot1Uri", st.slot1Uri))
    st.slot2Label = String(root.setting("slot2Label", st.slot2Label))
    st.slot2Uri = String(root.setting("slot2Uri", st.slot2Uri))
    st.slot3Label = String(root.setting("slot3Label", st.slot3Label))
    st.slot3Uri = String(root.setting("slot3Uri", st.slot3Uri))
    st.setActiveSlot(root.configuredInt("activeSlot", 0, 0, 2))
    st.spotifyVolume = root.configuredInt("spotifyVolume", 40, 0, 100)
    st.blockSites = root.setting("blockSites", true) !== false
    st.catSocial = root.setting("catSocial", true) !== false
    st.catVideo = root.setting("catVideo", true) !== false
    st.catShopping = root.setting("catShopping", true) !== false
    st.catNews = root.setting("catNews", true) !== false
    st.catAdult = root.setting("catAdult", false) === true
    st.extraDomains = String(root.setting("extraDomains", st.extraDomains))
    st.openSpotify = root.setting("openSpotify", true) !== false
    st.openObsidian = root.setting("openObsidian", true) !== false
    st.spotifyWorkspace = root.configuredInt("spotifyWorkspace", 9, 0, 99)
    st.musicPlayer = String(root.setting("musicPlayer", "auto"))
    st.alwaysShuffle = root.setting("alwaysShuffle", true) !== false
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: {
    applySettings()
    injectPanel()
  }
  Component.onCompleted: applySettings()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    // Literal target: IpcHandler registers during construction, before the
    // bar host has necessarily injected the widget's properties.
    target: "io.github.keegan-sucks.flowstate"

    function start(): string {
      if (!Core.FocusState.running) Core.FocusState.startPause()
      return Core.FocusState.statusText
    }
    function pause(): string {
      Core.FocusState.pause()
      return Core.FocusState.statusText
    }
    function toggleTimer(): string {
      Core.FocusState.startPause()
      return Core.FocusState.statusText
    }
    function reset(): string {
      Core.FocusState.reset()
      return Core.FocusState.statusText
    }
    function skip(): string {
      Core.FocusState.skipPomodoroPhase()
      return Core.FocusState.statusText
    }
    function stopwatch(): string {
      Core.FocusState.selectMode(Core.FocusState.stopwatchMode)
      return Core.FocusState.statusText
    }
    function pomodoro(workMinutes: string, shortBreakMinutes: string, cycles: string, longBreakMinutes: string): string {
      Core.FocusState.selectMode(Core.FocusState.pomodoroMode)
      Core.FocusState.setPomodoroWorkMinutes(parseInt(workMinutes, 10) || 25)
      Core.FocusState.setPomodoroShortBreakMinutes(parseInt(shortBreakMinutes, 10) || 5)
      Core.FocusState.setPomodoroCycles(parseInt(cycles, 10) || 4)
      Core.FocusState.setPomodoroLongBreakMinutes(parseInt(longBreakMinutes, 10) || 15)
      return Core.FocusState.statusText
    }

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }

    function status(): string {
      return JSON.stringify({
        mode: Core.FocusState.modeName,
        running: Core.FocusState.running,
        completed: Core.FocusState.completed,
        display: Core.FocusState.displayText,
        status: Core.FocusState.statusText,
        phase: Core.FocusState.mode === Core.FocusState.pomodoroMode
          ? Core.FocusState.pomodoroPhase.label
          : "",
        completedPomodoros: Core.FocusState.mode === Core.FocusState.pomodoroMode
          ? Core.FocusState.pomodoroCompletedCycles
          : 0,
        focusActive: Core.FocusState.focusActive,
        soundtrack: Core.FocusState.slotLabel(Core.FocusState.activeSlot)
      })
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical
      ? -1
      : timerRow.implicitWidth + button.scaledHorizontalMargin * 2
    active: Core.FocusState.running
    tooltipText: Core.FocusState.modeName + " · " + Core.FocusState.statusText
    onPressed: function(b) {
      if (b === Qt.MiddleButton) Core.FocusState.startPause()
      else if (b === Qt.RightButton) Core.FocusState.reset()
      else root.toggle()
    }

    Rectangle {
      anchors.fill: parent
      anchors.margins: Style.space(2)
      radius: height / 2
      visible: root.sessionVisible
      color: Qt.rgba(
        root.phaseColor.r,
        root.phaseColor.g,
        root.phaseColor.b,
        Core.FocusState.running ? 0.18 : 0.10
      )
    }

    Row {
      id: timerRow
      anchors.centerIn: parent
      spacing: Style.space(5)

      Text {
        text: root.onBreak ? "󰅶" : "◷"
        color: root.sessionVisible
          ? root.phaseColor
          : button.active ? button.activeColor : button.foreground
        font.family: button.fontFamily
        font.pixelSize: Math.round(Style.font.iconLarge * 1.15)
        renderType: Text.NativeRendering
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        visible: !root.vertical && Core.FocusState.barTimeText !== ""
        text: Core.FocusState.barTimeText
        color: root.sessionVisible
          ? root.phaseColor
          : button.active ? button.activeColor : button.foreground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }
}
