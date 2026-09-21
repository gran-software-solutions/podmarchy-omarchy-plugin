import QtQuick
import qs.Commons
import qs.Ui

// Actions overlay: a searchable menu of commands for the current row.
Item {
  id: overlay

  property var root
  property var pointerGate

  anchors.fill: parent

  function scrollTo(index) {
    if (actionsList.count > 0) actionsList.positionViewAtIndex(index, ListView.Contain)
  }

  Rectangle {
    anchors.fill: parent
    visible: overlay.root.actionsOpen
    radius: overlay.root.cornerRadius
    color: Util.alpha(overlay.root.background, 0.35)
  }

  BorderSurface {
    visible: overlay.root.actionsOpen
    anchors.centerIn: parent
    width: Math.min(Style.space(560), overlay.parent.width - Style.space(40))
    height: Math.min(Style.space(520), overlay.parent.height - Style.space(40))
    radius: overlay.root.cornerRadius
    color: overlay.root.background
    borderSpec: overlay.root.borderSpec
    padding: overlay.root.contentMargin

    MouseArea { anchors.fill: parent; onClicked: {} }

    Column {
      anchors.fill: parent
      anchors.topMargin: parent.contentTopInset
      anchors.rightMargin: parent.contentRightInset
      anchors.bottomMargin: parent.contentBottomInset
      anchors.leftMargin: parent.contentLeftInset
      spacing: overlay.root.contentSpacing

      Text {
        id: actionsHeading
        textFormat: Text.PlainText
        text: "Actions"
        color: overlay.root.foreground
        font.family: overlay.root.fontFamily
        font.pixelSize: Style.font.heading
      }

      Rectangle {
        id: actionSearchBox
        width: parent.width
        height: Style.space(42)
        radius: overlay.root.cornerRadius
        color: Util.alpha(overlay.root.border, 0.08)

        Text {
          textFormat: Text.PlainText
          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          text: overlay.root.actionFilter || "Search actions…"
          color: overlay.root.foreground
          opacity: overlay.root.actionFilter ? 1 : 0.5
          font.family: overlay.root.fontFamily
          font.pixelSize: Style.font.title
        }
      }

      ListView {
        id: actionsList
        width: parent.width
        height: parent.height - actionsHeading.height - actionSearchBox.height - overlay.root.contentSpacing * 2
        model: overlay.root.actionsModel
        clip: true
        spacing: Style.space(4)
        boundsBehavior: Flickable.StopAtBounds
        reuseItems: true

        delegate: Rectangle {
          id: actionRow
          required property int index
          required property string actionId
          required property string label
          required property string hint

          readonly property bool hasCursor: index === overlay.root.actionIndex

          width: ListView.view.width
          height: Style.space(46)
          radius: overlay.root.cornerRadius
          color: hasCursor ? overlay.root.selectedBackground : "transparent"

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(22)
            anchors.right: actionHint.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: actionRow.label
            color: actionRow.hasCursor ? overlay.root.selectedText : (actionRow.actionId === "stop" ? "#d04860" : overlay.root.foreground)
            font.family: overlay.root.fontFamily
            font.pixelSize: Style.font.title
            elide: Text.ElideRight
          }

          Text {
            id: actionHint
            anchors.right: parent.right
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: actionRow.hint
            color: actionRow.hasCursor ? overlay.root.selectedText : overlay.root.foreground
            opacity: 0.5
            font.family: overlay.root.fontFamily
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: function(mouse) {
              if (!overlay.pointerGate || !overlay.pointerGate.moved(actionRow, mouse)) return
              overlay.root.actionIndex = actionRow.index
            }
            onClicked: overlay.root.runActionIndex(actionRow.index)
          }
        }
      }
    }
  }
}
