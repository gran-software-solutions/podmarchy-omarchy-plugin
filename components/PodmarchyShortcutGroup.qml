import QtQuick
import qs.Ui
import qs.Commons

// A titled group of shortcut rows.
Column {
  id: root

  property string title
  property var rows: []

  spacing: Style.space(3)

  Text {
    textFormat: Text.PlainText
    text: root.title
    color: selectedText
    font.family: fontFamily
    font.pixelSize: metaFont
    font.letterSpacing: 1.4
    font.weight: Font.DemiBold
    bottomPadding: Style.space(4)
  }

  Repeater {
    model: root.rows
    delegate: PodmarchyShortcutRow {
      required property var modelData
      keys: modelData.keys
      label: modelData.label
    }
  }
}
