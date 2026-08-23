import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui

// Compact labeled integer spin box. Theme-aware via qs.Commons/qs.Ui tokens.
Column {
  id: root

  property string label: ""
  property int value: 0
  property int from: 0
  property int to: 100
  property int stepSize: 1
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.body
  property real fieldWidth: Style.spacing.numberFieldWidth
  property bool hovered: false
  property bool canceling: false
  property alias field: spin

  signal modified(int value)

  function commitText(text) {
    var parsed = parseInt(String(text), 10)
    if (isNaN(parsed)) parsed = root.value
    parsed = Math.max(root.from, Math.min(root.to, parsed))
    root.modified(parsed)
  }

  spacing: Style.spacing.md

  Text {
    visible: root.label !== ""
    text: root.label
    color: Qt.darker(root.foreground, 1.4)
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  QQC.SpinBox {
    id: spin
    width: root.fieldWidth
    implicitHeight: Math.max(Style.spacing.controlHeight, root.fontSize + Style.spacing.controlPaddingY * 2)
    from: root.from
    to: root.to
    stepSize: root.stepSize
    value: root.value
    editable: true
    activeFocusOnTab: true
    font.family: root.fontFamily
    font.pixelSize: root.fontSize

    readonly property var _borderSpec: Border.controlSpec(
      activeFocus ? "focus" : (root.hovered ? "hover-cursor" : "normal"),
      root.foreground,
      root.accent
    )

    leftPadding: Border.left(_borderSpec) + Style.spacing.controlPaddingX
    rightPadding: Border.right(_borderSpec) + Style.spacing.controlPaddingX
    topPadding: Border.top(_borderSpec)
    bottomPadding: Border.bottom(_borderSpec)

    onValueModified: root.modified(value)

    background: BorderSurface {
      color: Style.controlFill(spin.activeFocus, root.hovered, root.foreground, root.accent)
      borderSpec: spin._borderSpec
      radius: Style.cornerRadius

      HoverHandler {
        onHoveredChanged: root.hovered = hovered
      }
    }

    contentItem: TextInput {
      id: editor
      text: spin.displayText
      font: spin.font
      color: root.foreground
      selectionColor: Style.selectionFillFor(root.foreground, root.accent)
      selectedTextColor: root.foreground
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      readOnly: !spin.editable
      validator: spin.validator
      inputMethodHints: Qt.ImhFormattedNumbersOnly
      selectByMouse: true

      onEditingFinished: {
        if (!root.canceling) root.commitText(text)
        root.canceling = false
      }

      Keys.onEscapePressed: {
        root.canceling = true
        focus = false
      }
    }
  }
}
