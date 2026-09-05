import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "." as Core

Panel {
  id: root
  moduleName: "io.github.keegan-sucks.flowstate"
  ipcTarget: "io.github.keegan-sucks.flowstate"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool canEditTimer: !Core.FocusState.isSessionActive

  property bool editing: false

  readonly property var soundOptions: [
    { value: "bell", label: "Bell" },
    { value: "complete", label: "Complete" },
    { value: "message", label: "Message" },
    { value: "message-new-instant", label: "Message (instant)" },
    { value: "alarm-clock-elapsed", label: "Alarm" },
    { value: "dialog-information", label: "Info" },
    { value: "dialog-warning", label: "Warning" },
    { value: "window-attention", label: "Attention" },
    { value: "device-added", label: "Device added" },
    { value: "service-login", label: "Login" },
    { value: "service-logout", label: "Logout" },
    { value: "power-plug", label: "Power plug" },
    { value: "power-unplug", label: "Power unplug" },
    { value: "phone-incoming-call", label: "Phone" },
    { value: "camera-shutter", label: "Shutter" }
  ]

  function startPause() { Core.FocusState.startPause() }
  function resetTimer() { Core.FocusState.reset() }

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]
    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function chooseSlot(i) {
    Core.FocusState.setActiveSlot(i)
    root.persistSettings({ activeSlot: Core.FocusState.activeSlot })
  }
  function setSlotLabel(i, v) {
    v = String(v)
    if (i === 0) { Core.FocusState.slot1Label = v; root.persistSettings({ slot1Label: v }) }
    else if (i === 1) { Core.FocusState.slot2Label = v; root.persistSettings({ slot2Label: v }) }
    else { Core.FocusState.slot3Label = v; root.persistSettings({ slot3Label: v }) }
  }
  function setSlotTarget(i, v) {
    v = String(v).trim()
    if (i === 0) { Core.FocusState.slot1Uri = v; root.persistSettings({ slot1Uri: v }) }
    else if (i === 1) { Core.FocusState.slot2Uri = v; root.persistSettings({ slot2Uri: v }) }
    else { Core.FocusState.slot3Uri = v; root.persistSettings({ slot3Uri: v }) }
  }

  function setTimerField(key, value) {
    var s = ({})
    if (key === "work") { Core.FocusState.setWorkMinutes(value); s.workMinutes = Core.FocusState.workMinutes }
    else if (key === "short") { Core.FocusState.setShortBreakMinutes(value); s.shortBreakMinutes = Core.FocusState.shortBreakMinutes }
    else if (key === "cycles") { Core.FocusState.setCycles(value); s.cycles = Core.FocusState.cycles }
    root.persistSettings(s)
  }

  function setPlaySoundtrack(on) { Core.FocusState.playSoundtrack = Boolean(on); root.persistSettings({ playSoundtrack: Core.FocusState.playSoundtrack }) }
  function setAlwaysShuffle(on) { Core.FocusState.alwaysShuffle = Boolean(on); root.persistSettings({ alwaysShuffle: Core.FocusState.alwaysShuffle }) }
  function setSoundsEnabled(on) { Core.FocusState.soundsEnabled = Boolean(on); root.persistSettings({ soundsEnabled: Core.FocusState.soundsEnabled }) }
  function setWorkspace(v) {
    var n = Math.max(0, Math.min(99, Math.round(Number(v))))
    Core.FocusState.spotifyWorkspace = n; root.persistSettings({ spotifyWorkspace: n })
  }

  function setCueSound(cue, val) {
    val = String(val); var s = ({})
    if (cue === "short") { Core.FocusState.shortBreakSound = val; s.shortBreakSound = val }
    else if (cue === "back") { Core.FocusState.backToWorkSound = val; s.backToWorkSound = val }
    else { Core.FocusState.longBreakSound = val; s.longBreakSound = val }
    root.persistSettings(s)
  }
  function setCueVolume(cue, val) {
    var v = Math.max(0, Math.min(1, Number(val))); var s = ({})
    if (cue === "short") { Core.FocusState.shortBreakVolume = v; s.shortBreakVolume = v }
    else if (cue === "back") { Core.FocusState.backToWorkVolume = v; s.backToWorkVolume = v }
    else { Core.FocusState.longBreakVolume = v; s.longBreakVolume = v }
    root.persistSettings(s)
  }
  function cueSound(cue) { return cue === "short" ? Core.FocusState.shortBreakSound : cue === "back" ? Core.FocusState.backToWorkSound : Core.FocusState.longBreakSound }
  function cueVolume(cue) { return cue === "short" ? Core.FocusState.shortBreakVolume : cue === "back" ? Core.FocusState.backToWorkVolume : Core.FocusState.longBreakVolume }
  function previewCue(cue) { Core.FocusState.playSoundFile(cueSound(cue), cueVolume(cue)) }

  function setGlyph(which, val) {
    val = String(val)
    if (which === "focus") { Core.FocusState.focusGlyph = val; root.persistSettings({ focusGlyph: val }) }
    else { Core.FocusState.breakGlyph = val; root.persistSettings({ breakGlyph: val }) }
  }

  Component {
    id: timerIcon
    Text {
      text: Core.FocusState.glyph
      color: root.contentForeground
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.display
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(660))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editing
        || workField.field.activeFocus
        || shortField.field.activeFocus
        || cyclesField.field.activeFocus
      onActivateRequested: root.startPause()
      onCloseRequested: { if (root.editing) root.editing = false; else root.close() }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "r" || text === "R") root.resetTimer()
        else if (text === "s" || text === "S") Core.FocusState.skip()
        else if (text === "n" || text === "N") Core.FocusState.nextTrack()
        else if (text === "e" || text === "E") root.editing = !root.editing
      }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

        Binding {
          target: scrollArea.contentItem
          property: "interactive"
          value: panelColumn.implicitHeight > scrollArea.height
        }

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.space(12)

          // Header + gear
          Item {
            width: parent.width
            implicitHeight: Math.max(hero.implicitHeight, gearButton.implicitHeight)
            PanelHero {
              id: hero
              width: parent.width - gearButton.width - Style.space(8)
              iconComponent: timerIcon
              title: "Flowstate"
              meta: Core.FocusState.statusText
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
            }
            Button {
              id: gearButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: root.editing ? "✓" : "⚙"
              text: root.editing ? "Done" : ""
              fontSize: Style.font.bodySmall
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              bordered: true
              active: root.editing
              onClicked: root.editing = !root.editing
            }
          }

          PanelSeparator { foreground: root.contentForeground }

          // ===================== MAIN VIEW =====================
          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: !root.editing

            // Dots + phase
            Text {
              width: parent.width
              text: Core.FocusState.dotsText + "   " + Core.FocusState.phaseLabel.toUpperCase()
              color: Qt.darker(root.contentForeground, 1.3)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              horizontalAlignment: Text.AlignHCenter
            }

            // Big clock
            Text {
              width: parent.width
              text: Core.FocusState.displayText
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.displayLarge * 2
              font.bold: true
              horizontalAlignment: Text.AlignHCenter
            }

            // Progress bar
            Item {
              width: parent.width
              implicitHeight: Style.space(6)
              Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)
              }
              Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Core.FocusState.progress <= 0 ? 0 : Math.max(height, parent.width * Core.FocusState.progress)
                height: parent.height
                radius: height / 2
                color: Core.FocusState.onBreak ? Core.FocusState.breakColor : Color.accent
                Behavior on width { NumberAnimation { duration: 120 } }
              }
            }

            // Transport
            Row {
              width: parent.width
              spacing: Style.space(8)
              Button {
                width: Math.max(0, parent.width - skipButton.width - resetButton.width - parent.spacing * 2)
                text: Core.FocusState.running ? "Pause" : (Core.FocusState.isSessionActive ? "Resume" : "Start")
                iconText: Core.FocusState.running ? "Ⅱ" : "▶"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                bordered: true
                active: Core.FocusState.running
                onClicked: root.startPause()
              }
              Button {
                id: skipButton
                text: "Skip"
                iconText: "»"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                bordered: true
                enabled: Core.FocusState.isSessionActive
                opacity: enabled ? 1 : 0.5
                onClicked: Core.FocusState.skip()
              }
              Button {
                id: resetButton
                text: "Reset"
                iconText: "↻"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                bordered: true
                enabled: Core.FocusState.isSessionActive
                opacity: enabled ? 1 : 0.5
                onClicked: root.resetTimer()
              }
            }

            // Soundtrack slot buttons
            Row {
              width: parent.width
              spacing: Style.space(6)
              enabled: Core.FocusState.playSoundtrack
              opacity: enabled ? 1 : 0.5
              readonly property var slots: {
                var a = []
                for (var i = 0; i < 3; i++)
                  if (Core.FocusState.slotConfigured(i)) a.push({ index: i, label: Core.FocusState.slotLabel(i) })
                return a
              }
              readonly property real cellWidth: slots.length > 0 ? (width - spacing * (slots.length - 1)) / slots.length : width
              Repeater {
                model: parent.slots
                Button {
                  required property var modelData
                  width: parent.cellWidth
                  text: modelData.label
                  fontSize: Style.font.bodySmall
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  bordered: true
                  active: Core.FocusState.activeSlot === modelData.index
                  onClicked: root.chooseSlot(modelData.index)
                }
              }
            }

            Text {
              width: parent.width
              text: "Space start/pause · R reset · S skip · N next song · E edit"
              color: Qt.darker(root.contentForeground, 1.4)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }
          }

          // ===================== EDIT VIEW =====================
          Column {
            width: parent.width
            spacing: Style.space(12)
            visible: root.editing

            // ---- Timer ----
            PanelSectionHeader { text: "TIMER"; foreground: root.contentForeground; fontFamily: root.contentFontFamily }
            Row {
              width: parent.width
              spacing: Style.space(10)
              CompactField {
                id: workField
                width: (parent.width - parent.spacing * 2) / 3; fieldWidth: width
                label: "Focus"; from: 1; to: 999; value: Core.FocusState.workMinutes
                foreground: root.contentForeground; fontFamily: root.contentFontFamily
                enabled: root.canEditTimer; opacity: enabled ? 1 : 0.5
                onModified: function(v) { root.setTimerField("work", v) }
              }
              CompactField {
                id: shortField
                width: (parent.width - parent.spacing * 2) / 3; fieldWidth: width
                label: "Break"; from: 1; to: 999; value: Core.FocusState.shortBreakMinutes
                foreground: root.contentForeground; fontFamily: root.contentFontFamily
                enabled: root.canEditTimer; opacity: enabled ? 1 : 0.5
                onModified: function(v) { root.setTimerField("short", v) }
              }
              CompactField {
                id: cyclesField
                width: (parent.width - parent.spacing * 2) / 3; fieldWidth: width
                label: "Cycles"; from: 1; to: 99; value: Core.FocusState.cycles
                foreground: root.contentForeground; fontFamily: root.contentFontFamily
                enabled: root.canEditTimer; opacity: enabled ? 1 : 0.5
                onModified: function(v) { root.setTimerField("cycles", v) }
              }
            }

            PanelSeparator { foreground: root.contentForeground }

            // ---- Soundtrack ----
            PanelSectionHeader { text: "SOUNDTRACK"; foreground: root.contentForeground; fontFamily: root.contentFontFamily }
            Toggle {
              width: parent.width
              label: "Play soundtrack"
              description: "Drive the Spotify app: start on focus, pause on breaks, restore volume on stop"
              checked: Core.FocusState.playSoundtrack
              foreground: root.contentForeground; fontFamily: root.contentFontFamily
              onClicked: root.setPlaySoundtrack(!Core.FocusState.playSoundtrack)
            }
            Toggle {
              width: parent.width
              label: "Always shuffle"
              description: "Shuffle and start on a random track"
              checked: Core.FocusState.alwaysShuffle
              foreground: root.contentForeground; fontFamily: root.contentFontFamily
              onClicked: root.setAlwaysShuffle(!Core.FocusState.alwaysShuffle)
            }
            // Volume
            Column {
              width: parent.width
              spacing: Style.space(4)
              Item {
                width: parent.width; implicitHeight: Math.max(volH.implicitHeight, volV.implicitHeight)
                PanelSectionHeader { id: volH; text: "FOCUS VOLUME"; foreground: root.contentForeground; fontFamily: root.contentFontFamily; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter }
                Text { id: volV; text: Core.FocusState.spotifyVolume + "%"; color: Qt.darker(root.contentForeground, 1.4); font.family: root.contentFontFamily; font.pixelSize: Style.font.caption; font.bold: true; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter }
              }
              PanelSlider {
                width: parent.width; bar: root.bar; minimum: 0; maximum: 100; step: 5; integer: true
                value: Core.FocusState.spotifyVolume
                onMoved: function(v) { Core.FocusState.setSpotifyVolume(v) }
                onReleased: function(v) { Core.FocusState.setSpotifyVolume(v); root.persistSettings({ spotifyVolume: Core.FocusState.spotifyVolume }) }
              }
            }
            // Player workspace
            Row {
              width: parent.width; spacing: Style.space(10)
              Text { text: "Spotify workspace (when Flowstate launches it; 0 = leave)"; color: root.contentForeground; font.family: root.contentFontFamily; font.pixelSize: Style.font.body; anchors.verticalCenter: parent.verticalCenter; width: parent.width - wsField.width - parent.spacing }
              CompactField {
                id: wsField
                width: Style.space(90); fieldWidth: width
                label: ""; from: 0; to: 99; value: Core.FocusState.spotifyWorkspace
                foreground: root.contentForeground; fontFamily: root.contentFontFamily
                onModified: function(v) { root.setWorkspace(v) }
              }
            }

            // Slots
            PanelSectionHeader { text: "SOUNDTRACK SLOTS"; foreground: root.contentForeground; fontFamily: root.contentFontFamily }
            Repeater {
              model: 3
              Row {
                id: slotRow
                required property int index
                width: parent.width
                spacing: Style.space(6)
                TextField {
                  id: slotLabelField
                  width: Style.space(90)
                  text: Core.FocusState.slotLabel(slotRow.index)
                  placeholderText: "Name"
                  foreground: root.contentForeground; font.family: root.contentFontFamily
                  onEditingFinished: root.setSlotLabel(slotRow.index, text)
                  Keys.onReturnPressed: { root.setSlotLabel(slotRow.index, text); focus = false }
                  Keys.onEscapePressed: focus = false
                }
                TextField {
                  width: parent.width - slotLabelField.width - parent.spacing
                  text: Core.FocusState.slotUri(slotRow.index)
                  placeholderText: "spotify:playlist:… or open.spotify.com link (empty to hide)"
                  foreground: root.contentForeground; font.family: root.contentFontFamily
                  onEditingFinished: root.setSlotTarget(slotRow.index, text)
                  Keys.onReturnPressed: { root.setSlotTarget(slotRow.index, text); focus = false }
                  Keys.onEscapePressed: focus = false
                }
              }
            }

            Text {
              width: parent.width
              text: "Target: a Spotify playlist, album, or artist — its URI (spotify:playlist:…) or open.spotify.com link. Switch slots live during focus."
              color: Qt.darker(root.contentForeground, 1.4)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            // ---- Liked Songs ----
            PanelSectionHeader { text: "LIKED SONGS"; foreground: root.contentForeground; fontFamily: root.contentFontFamily }
            Text {
              width: parent.width
              visible: Core.FocusState.anySlotNeedsMirror
              text: "⚠ A slot still says 'liked' — Spotify can't play that directly. Replace it with a mirror playlist (below)."
              color: Core.FocusState.breakColor
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              wrapMode: Text.WordWrap
            }
            Text {
              width: parent.width
              text: "Spotify can't shuffle Liked Songs directly, so point a slot at a mirror playlist. Easiest, no setup: in Spotify open Liked Songs → Ctrl-A → right-click → Add to playlist → New playlist, then paste that playlist's link into a slot above."
              color: Qt.darker(root.contentForeground, 1.4)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
            Button {
              text: "Auto-refresh Liked Songs…"
              iconText: "⟳"
              fontSize: Style.font.bodySmall
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              bordered: true
              onClicked: Core.FocusState.openLikedSetup()
            }
            Text {
              width: parent.width
              text: "Optional — builds the mirror for you and keeps it in sync weekly. Needs your own free Spotify app (just a Client ID — no password, no secret). Opens a guided setup in a terminal."
              color: Qt.darker(root.contentForeground, 1.4)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            PanelSeparator { foreground: root.contentForeground }

            // ---- Sounds ----
            PanelSectionHeader { text: "PHASE SOUNDS"; foreground: root.contentForeground; fontFamily: root.contentFontFamily }
            Toggle {
              width: parent.width
              label: "Phase sounds"
              checked: Core.FocusState.soundsEnabled
              foreground: root.contentForeground; fontFamily: root.contentFontFamily
              onClicked: root.setSoundsEnabled(!Core.FocusState.soundsEnabled)
            }
            Repeater {
              model: [
                { cue: "short", label: "Short break" },
                { cue: "back", label: "Back to work" },
                { cue: "long", label: "Session end" }
              ]
              Column {
                id: cueCol
                required property var modelData
                width: parent.width
                spacing: Style.space(4)
                enabled: Core.FocusState.soundsEnabled
                opacity: enabled ? 1 : 0.5
                Text { text: cueCol.modelData.label; color: Qt.darker(root.contentForeground, 1.3); font.family: root.contentFontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true }
                Row {
                  width: parent.width
                  spacing: Style.space(6)
                  Dropdown {
                    id: sd
                    width: parent.width - previewBtn.width - parent.spacing
                    options: root.soundOptions
                    value: root.cueSound(cueCol.modelData.cue)
                    showLabel: false
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily
                    onChanged: function(v) { root.setCueSound(cueCol.modelData.cue, v) }
                  }
                  Button {
                    id: previewBtn
                    text: "▶"
                    foreground: root.contentForeground; fontFamily: root.contentFontFamily
                    bordered: true
                    onClicked: root.previewCue(cueCol.modelData.cue)
                  }
                }
                PanelSlider {
                  width: parent.width; bar: root.bar; minimum: 0; maximum: 100; step: 5; integer: true
                  value: Math.round(root.cueVolume(cueCol.modelData.cue) * 100)
                  onReleased: function(v) { root.setCueVolume(cueCol.modelData.cue, v / 100) }
                }
              }
            }

            PanelSeparator { foreground: root.contentForeground }

            // ---- Glyphs ----
            PanelSectionHeader { text: "BAR GLYPHS"; foreground: root.contentForeground; fontFamily: root.contentFontFamily }
            Row {
              width: parent.width; spacing: Style.space(10)
              Column {
                width: (parent.width - parent.spacing) / 2; spacing: Style.space(3)
                Text { text: "Focus"; color: Qt.darker(root.contentForeground, 1.3); font.family: root.contentFontFamily; font.pixelSize: Style.font.bodySmall }
                TextField {
                  width: parent.width
                  text: Core.FocusState.focusGlyph
                  foreground: root.contentForeground; font.family: root.contentFontFamily
                  onEditingFinished: root.setGlyph("focus", text)
                  Keys.onReturnPressed: { root.setGlyph("focus", text); focus = false }
                }
              }
              Column {
                width: (parent.width - parent.spacing) / 2; spacing: Style.space(3)
                Text { text: "Break"; color: Qt.darker(root.contentForeground, 1.3); font.family: root.contentFontFamily; font.pixelSize: Style.font.bodySmall }
                TextField {
                  width: parent.width
                  text: Core.FocusState.breakGlyph
                  foreground: root.contentForeground; font.family: root.contentFontFamily
                  onEditingFinished: root.setGlyph("break", text)
                  Keys.onReturnPressed: { root.setGlyph("break", text); focus = false }
                }
              }
            }
          }
        }
      }
    }
  }
}
