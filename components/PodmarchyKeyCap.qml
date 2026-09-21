import QtQuick
import qs.Ui
import qs.Commons

// A small keycap badge used for shortcut hints.
Rectangle {
  id: root

  property string label
  property bool primary: false
  property color fillColor: primary ? keycapAccentFill : keycapFill
  property color strokeColor: primary ? keycapAccentBorder : keycapBorder
  property color textColor: keycapText
  property int textSize: metaFont
  property int capHeight: root.metaFont + Style.space(7)

  width: keyCapLabel.implicitWidth + Style.space(9)
  height: capHeight
  radius: 5
  color: fillColor
  border.color: strokeColor
  border.width: 1

  Text {
    id: keyCapLabel
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: root.label
    color: textColor
    font.family: fontFamily
    font.pixelSize: textSize
    font.weight: root.primary ? Font.DemiBold : Font.Normal
  }
}
