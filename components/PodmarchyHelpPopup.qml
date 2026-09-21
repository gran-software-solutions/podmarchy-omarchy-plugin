import QtQuick
import qs.Commons
import qs.Ui

// Help popup: keyboard shortcuts and settings, behind one segmented switch.
Item {
  id: popup

  property var root
  property var keyCatcher

  readonly property color hairline: Util.alpha(root.foreground, 0.08)
  readonly property color sectionFill: Util.alpha(root.foreground, 0.03)
  readonly property color bodyText: Util.alpha(root.foreground, 0.84)
  readonly property color errorColor: "#d04860"
  readonly property int sectionRadius: Style.space(8)
  readonly property int sectionPad: Style.space(14)
  readonly property int controlHeight: Style.space(30)

  readonly property var tabs: [
    { id: "shortcuts", label: "Shortcuts", glyph: "\u{F030C}", tip: "Every keyboard shortcut  (?)" },
    { id: "settings", label: "Settings", glyph: "\u{F0493}", tip: "Podcast Index key and trending language  (,)" }
  ]

  // Two columns, balanced by row count.
  readonly property var shortcutColumns: [
    [
      { title: "Navigate", glyph: "\u{F0041}", rows: [
        { keys: ["↑", "Ctrl+K"], label: "Move up" },
        { keys: ["↓", "Ctrl+J"], label: "Move down" },
        { keys: ["Enter"], label: "Open show · play episode" },
        { keys: ["Tab", "Ctrl+L"], label: "Next view" },
        { keys: ["Shift+Tab", "Ctrl+H"], label: "Previous view" },
        { keys: ["1", "2", "3"], label: "Library · Discover · Continue" },
        { keys: ["Esc"], label: "Back, then close" }
      ] },
      { title: "Library", glyph: "\u{F02D1}", rows: [
        { keys: ["s"], label: "Subscribe / unsubscribe" },
        { keys: ["d", "Delete"], label: "Unsubscribe · forget progress" },
        { keys: ["Backspace"], label: "Leave a show" }
      ] }
    ],
    [
      { title: "Playback", glyph: "\u{F040A}", rows: [
        { keys: ["Space", "k"], label: "Play / pause" },
        { keys: ["Shift+Enter"], label: "Play from the start" },
        { keys: ["j"], label: "Back 10 seconds" },
        { keys: ["←"], label: "Back 15 seconds" },
        { keys: ["l", "→"], label: "Ahead 30 seconds" },
        { keys: ["q"], label: "Stop" }
      ] },
      { title: "Panel", glyph: "\u{F056E}", rows: [
        { keys: ["/"], label: "Search" },
        { keys: ["."], label: "Actions menu" },
        { keys: ["o"], label: "Detail pane" },
        { keys: [","], label: "Settings" },
        { keys: ["?"], label: "This reference" }
      ] }
    ]
  ]

  readonly property var languages: [
    { code: "en", label: "English" },
    { code: "de", label: "Deutsch" },
    { code: "fr", label: "Français" },
    { code: "es", label: "Español" },
    { code: "", label: "Any language" }
  ]

  readonly property bool keyReady: root.keyDraft.trim() !== "" && root.secretDraft.trim() !== ""

  function close() {
    popup.root.helpOpen = false
    popup.keyCatcher.forceActiveFocus()
  }

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
      onClicked: popup.close()
    }
  }

  BorderSurface {
    id: helpCard
    anchors.centerIn: parent
    width: Math.min(popup.root.helpPopupWidth, popup.parent.width - Style.space(48))
    height: Math.min(content.implicitHeight + contentTopInset + contentBottomInset + Style.space(8),
                     popup.parent.height - Style.space(48))
    radius: popup.root.cornerRadius
    color: Util.alpha(popup.root.background, 1)
    borderSpec: popup.root.borderSpec
    padding: Style.space(18)
    clip: true
    visible: opacity > 0.01
    opacity: popup.root.helpOpen ? 1 : 0
    scale: popup.root.helpOpen ? 1 : 0.985
    Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

    MouseArea { anchors.fill: parent; onClicked: {} }

    Column {
      id: content
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: parent.contentTopInset + Style.space(4)
      anchors.leftMargin: parent.contentLeftInset
      anchors.rightMargin: parent.contentRightInset
      spacing: Style.space(16)

      // ---- header: badge, title, tab switch, close ----
      Item {
        width: parent.width
        height: Style.space(38)

        Row {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(12)

          Rectangle {
            width: Style.space(38)
            height: Style.space(38)
            radius: Style.space(9)
            color: Util.alpha(Color.accent, 0.12)
            border.width: 1
            border.color: Util.alpha(Color.accent, 0.22)

            Text {
              anchors.centerIn: parent
              text: popup.root.helpTab === "settings" ? "\u{F0493}" : "\u{F030C}"
              color: Color.accent
              font.family: popup.root.fontFamily
              font.pixelSize: Style.font.iconLarge
            }
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(3)

            Text {
              textFormat: Text.PlainText
              text: popup.root.helpTab === "settings" ? "Settings" : "Keyboard shortcuts"
              color: popup.root.foreground
              font.family: popup.root.fontFamily
              font.pixelSize: Style.font.heading
              font.weight: Font.DemiBold
            }

            Text {
              textFormat: Text.PlainText
              text: popup.root.helpTab === "settings"
                    ? "Saved on this machine, applied right away."
                    : "Everything in Podmarchy works without a mouse."
              color: popup.root.hintLabel
              font.family: popup.root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)

          // Same segmented control as the panel's view switch.
          Rectangle {
            height: popup.controlHeight + Style.space(4)
            width: tabRow.implicitWidth + Style.space(6)
            radius: Style.space(8)
            color: Util.alpha(popup.root.foreground, 0.05)
            border.width: 1
            border.color: Util.alpha(popup.root.foreground, 0.10)

            Row {
              id: tabRow
              anchors.centerIn: parent
              spacing: Style.space(2)

              Repeater {
                model: popup.tabs

                delegate: Rectangle {
                  id: tab
                  required property var modelData
                  readonly property bool active: popup.root.helpTab === modelData.id
                  readonly property bool hovered: tabArea.containsMouse

                  height: popup.controlHeight - Style.space(2)
                  width: tabInner.implicitWidth + Style.space(22)
                  radius: Style.space(6)
                  color: active ? popup.root.background : (hovered ? Util.alpha(popup.root.foreground, 0.06) : "transparent")
                  border.width: active ? 1 : 0
                  border.color: Util.alpha(popup.root.foreground, 0.12)
                  Behavior on color { ColorAnimation { duration: 110 } }

                  Row {
                    id: tabInner
                    anchors.centerIn: parent
                    spacing: Style.space(6)

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: tab.modelData.glyph
                      color: tab.active ? Color.accent : popup.root.foreground
                      opacity: tab.active ? 1 : 0.5
                      font.family: popup.root.fontFamily
                      font.pixelSize: Style.font.body
                    }

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      textFormat: Text.PlainText
                      text: tab.modelData.label
                      color: popup.root.foreground
                      opacity: tab.active ? 1 : (tab.hovered ? 0.8 : 0.5)
                      font.family: popup.root.fontFamily
                      font.pixelSize: Style.font.body
                      font.weight: tab.active ? Font.DemiBold : Font.Normal
                    }
                  }

                  MouseArea {
                    id: tabArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      popup.root.helpTab = tab.modelData.id
                      popup.root.settingsMessage = ""
                      if (tab.modelData.id === "shortcuts") popup.keyCatcher.forceActiveFocus()
                    }
                  }

                  PanelToolTip { visible: tabArea.containsMouse; text: tab.modelData.tip }
                }
              }
            }
          }

          Rectangle {
            id: closeButton
            anchors.verticalCenter: parent.verticalCenter
            width: popup.controlHeight
            height: popup.controlHeight
            radius: Style.space(6)
            color: closeArea.containsMouse ? Util.alpha(popup.root.foreground, 0.07) : "transparent"

            Text {
              anchors.centerIn: parent
              text: "\u{F0156}"
              color: popup.root.foreground
              opacity: closeArea.containsMouse ? 0.9 : 0.5
              font.family: popup.root.fontFamily
              font.pixelSize: Style.font.title
            }

            MouseArea {
              id: closeArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: popup.close()
            }

            PanelToolTip { visible: closeArea.containsMouse; text: "Close  (Esc)" }
          }
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: popup.hairline
      }

      // ---- page: shortcuts ----
      Row {
        id: shortcutsPage
        visible: popup.root.helpTab === "shortcuts"
        width: parent.width
        spacing: Style.space(14)

        Repeater {
          model: popup.shortcutColumns

          delegate: Column {
            id: shortcutColumn
            required property var modelData
            width: (shortcutsPage.width - shortcutsPage.spacing) / 2
            spacing: Style.space(14)

            Repeater {
              model: shortcutColumn.modelData

              delegate: PodmarchyShortcutGroup {
                required property var modelData
                width: shortcutColumn.width
                ctx: popup.root
                title: modelData.title
                glyph: modelData.glyph
                rows: modelData.rows
              }
            }
          }
        }
      }

      // ---- page: settings ----
      Column {
        visible: popup.root.helpTab === "settings"
        width: parent.width
        spacing: Style.space(14)

        onVisibleChanged: if (visible && popup.root.helpOpen) Qt.callLater(function() {
          if (!popup.root.apiConfigured) keyField.input.forceActiveFocus()
        })

        // -- Podcast Index credentials --
        Rectangle {
          width: parent.width
          height: apiSection.implicitHeight + popup.sectionPad * 2
          radius: popup.sectionRadius
          color: popup.sectionFill
          border.width: 1
          border.color: popup.hairline

          Column {
            id: apiSection
            anchors.fill: parent
            anchors.margins: popup.sectionPad
            spacing: Style.space(12)

            Item {
              width: parent.width
              height: Style.space(24)

              Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(8)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "\u{F0306}"
                  color: Color.accent
                  font.family: popup.root.fontFamily
                  font.pixelSize: Style.font.title
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: "Podcast Index"
                  color: popup.root.foreground
                  font.family: popup.root.fontFamily
                  font.pixelSize: Style.font.subtitle
                  font.weight: Font.DemiBold
                }
              }

              // Connection status pill.
              Rectangle {
                readonly property color tone: popup.root.apiConfigured ? Color.accent : popup.errorColor
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(22)
                width: statusRow.implicitWidth + Style.space(18)
                radius: height / 2
                color: Util.alpha(tone, 0.10)
                border.width: 1
                border.color: Util.alpha(tone, 0.28)

                Row {
                  id: statusRow
                  anchors.centerIn: parent
                  spacing: Style.space(6)

                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(6)
                    height: width
                    radius: width / 2
                    color: parent.parent.tone
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: popup.root.apiConfigured ? "Connected" : "Not connected"
                    color: parent.parent.tone
                    font.family: popup.root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.weight: Font.DemiBold
                  }
                }
              }
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: "Search, trending and episode lists come from Podcast Index. Their API key and secret are free."
              color: popup.root.hintLabel
              font.family: popup.root.fontFamily
              font.pixelSize: Style.font.bodySmall
              lineHeight: 1.15
            }

            Row {
              id: credentialRow
              width: parent.width
              spacing: Style.space(10)

              readonly property real fieldWidth: (width - saveButton.width - spacing * 2) / 2

              Column {
                spacing: Style.space(6)

                Text {
                  textFormat: Text.PlainText
                  text: "API KEY"
                  color: popup.root.hintLabel
                  font.family: popup.root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1.0
                  font.weight: Font.DemiBold
                }

                PodmarchySettingsField {
                  id: keyField
                  width: credentialRow.fieldWidth
                  height: popup.controlHeight
                  placeholder: popup.root.savedKeyMask || "Paste your API key"
                  text: popup.root.keyDraft
                  onEdited: function(value) { popup.root.keyDraft = value }
                  onSubmitted: secretField.input.forceActiveFocus()
                  Keys.onEscapePressed: popup.close()
                }
              }

              Column {
                spacing: Style.space(6)

                Text {
                  textFormat: Text.PlainText
                  text: "API SECRET"
                  color: popup.root.hintLabel
                  font.family: popup.root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1.0
                  font.weight: Font.DemiBold
                }

                PodmarchySettingsField {
                  id: secretField
                  width: credentialRow.fieldWidth
                  height: popup.controlHeight
                  placeholder: popup.root.savedSecretMask || "Paste your API secret"
                  secret: true
                  text: popup.root.secretDraft
                  onEdited: function(value) { popup.root.secretDraft = value }
                  onSubmitted: if (popup.keyReady) popup.root.saveCredentials()
                  Keys.onEscapePressed: popup.close()
                }
              }

              Rectangle {
                id: saveButton
                anchors.bottom: parent.bottom
                width: Math.max(Style.space(84), saveLabel.implicitWidth + Style.space(28))
                height: popup.controlHeight
                radius: Style.space(6)
                color: popup.keyReady
                       ? (saveArea.containsMouse ? Qt.darker(Color.accent, 1.08) : Color.accent)
                       : Util.alpha(popup.root.foreground, 0.06)
                border.width: popup.keyReady ? 0 : 1
                border.color: Util.alpha(popup.root.foreground, 0.10)
                Behavior on color { ColorAnimation { duration: 110 } }

                Text {
                  id: saveLabel
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: popup.root.savingCredentials ? "Saving…" : (popup.root.apiConfigured ? "Update" : "Connect")
                  color: popup.keyReady ? popup.root.background : Util.alpha(popup.root.foreground, 0.4)
                  font.family: popup.root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.weight: Font.DemiBold
                }

                MouseArea {
                  id: saveArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: popup.keyReady ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: if (popup.keyReady) popup.root.saveCredentials()
                }

                PanelToolTip {
                  visible: saveArea.containsMouse
                  text: popup.keyReady ? "Save the key and secret on this computer" : "Paste both the key and the secret first"
                }
              }
            }

            Item {
              width: parent.width
              height: Style.space(18)

              Text {
                anchors.left: parent.left
                anchors.right: signupLink.left
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: popup.root.settingsMessage || "Stored only on this machine, and sent only to Podcast Index."
                color: popup.root.settingsError ? popup.errorColor
                       : (popup.root.settingsMessage ? Color.accent : popup.root.hintLabel)
                font.family: popup.root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Row {
                id: signupLink
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: "Get a free key"
                  color: Color.accent
                  font.family: popup.root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.weight: Font.DemiBold
                  font.underline: signupArea.containsMouse
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "\u{F03CC}"
                  color: Color.accent
                  font.family: popup.root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              MouseArea {
                id: signupArea
                anchors.fill: signupLink
                anchors.margins: -Style.space(4)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.execDetached(["xdg-open", "https://api.podcastindex.org/signup"])
              }

              PanelToolTip { visible: signupArea.containsMouse; text: "Open api.podcastindex.org/signup in your browser" }
            }
          }
        }

        // -- Trending language --
        Rectangle {
          width: parent.width
          height: languageSection.implicitHeight + popup.sectionPad * 2
          radius: popup.sectionRadius
          color: popup.sectionFill
          border.width: 1
          border.color: popup.hairline

          Column {
            id: languageSection
            anchors.fill: parent
            anchors.margins: popup.sectionPad
            spacing: Style.space(12)

            Row {
              spacing: Style.space(8)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "\u{F05CA}"
                color: Color.accent
                font.family: popup.root.fontFamily
                font.pixelSize: Style.font.title
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "Trending language"
                color: popup.root.foreground
                font.family: popup.root.fontFamily
                font.pixelSize: Style.font.subtitle
                font.weight: Font.DemiBold
              }
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: "Which shows Discover lists as trending. Search always covers every language."
              color: popup.root.hintLabel
              font.family: popup.root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Row {
              spacing: Style.space(6)

              Repeater {
                model: popup.languages

                delegate: Rectangle {
                  id: langChip
                  required property var modelData
                  readonly property bool active: popup.root.language === modelData.code

                  anchors.verticalCenter: parent.verticalCenter
                  height: popup.controlHeight
                  width: langLabel.implicitWidth + Style.space(24)
                  radius: Style.space(6)
                  color: active ? Util.alpha(Color.accent, 0.12)
                                : (langArea.containsMouse ? Util.alpha(popup.root.foreground, 0.06) : "transparent")
                  border.width: 1
                  border.color: active ? Util.alpha(Color.accent, 0.45) : Util.alpha(popup.root.foreground, 0.12)
                  Behavior on color { ColorAnimation { duration: 110 } }

                  Text {
                    id: langLabel
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: langChip.modelData.label
                    color: langChip.active ? Color.accent : popup.bodyText
                    font.family: popup.root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.weight: langChip.active ? Font.DemiBold : Font.Normal
                  }

                  MouseArea {
                    id: langArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: popup.root.saveLanguage(langChip.modelData.code)
                  }
                }
              }

              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: Style.space(18)
                color: popup.hairline
              }

              PodmarchySettingsField {
                id: languageField
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(130)
                height: popup.controlHeight
                placeholder: "Other: nl, pt…"
                text: popup.languages.some(function(l) { return l.code === popup.root.language }) ? "" : popup.root.language
                onSubmitted: popup.root.saveLanguage(text)
                onFocusLost: if (text.trim() !== "") popup.root.saveLanguage(text)
                Keys.onEscapePressed: popup.close()
              }
            }
          }
        }
      }
    }
  }
}
