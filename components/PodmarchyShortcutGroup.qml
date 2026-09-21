import QtQuick
import qs.Ui
import qs.Commons

// A titled card of shortcut rows.
Rectangle {
  id: root

  property var ctx
  property string title
  property string glyph
  property var rows: []

  readonly property int pad: Style.space(12)

  height: body.implicitHeight + pad + Style.space(6)
  radius: Style.space(8)
  color: Util.alpha(ctx.foreground, 0.03)
  border.width: 1
  border.color: Util.alpha(ctx.foreground, 0.08)

  Column {
    id: body
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.leftMargin: root.pad
    anchors.rightMargin: root.pad
    anchors.topMargin: root.pad

    Row {
      spacing: Style.space(7)
      bottomPadding: Style.space(5)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.glyph
        color: Color.accent
        font.family: root.ctx.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.title.toUpperCase()
        color: root.ctx.hintLabel
        font.family: root.ctx.fontFamily
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1.2
        font.weight: Font.DemiBold
      }
    }

    Repeater {
      model: root.rows

      delegate: PodmarchyShortcutRow {
        required property var modelData
        required property int index
        width: body.width
        ctx: root.ctx
        keys: modelData.keys
        label: modelData.label
        last: index === root.rows.length - 1
      }
    }
  }
}
