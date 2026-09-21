import QtQuick
import qs.Commons
import qs.Ui

// Keycap-styled text field, as in Yank's retention setting.
Rectangle {
  id: field

  property alias input: fieldInput
  property alias text: fieldInput.text
  property string placeholder: ""
  property bool secret: false

  signal edited(string value)
  signal submitted()
  signal focusLost()

  height: Style.space(26)
  radius: Style.space(5)
  color: keycapFill
  border.width: fieldInput.activeFocus ? 2 : 1
  border.color: fieldInput.activeFocus ? Util.alpha(selectedText, 0.6) : Util.alpha(foreground, 0.20)

  TextInput {
    id: fieldInput
    anchors.fill: parent
    anchors.leftMargin: Style.space(8)
    anchors.rightMargin: Style.space(8)
    verticalAlignment: TextInput.AlignVCenter
    color: foreground
    selectionColor: Util.alpha(selectedText, 0.35)
    selectedTextColor: foreground
    font.family: fontFamily
    font.pixelSize: metaFont
    echoMode: field.secret ? TextInput.Password : TextInput.Normal
    activeFocusOnPress: true
    clip: true
    onTextEdited: field.edited(text)
    onActiveFocusChanged: if (!activeFocus) field.focusLost()
    Keys.onReturnPressed: field.submitted()
    Keys.onEnterPressed: field.submitted()
  }

  Text {
    anchors.left: parent.left
    anchors.leftMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    visible: fieldInput.text.length === 0
    textFormat: Text.PlainText
    text: field.placeholder
    color: foreground
    opacity: 0.35
    font.family: fontFamily
    font.pixelSize: metaFont
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.IBeamCursor
    onClicked: fieldInput.forceActiveFocus()
  }
}
