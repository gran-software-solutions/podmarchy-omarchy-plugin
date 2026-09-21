import QtQuick
import qs.Ui
import qs.Commons

// One physical-looking key for the shortcuts reference: a face over a
// slightly darker base, so it reads as a key and not as a tag.
Item {
  id: root

  property var ctx
  property string label

  readonly property int faceHeight: Style.space(19)
  readonly property int keyRadius: Style.space(5)

  implicitWidth: Math.max(faceHeight, keyText.implicitWidth + Style.space(12))
  implicitHeight: faceHeight + Style.space(2)
  width: implicitWidth
  height: implicitHeight

  // Base: peeks out below the face.
  Rectangle {
    anchors.fill: parent
    radius: root.keyRadius
    color: Util.alpha(root.ctx.foreground, root.ctx.lightTheme ? 0.16 : 0.30)
  }

  Rectangle {
    width: parent.width
    height: root.faceHeight
    radius: root.keyRadius
    color: root.ctx.lightTheme ? "#ffffff" : Util.alpha(root.ctx.foreground, 0.09)
    border.width: 1
    border.color: Util.alpha(root.ctx.foreground, 0.16)

    Text {
      id: keyText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: root.label
      color: root.ctx.keycapText
      font.family: root.ctx.fontFamily
      font.pixelSize: Style.font.caption
      font.weight: Font.Medium
    }
  }
}
