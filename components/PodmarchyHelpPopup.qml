import QtQuick
import qs.Commons
import qs.Ui

// Help popup: shortcuts and settings.
Item {
  id: popup

  property var root
  property var keyCatcher
  property bool saving: false

  anchors.fill: parent

  // Backdrop.
  Rectangle {
    anchors.fill: parent
    radius: popup.root.cornerRadius
    color: Util.alpha(popup.root.foreground, 0.28)
    visible: opacity > 0.01
    opacity: popup.root.helpOpen ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

    MouseArea {
      anchors.fill: parent
      onClicked: {
        popup.root.helpOpen = false
        popup.keyCatcher.forceActiveFocus()
      }
    }
  }

  BorderSurface {
    id: helpCard
    anchors.centerIn: parent
    width: Math.min(popup.root.helpPopupWidth, popup.parent.width - Style.space(60))
    height: Math.min(popup.root.helpPopupHeight, popup.parent.height - Style.space(60))
    radius: popup.root.cornerRadius
    color: Util.alpha(popup.root.background, 1)
    borderSpec: popup.root.borderSpec
    padding: popup.root.contentMargin
    visible: opacity > 0.01
    opacity: popup.root.helpOpen ? 1 : 0
    scale: popup.root.helpOpen ? 1 : 0.99
    Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    MouseArea { anchors.fill: parent; onClicked: {} }

    Column {
      anchors.fill: parent
      anchors.topMargin: parent.contentTopInset + Style.space(4)
      anchors.rightMargin: parent.contentRightInset + Style.space(2)
      anchors.bottomMargin: parent.contentBottomInset
      anchors.leftMargin: parent.contentLeftInset + Style.space(2)
      spacing: popup.root.contentSpacing

      // Page switcher.
      Row {
        spacing: Style.space(4)

        Item {
          id: tabShortcuts
          width: tabShortcutsLabel.implicitWidth + Style.space(18)
          height: Style.space(24)
          readonly property bool active: popup.root.helpTab === "shortcuts"

          Rectangle {
            anchors.fill: parent
            radius: Style.space(5)
            color: tabShortcuts.active ? Util.alpha(popup.root.selectedText, 0.16)
                                       : (tabShortcutsArea.containsMouse ? Util.alpha(popup.root.foreground, 0.06) : "transparent")
            border.width: 1
            border.color: tabShortcuts.active ? Util.alpha(popup.root.selectedText, 0.45) : Util.alpha(popup.root.foreground, 0.16)
          }

          Text {
            id: tabShortcutsLabel
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: "SHORTCUTS"
            color: tabShortcuts.active ? popup.root.selectedText : popup.root.foreground
            font.family: popup.root.fontFamily
            font.pixelSize: popup.root.metaFont
            font.letterSpacing: 1.0
            font.weight: tabShortcuts.active ? Font.DemiBold : Font.Normal
          }

          MouseArea {
            id: tabShortcutsArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              popup.root.helpTab = "shortcuts"
              popup.keyCatcher.forceActiveFocus()
            }
          }

          PanelToolTip { visible: tabShortcutsArea.containsMouse; text: "All keyboard shortcuts" }
        }

        Item {
          id: tabSettings
          width: tabSettingsLabel.implicitWidth + Style.space(18)
          height: Style.space(24)
          readonly property bool active: popup.root.helpTab === "settings"

          Rectangle {
            anchors.fill: parent
            radius: Style.space(5)
            color: tabSettings.active ? Util.alpha(popup.root.selectedText, 0.16)
                                      : (tabSettingsArea.containsMouse ? Util.alpha(popup.root.foreground, 0.06) : "transparent")
            border.width: 1
            border.color: tabSettings.active ? Util.alpha(popup.root.selectedText, 0.45) : Util.alpha(popup.root.foreground, 0.16)
          }

          Text {
            id: tabSettingsLabel
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: "SETTINGS"
            color: tabSettings.active ? popup.root.selectedText : popup.root.foreground
            font.family: popup.root.fontFamily
            font.pixelSize: popup.root.metaFont
            font.letterSpacing: 1.0
            font.weight: tabSettings.active ? Font.DemiBold : Font.Normal
          }

          MouseArea {
            id: tabSettingsArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: popup.root.helpTab = "settings"
          }

          PanelToolTip { visible: tabSettingsArea.containsMouse; text: "Podcast Index key and trending language" }
        }
      }

      // ---- page: settings ----
      Column {
        visible: popup.root.helpTab === "settings"
        width: parent.width
        spacing: Style.space(8)

        onVisibleChanged: if (visible && popup.root.helpOpen) Qt.callLater(function() {
          if (!popup.root.apiConfigured) keyField.input.forceActiveFocus()
        })

        Row {
          spacing: Style.space(8)

          Text {
            textFormat: Text.PlainText
            text: "PODCAST INDEX"
            color: popup.root.hintLabel
            font.family: popup.root.fontFamily
            font.pixelSize: popup.root.metaFont
            font.letterSpacing: 1.0
            font.weight: Font.DemiBold
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            textFormat: Text.PlainText
            text: popup.root.apiConfigured ? "\u{F012C} connected" : "not connected"
            color: popup.root.apiConfigured ? Color.accent : popup.root.hintLabel
            font.family: popup.root.fontFamily
            font.pixelSize: popup.root.metaFont
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Row {
          spacing: Style.space(7)

          PodmarchySettingsField {
            id: keyField
            width: Style.space(220)
            placeholder: popup.root.apiConfigured ? "New API key" : "API key"
            text: popup.root.keyDraft || popup.root.savedKeyMask
            onEdited: function(value) { popup.root.keyDraft = value }
            onSubmitted: secretField.input.forceActiveFocus()
            Keys.onEscapePressed: { popup.root.helpOpen = false; popup.keyCatcher.forceActiveFocus() }
          }

          PodmarchySettingsField {
            id: secretField
            width: Style.space(300)
            placeholder: popup.root.apiConfigured ? "New API secret" : "API secret"
            secret: true
            text: popup.root.secretDraft || popup.root.savedSecretMask
            onEdited: function(value) { popup.root.secretDraft = value }
            onSubmitted: popup.root.saveCredentials()
            Keys.onEscapePressed: { popup.root.helpOpen = false; popup.keyCatcher.forceActiveFocus() }
          }

          Rectangle {
            id: saveButton
            width: Math.max(Style.space(42), saveLabel.implicitWidth + Style.space(18))
            height: Style.space(26)
            radius: Style.space(5)
            readonly property bool ready: popup.root.keyDraft.trim() !== "" && popup.root.secretDraft.trim() !== ""
            color: ready ? popup.root.keycapAccentFill : popup.root.keycapFill
            border.width: 1
            border.color: ready ? popup.root.keycapAccentBorder : popup.root.keycapBorder
            opacity: ready ? 1 : 0.6

            Text {
              id: saveLabel
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: popup.saving ? "Saving…" : "Save"
              color: popup.root.keycapText
              font.family: popup.root.fontFamily
              font.pixelSize: popup.root.metaFont
              font.weight: Font.DemiBold
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
            }

            MouseArea {
              id: saveArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: if (saveButton.ready) popup.root.saveCredentials()
            }

            PanelToolTip {
              visible: saveArea.containsMouse
              text: saveButton.ready ? "Save the key and secret on this computer" : "Paste both the key and the secret first"
            }
          }
        }

        Row {
          spacing: Style.space(4)

          Text {
            textFormat: Text.PlainText
            text: popup.root.settingsMessage || "Free key, no card: sign up at"
            color: popup.root.settingsError ? "#d04860" : popup.root.hintLabel
            font.family: popup.root.fontFamily
            font.pixelSize: popup.root.metaFont
          }

          Text {
            visible: !popup.root.settingsMessage
            textFormat: Text.PlainText
            text: "api.podcastindex.org"
            color: Color.accent
            font.family: popup.root.fontFamily
            font.pixelSize: popup.root.metaFont
            font.underline: signupArea.containsMouse

            MouseArea {
              id: signupArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: Quickshell.execDetached(["xdg-open", "https://api.podcastindex.org/signup"])
            }

            PanelToolTip { visible: signupArea.containsMouse; text: "Open the Podcast Index sign-up page in your browser" }
          }

          Text {
            visible: !popup.root.settingsMessage
            textFormat: Text.PlainText
            text: "· stored only on this machine"
            color: popup.root.hintLabel
            font.family: popup.root.fontFamily
            font.pixelSize: popup.root.metaFont
          }
        }

        Item { width: 1; height: Style.space(4) }

        Text {
          textFormat: Text.PlainText
          text: "TRENDING LANGUAGE"
          color: popup.root.hintLabel
          font.family: popup.root.fontFamily
          font.pixelSize: popup.root.metaFont
          font.letterSpacing: 1.0
          font.weight: Font.DemiBold
        }

        Row {
          spacing: Style.space(7)

          PodmarchySettingsField {
            id: languageField
            width: Style.space(90)
            placeholder: "any"
            text: popup.root.language
            onSubmitted: popup.root.saveLanguage(text)
            onFocusLost: popup.root.saveLanguage(text)
            Keys.onEscapePressed: { popup.root.helpOpen = false; popup.keyCatcher.forceActiveFocus() }
          }

          Text {
            textFormat: Text.PlainText
            text: "Language code such as en or de, several with commas. Empty shows every language."
            color: popup.root.hintLabel
            font.family: popup.root.fontFamily
            font.pixelSize: popup.root.metaFont
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }

      // ---- page: shortcuts ----
      Row {
        visible: popup.root.helpTab === "shortcuts"
        spacing: Style.space(20)

        PodmarchyShortcutGroup {
          ctx: popup.root
          title: "NAVIGATE"
          rows: [
            { keys: ["↑", "↓"], label: "move" },
            { keys: ["Enter"], label: "open / play" },
            { keys: ["Tab"], label: "switch view" },
            { keys: ["Esc"], label: "back, then close" }
          ]
        }

        PodmarchyShortcutGroup {
          ctx: popup.root
          title: "PLAYBACK"
          rows: [
            { keys: ["Space"], label: "pause / resume" },
            { keys: ["k"], label: "pause / resume" },
            { keys: ["j", "l"], label: "back 10 s / ahead 30 s" },
            { keys: ["←", "→"], label: "back 15 s / ahead 30 s" },
            { keys: ["q"], label: "stop" }
          ]
        }

        PodmarchyShortcutGroup {
          ctx: popup.root
          title: "LIBRARY"
          rows: [
            { keys: ["s"], label: "subscribe / unsubscribe" },
            { keys: ["d"], label: "remove from view" },
            { keys: ["Backspace"], label: "leave a show" }
          ]
        }

        PodmarchyShortcutGroup {
          ctx: popup.root
          title: "PANEL"
          rows: [
            { keys: ["/"], label: "search" },
            { keys: ["?"], label: "this reference" },
            { keys: [","], label: "settings" },
            { keys: ["."], label: "actions menu" },
            { keys: ["o"], label: "detail pane" }
          ]
        }
      }
    }
  }
}
