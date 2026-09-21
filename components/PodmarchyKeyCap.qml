import QtQuick
import qs.Ui
import qs.Commons

// A small keycap badge used for shortcut hints.
Rectangle {
  id: root

  property var ctx
  property string label
  property bool primary: false

  readonly property color fillColor: primary ? ctx.keycapAccentFill : ctx.keycapFill
  readonly property color strokeColor: primary ? ctx.keycapAccentBorder : ctx.keycapBorder
  readonly property color textColor: ctx.keycapText
  readonly property int textSize: ctx.metaFont
  readonly property int capHeight: ctx.metaFont + Style.space(7)

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
    color: root.textColor
    font.family: ctx.fontFamily
    font.pixelSize: root.textSize
    font.weight: root.primary ? Font.DemiBold : Font.Normal
  }
}
