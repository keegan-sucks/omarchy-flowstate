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
  readonly property bool canEdit: !Core.FocusState.running
    && !Core.FocusState.pomodoroSessionStarted
    && !Core.FocusState.completed

  function startPause() { Core.FocusState.startPause() }
  function resetTimer() { Core.FocusState.reset() }

  // Persist a settings delta back into this widget's shell.json entry, so
  // choices made in the panel survive a shell restart.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // Whether the soundtrack / cycle / blocklist editor is open in the panel.
  property bool editing: false

  function chooseSlot(index) {
    Core.FocusState.setActiveSlot(index)
    root.persistSettings({ activeSlot: Core.FocusState.activeSlot })
  }

  function setSlotLabel(index, value) {
    var v = String(value)
    if (index === 0) { Core.FocusState.slot1Label = v; root.persistSettings({ slot1Label: v }) }
    else if (index === 1) { Core.FocusState.slot2Label = v; root.persistSettings({ slot2Label: v }) }
    else { Core.FocusState.slot3Label = v; root.persistSettings({ slot3Label: v }) }
  }

  function setSlotUri(index, value) {
    var v = String(value).trim()
    if (index === 0) { Core.FocusState.slot1Uri = v; root.persistSettings({ slot1Uri: v }) }
    else if (index === 1) { Core.FocusState.slot2Uri = v; root.persistSettings({ slot2Uri: v }) }
    else { Core.FocusState.slot3Uri = v; root.persistSettings({ slot3Uri: v }) }
  }

  function setCategory(key, on) {
    var b = Boolean(on)
    var s = ({})
    if (key === "social") { Core.FocusState.catSocial = b; s.catSocial = b }
    else if (key === "video") { Core.FocusState.catVideo = b; s.catVideo = b }
    else if (key === "shopping") { Core.FocusState.catShopping = b; s.catShopping = b }
    else if (key === "news") { Core.FocusState.catNews = b; s.catNews = b }
    else if (key === "adult") { Core.FocusState.catAdult = b; s.catAdult = b }
    root.persistSettings(s)
  }

  function setExtraDomains(value) {
    Core.FocusState.extraDomains = String(value)
    root.persistSettings({ extraDomains: Core.FocusState.extraDomains })
  }

  function categoryChecked(key) {
    if (key === "social") return Core.FocusState.catSocial
    if (key === "video") return Core.FocusState.catVideo
    if (key === "shopping") return Core.FocusState.catShopping
    if (key === "news") return Core.FocusState.catNews
    if (key === "adult") return Core.FocusState.catAdult
    return false
  }

  function setFocusEffects(on) {
    Core.FocusState.focusEffects = Boolean(on)
    root.persistSettings({ focusEffects: Core.FocusState.focusEffects })
  }

  function setPomodoroField(key, value) {
    var setting = ({})
    if (key === "work") {
      Core.FocusState.setPomodoroWorkMinutes(value)
      setting.pomodoroWorkMinutes = Core.FocusState.pomodoroWorkMinutes
    } else if (key === "short") {
      Core.FocusState.setPomodoroShortBreakMinutes(value)
      setting.pomodoroShortBreakMinutes = Core.FocusState.pomodoroShortBreakMinutes
    } else if (key === "cycles") {
      Core.FocusState.setPomodoroCycles(value)
      setting.pomodoroCycles = Core.FocusState.pomodoroCycles
    } else if (key === "long") {
      Core.FocusState.setPomodoroLongBreakMinutes(value)
      setting.pomodoroLongBreakMinutes = Core.FocusState.pomodoroLongBreakMinutes
    } else if (key === "sound") {
      Core.FocusState.setPomodoroSoundEnabled(Boolean(value))
      setting.pomodoroSound = Core.FocusState.pomodoroSoundEnabled
    }
    root.persistSettings(setting)
  }

  Component {
    id: timerIcon
    Text {
      text: Core.FocusState.onBreak ? "󰅶" : "◷"
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
    contentWidth: panel.fittedContentWidth(Style.space(380))
    // No fixed cap: fit to content, growing only up to what the screen allows,
    // so the everyday panel never needs to scroll.
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editing
        || workField.field.activeFocus
        || shortField.field.activeFocus
        || cyclesField.field.activeFocus
        || longField.field.activeFocus
      onActivateRequested: root.startPause()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "r" || text === "R") root.resetTimer()
        else if (text === "s" || text === "S") Core.FocusState.skipPomodoroPhase()
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

          PanelHero {
            width: parent.width
            iconComponent: timerIcon
            title: "Flowstate"
            meta: Core.FocusState.statusText
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          // ---- Transport controls, at the top so Start is always reachable
          //      without scrolling. Hidden while editing settings.
          Row {
            width: parent.width
            spacing: Style.space(8)
            visible: !root.editing

            Button {
              width: Math.max(0, parent.width - resetButton.width
                - (skipButton.visible ? skipButton.width + parent.spacing : 0)
                - parent.spacing)
              text: Core.FocusState.running
                ? "Pause"
                : Core.FocusState.completed ? "Start again" : "Start"
              iconText: Core.FocusState.running ? "Ⅱ" : "▶"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              bordered: true
              active: Core.FocusState.running
              onClicked: root.startPause()
            }

            Button {
              id: skipButton
              visible: Core.FocusState.pomodoroSessionStarted && !Core.FocusState.completed
              text: "Skip"
              iconText: "»"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              bordered: true
              onClicked: Core.FocusState.skipPomodoroPhase()
            }

            Button {
              id: resetButton
              text: "Reset"
              iconText: "↻"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              bordered: true
              enabled: Core.FocusState.running
                || Core.FocusState.storedElapsedMs > 0
                || Core.FocusState.completed
                || Core.FocusState.pomodoroSessionStarted
              opacity: enabled ? 1 : 0.5
              onClicked: root.resetTimer()
            }
          }

          PanelSeparator { foreground: root.contentForeground }

          // ---- Big time display + status (hidden while editing settings) ----
          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: !root.editing

            Text {
              width: parent.width
              text: Core.FocusState.displayText
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Math.round(Style.font.displayLarge * 1.5)
              font.bold: true
              horizontalAlignment: Text.AlignHCenter
            }

            Text {
              width: parent.width
              text: Core.FocusState.statusText.toUpperCase()
              color: Qt.darker(root.contentForeground, 1.4)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              horizontalAlignment: Text.AlignHCenter
            }
          }

          // ---- Progress bar -------------------------------------------------
          Item {
            width: parent.width
            visible: !root.editing
            implicitHeight: Style.space(7)

            Rectangle {
              anchors.fill: parent
              radius: height / 2
              color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)
            }

            Rectangle {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Core.FocusState.progress <= 0
                ? 0
                : Math.max(height, parent.width * Core.FocusState.progress)
              height: parent.height
              radius: height / 2
              color: Core.FocusState.onBreak ? Core.FocusState.pomodoroBreakColor : Color.accent
              Behavior on width { NumberAnimation { duration: 90 } }
            }
          }

          // ---- Cycle progress dots + summary (read-out; edit under ⚙) --------
          Item {
            width: parent.width
            visible: !root.editing
            implicitHeight: Math.max(cycleDots.implicitHeight, cycleSummary.implicitHeight)

            Row {
              id: cycleDots
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(7)

              Repeater {
                model: Core.FocusState.pomodoroCycles
                Rectangle {
                  required property int index
                  width: Style.space(8)
                  height: width
                  radius: width / 2
                  anchors.verticalCenter: parent.verticalCenter
                  color: index < Core.FocusState.pomodoroCompletedCycles
                    ? Color.accent
                    : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.24)
                }
              }
            }

            Text {
              id: cycleSummary
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: Core.FocusState.pomodoroWorkMinutes + " / "
                + Core.FocusState.pomodoroShortBreakMinutes + " × "
                + Core.FocusState.pomodoroCycles + " · "
                + Core.FocusState.pomodoroLongBreakMinutes + " long"
              color: Qt.darker(root.contentForeground, 1.4)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          PanelSeparator { foreground: root.contentForeground }

          // ---- Focus session (soundtrack + volume + editor) -----------------
          Column {
            width: parent.width
            spacing: Style.space(10)

            Item {
              width: parent.width
              implicitHeight: Math.max(sessionHeader.implicitHeight, gearButton.implicitHeight)

              PanelSectionHeader {
                id: sessionHeader
                text: "FOCUS SESSION"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Button {
                id: gearButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconText: root.editing ? "✓" : "⚙"
                text: root.editing ? "Done" : "Edit"
                fontSize: Style.font.bodySmall
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                bordered: true
                active: root.editing
                onClicked: root.editing = !root.editing
              }
            }

            // ===== Normal view =====
            Column {
              width: parent.width
              spacing: Style.space(10)
              visible: !root.editing

              Row {
                id: soundRow
                width: parent.width
                spacing: Style.space(6)
                enabled: Core.FocusState.focusEffects
                opacity: enabled ? 1 : 0.5

                readonly property var slots: {
                  var a = []
                  for (var i = 0; i < 3; i++)
                    if (Core.FocusState.slotConfigured(i))
                      a.push({ index: i, label: Core.FocusState.slotLabel(i) })
                  return a
                }
                readonly property real cellWidth: slots.length > 0
                  ? (width - spacing * (slots.length - 1)) / slots.length
                  : width

                Repeater {
                  model: soundRow.slots
                  Button {
                    required property var modelData
                    width: soundRow.cellWidth
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
                text: Core.FocusState.focusEffects
                  ? "Volume, sounds & options in ⚙ Edit"
                  : "Focus effects are off — Spotify, Obsidian and blocking won't run"
                color: Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
              }
            }

            // ===== Edit view (settings) — kept compact so it never scrolls ==
            Column {
              width: parent.width
              spacing: Style.space(8)
              visible: root.editing

              PanelSectionHeader {
                text: "SOUNDTRACKS"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
              }

              Repeater {
                model: 3
                Row {
                  id: slotRow
                  required property int index
                  width: parent.width
                  spacing: Style.space(6)

                  TextField {
                    id: labelField
                    width: Style.space(90)
                    text: Core.FocusState.slotLabel(slotRow.index)
                    placeholderText: "Name"
                    foreground: root.contentForeground
                    font.family: root.contentFontFamily
                    onEditingFinished: root.setSlotLabel(slotRow.index, text)
                    Keys.onReturnPressed: { root.setSlotLabel(slotRow.index, text); focus = false }
                    Keys.onEnterPressed: { root.setSlotLabel(slotRow.index, text); focus = false }
                    Keys.onEscapePressed: focus = false
                  }

                  TextField {
                    width: parent.width - labelField.width - parent.spacing
                    text: Core.FocusState.slotUri(slotRow.index)
                    placeholderText: "spotify:playlist:… , share URL, or 'liked'"
                    foreground: root.contentForeground
                    font.family: root.contentFontFamily
                    onEditingFinished: root.setSlotUri(slotRow.index, text)
                    Keys.onReturnPressed: { root.setSlotUri(slotRow.index, text); focus = false }
                    Keys.onEnterPressed: { root.setSlotUri(slotRow.index, text); focus = false }
                    Keys.onEscapePressed: focus = false
                  }
                }
              }

              // ---- Volume + master switch (moved here from the main view) ----
              Item {
                width: parent.width
                implicitHeight: Math.max(volHeader.implicitHeight, volValue.implicitHeight)
                enabled: Core.FocusState.focusEffects
                opacity: enabled ? 1 : 0.5

                PanelSectionHeader {
                  id: volHeader
                  text: "VOLUME"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  id: volValue
                  text: Core.FocusState.spotifyVolume + "%"
                  color: Qt.darker(root.contentForeground, 1.4)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              PanelSlider {
                width: parent.width
                bar: root.bar
                minimum: 0
                maximum: 100
                step: 5
                integer: true
                enabled: Core.FocusState.focusEffects
                opacity: enabled ? 1 : 0.5
                value: Core.FocusState.spotifyVolume
                onMoved: function(v) { Core.FocusState.setSpotifyVolume(v) }
                onReleased: function(v) {
                  Core.FocusState.setSpotifyVolume(v)
                  root.persistSettings({ spotifyVolume: Core.FocusState.spotifyVolume })
                }
              }

              Toggle {
                width: parent.width
                label: "Focus effects"
                description: "Block sites, play Spotify, isolate Obsidian when a session starts"
                checked: Core.FocusState.focusEffects
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.setFocusEffects(!Core.FocusState.focusEffects)
              }

              PanelSectionHeader {
                text: "POMODORO CYCLE"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
              }

              Row {
                width: parent.width
                spacing: Style.space(10)

                CompactField {
                  id: workField
                  width: (parent.width - parent.spacing) / 2
                  fieldWidth: width
                  label: "Focus minutes"
                  from: 1
                  to: 999
                  value: Core.FocusState.pomodoroWorkMinutes
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  enabled: root.canEdit
                  opacity: enabled ? 1 : 0.5
                  onModified: function(value) { root.setPomodoroField("work", value) }
                }

                CompactField {
                  id: shortField
                  width: (parent.width - parent.spacing) / 2
                  fieldWidth: width
                  label: "Short break"
                  from: 1
                  to: 999
                  value: Core.FocusState.pomodoroShortBreakMinutes
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  enabled: root.canEdit
                  opacity: enabled ? 1 : 0.5
                  onModified: function(value) { root.setPomodoroField("short", value) }
                }
              }

              Row {
                width: parent.width
                spacing: Style.space(10)

                CompactField {
                  id: cyclesField
                  width: (parent.width - parent.spacing) / 2
                  fieldWidth: width
                  label: "Focus cycles"
                  from: 1
                  to: 99
                  value: Core.FocusState.pomodoroCycles
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  enabled: root.canEdit
                  opacity: enabled ? 1 : 0.5
                  onModified: function(value) { root.setPomodoroField("cycles", value) }
                }

                CompactField {
                  id: longField
                  width: (parent.width - parent.spacing) / 2
                  fieldWidth: width
                  label: "Long break"
                  from: 1
                  to: 999
                  value: Core.FocusState.pomodoroLongBreakMinutes
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  enabled: root.canEdit
                  opacity: enabled ? 1 : 0.5
                  onModified: function(value) { root.setPomodoroField("long", value) }
                }
              }

              Toggle {
                width: parent.width
                label: "Pomodoro sounds"
                description: "Bell between phases and three bells when the cycle ends"
                checked: Core.FocusState.pomodoroSoundEnabled
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                enabled: root.canEdit
                opacity: enabled ? 1 : 0.5
                onClicked: if (enabled) root.setPomodoroField("sound", !Core.FocusState.pomodoroSoundEnabled)
              }

              PanelSectionHeader {
                text: "BLOCK CATEGORIES"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
              }

              Repeater {
                model: [
                  { key: "social", label: "Social media" },
                  { key: "video", label: "Video streaming" },
                  { key: "shopping", label: "Shopping" },
                  { key: "news", label: "News & forums" },
                  { key: "adult", label: "Adult" }
                ]
                Toggle {
                  required property var modelData
                  width: parent.width
                  label: modelData.label
                  checked: root.categoryChecked(modelData.key)
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.setCategory(modelData.key, !root.categoryChecked(modelData.key))
                }
              }

              PanelSectionHeader {
                text: "EXTRA DOMAINS"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
              }

              TextField {
                width: parent.width
                text: Core.FocusState.extraDomains
                placeholderText: "example.com, other.com"
                foreground: root.contentForeground
                font.family: root.contentFontFamily
                onEditingFinished: root.setExtraDomains(text)
                Keys.onReturnPressed: { root.setExtraDomains(text); focus = false }
                Keys.onEnterPressed: { root.setExtraDomains(text); focus = false }
                Keys.onEscapePressed: focus = false
              }
            }
          }

        }
      }
    }
  }
}
