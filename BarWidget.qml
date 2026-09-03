import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "." as Core

BarWidget {
  id: root
  moduleName: "io.github.keegan-sucks.flowstate"

  readonly property bool active: Core.FocusState.isSessionActive
  readonly property bool onBreak: Core.FocusState.onBreak
  readonly property color phaseColor: root.onBreak ? Core.FocusState.breakColor : Color.accent

  function configuredInt(key, fallback, minimum, maximum) {
    var v = Number(root.setting(key, fallback))
    if (!isFinite(v)) v = fallback
    return Math.max(minimum, Math.min(maximum, Math.round(v)))
  }
  function configuredReal(key, fallback, minimum, maximum) {
    var v = Number(root.setting(key, fallback))
    if (!isFinite(v)) v = fallback
    return Math.max(minimum, Math.min(maximum, v))
  }

  function applySettings() {
    var st = Core.FocusState
    st.workMinutes = root.configuredInt("workMinutes", 25, 1, 999)
    st.shortBreakMinutes = root.configuredInt("shortBreakMinutes", 5, 1, 999)
    st.cycles = root.configuredInt("cycles", 4, 1, 99)

    st.playSoundtrack = root.setting("playSoundtrack", true) !== false
    st.spotifyVolume = root.configuredInt("spotifyVolume", 35, 0, 100)
    st.alwaysShuffle = root.setting("alwaysShuffle", true) !== false
    st.spotifyWorkspace = root.configuredInt("spotifyWorkspace", 9, 0, 99)
    st.nowPlaying = root.setting("nowPlaying", false) === true

    st.slot1Label = String(root.setting("slot1Label", st.slot1Label))
    st.slot1Uri = String(root.setting("slot1Uri", st.slot1Uri))
    st.slot2Label = String(root.setting("slot2Label", st.slot2Label))
    st.slot2Uri = String(root.setting("slot2Uri", st.slot2Uri))
    st.slot3Label = String(root.setting("slot3Label", st.slot3Label))
    st.slot3Uri = String(root.setting("slot3Uri", st.slot3Uri))
    st.setActiveSlot(root.configuredInt("activeSlot", 2, 0, 2))

    st.soundsEnabled = root.setting("soundsEnabled", true) !== false
    st.shortBreakSound = String(root.setting("shortBreakSound", st.shortBreakSound))
    st.backToWorkSound = String(root.setting("backToWorkSound", st.backToWorkSound))
    st.longBreakSound = String(root.setting("longBreakSound", st.longBreakSound))
    st.shortBreakVolume = root.configuredReal("shortBreakVolume", 1.0, 0, 1)
    st.backToWorkVolume = root.configuredReal("backToWorkVolume", 1.0, 0, 1)
    st.longBreakVolume = root.configuredReal("longBreakVolume", 1.0, 0, 1)

    st.focusGlyph = String(root.setting("focusGlyph", st.focusGlyph))
    st.breakGlyph = String(root.setting("breakGlyph", st.breakGlyph))
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
    target: "io.github.keegan-sucks.flowstate"

    function start(): string {
      if (!Core.FocusState.running) Core.FocusState.startPause()
      return Core.FocusState.statusText
    }
    function pause(): string { Core.FocusState.pause(); return Core.FocusState.statusText }
    function toggleTimer(): string { Core.FocusState.startPause(); return Core.FocusState.statusText }
    function reset(): string { Core.FocusState.reset(); return Core.FocusState.statusText }
    function skip(): string { Core.FocusState.skip(); return Core.FocusState.statusText }
    function next(): string { Core.FocusState.nextTrack(); return Core.FocusState.statusText }

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }

    function status(): string {
      return JSON.stringify({
        phase: Core.FocusState.phase,
        running: Core.FocusState.running,
        label: Core.FocusState.phaseLabel,
        dots: Core.FocusState.dotsText,
        display: Core.FocusState.displayText,
        soundtrack: Core.FocusState.slotLabel(Core.FocusState.activeSlot),
        focusActive: Core.FocusState.focusActive
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
    tooltipText: "Flowstate · " + Core.FocusState.statusText
    onPressed: function(b) {
      if (b === Qt.MiddleButton) Core.FocusState.startPause()
      else if (b === Qt.RightButton) Core.FocusState.reset()
      else root.toggle()
    }

    Rectangle {
      anchors.fill: parent
      anchors.margins: Style.space(2)
      radius: height / 2
      visible: root.active
      color: Qt.rgba(root.phaseColor.r, root.phaseColor.g, root.phaseColor.b,
                     Core.FocusState.running ? 0.18 : 0.10)
    }

    Row {
      id: timerRow
      anchors.centerIn: parent
      spacing: Style.space(5)

      Text {
        text: Core.FocusState.glyph
        color: root.active ? root.phaseColor : (button.active ? button.activeColor : button.foreground)
        font.family: button.fontFamily
        font.pixelSize: Math.round(Style.font.iconLarge * 1.1)
        renderType: Text.NativeRendering
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        visible: !root.vertical && root.active
        text: Core.FocusState.dotsText
        color: root.active ? root.phaseColor : button.foreground
        font.family: button.fontFamily
        font.pixelSize: Math.round(button.fontSize * 0.85)
        renderType: Text.NativeRendering
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        visible: !root.vertical && Core.FocusState.barTimeText !== ""
        text: Core.FocusState.barTimeText
        color: root.active ? root.phaseColor : button.foreground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }
}
