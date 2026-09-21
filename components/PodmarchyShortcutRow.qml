import QtQuick
import qs.Ui
import qs.Commons

// One shortcut hint: one or more keycaps followed by a description.
Row {
  id: root

  property var ctx
  property var keys: []
  property string label

  spacing: Style.space(12)

  Row {
    width: Style.space(104)
    height: ctx.referenceRowHeight
    spacing: Style.space(3)

    Repeater {
      model: root.keys
      delegate: PodmarchyKeyCap {
        required property string modelData
        ctx: root.ctx
        label: modelData
      }
    }
  }

  Text {
    textFormat: Text.PlainText
    text: root.label
    color: ctx.hintLabel
    height: ctx.referenceRowHeight
    verticalAlignment: Text.AlignVCenter
    font.family: ctx.fontFamily
    font.pixelSize: ctx.metaFont
    anchors.verticalCenter: parent.verticalCenter
  }
}
