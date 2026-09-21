import QtQuick
import qs.Ui
import qs.Commons

// One shortcut hint: one or more keycaps followed by a description.
Row {
  id: root

  property var keys: []
  property string label

  spacing: Style.space(12)

  Row {
    width: Style.space(104)
    height: referenceRowHeight
    spacing: Style.space(3)

    Repeater {
      model: root.keys
      delegate: PodmarchyKeyCap { required property string modelData; label: modelData }
    }
  }

  Text {
    textFormat: Text.PlainText
    text: root.label
    color: hintLabel
    height: referenceRowHeight
    verticalAlignment: Text.AlignVCenter
    font.family: fontFamily
    font.pixelSize: metaFont
    anchors.verticalCenter: parent.verticalCenter
  }
}
