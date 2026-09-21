import QtQuick
import qs.Ui
import qs.Commons

// One shortcut: what it does on the left, its keys right-aligned.
// `keys` lists alternatives; "Ctrl+K" draws as two keys, and alternatives
// are separated by a faint slash.
Item {
  id: root

  property var ctx
  property var keys: []
  property string label
  property bool last: false

  height: Style.space(27)

  Text {
    anchors.left: parent.left
    anchors.right: keyRow.left
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: root.label
    color: Util.alpha(root.ctx.foreground, 0.84)
    elide: Text.ElideRight
    font.family: root.ctx.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Row {
    id: keyRow
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(5)

    Repeater {
      model: root.keys

      delegate: Row {
        id: alternative
        required property string modelData
        required property int index
        spacing: Style.space(3)

        Text {
          visible: alternative.index > 0
          anchors.verticalCenter: parent.verticalCenter
          rightPadding: Style.space(2)
          textFormat: Text.PlainText
          text: "/"
          color: Util.alpha(root.ctx.foreground, 0.28)
          font.family: root.ctx.fontFamily
          font.pixelSize: Style.font.caption
        }

        Repeater {
          model: alternative.modelData.split("+")

          delegate: PodmarchyShortcutKey {
            required property string modelData
            ctx: root.ctx
            label: modelData
          }
        }
      }
    }
  }

  Rectangle {
    visible: !root.last
    anchors.bottom: parent.bottom
    width: parent.width
    height: 1
    color: Util.alpha(root.ctx.foreground, 0.06)
  }
}
