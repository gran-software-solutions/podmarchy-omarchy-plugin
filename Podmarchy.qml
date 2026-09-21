import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "PodmarchyModel.js" as Model

Item {
  id: root

  property bool opened: false
  property string filterText: ""
  property string view: "library" // library | discover | continue
  // The show whose episodes are listed, or null for the view's show list.
  property var openShow: null
  property int selectedIndex: 0
  property bool cursorActive: false
  // Hover must not steal the cursor right after a keyboard move: scrolling
  // slides rows under a still pointer and the dwell timer would fire.
  property double lastKeyboardMove: 0
  property var rows: []
  property double now: Date.now()

  // ---- data ----
  property var subscriptions: []
  property var progress: ({})
  property var status: ({ running: false, paused: false, position: 0, duration: 0, episode: {} })
  property var trending: []
  property var searchResults: []
  property string searchedTerm: ""
  property var episodeCache: ({})   // feedId -> items
  property bool apiConfigured: false
  property bool busy: apiProc.running
  property string errorText: ""
  property string language: "en"

  // ---- actions overlay ----
  property bool actionsOpen: false
  property string actionFilter: ""
  property int actionIndex: 0

  // ---- help / settings popup ----
  property bool helpOpen: false
  property string helpTab: "settings"
  property string keyDraft: ""
  property string secretDraft: ""
  property string settingsMessage: ""
  property bool settingsError: false

  property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/podmarchy"
  property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") + "/podmarchy"
  property string subscriptionsPath: stateDir + "/subscriptions.json"
  property string progressPath: stateDir + "/progress.json"
  property string settingsPath: stateDir + "/settings.json"
  property string statusPath: runtimeDir + "/status.json"
  property string apiScript: Qt.resolvedUrl("podmarchy-api").toString().replace("file://", "")
  property string playerScript: Qt.resolvedUrl("podmarchy-player").toString().replace("file://", "")
  property bool statusReady: false

  // ---- look: the same tokens and proportions as Yank ----
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  // A 1px hairline at 40%, not the 2px full-alpha rule of the shell's own
  // popups, which reads as a heavy box at this card size.
  readonly property var borderSpec: Border.flat(Util.alpha(border, 0.4), 1)
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property bool lightTheme: background.hslLightness > 0.5
  readonly property color keycapFill: lightTheme ? Util.alpha("#ffffff", 0.55) : Util.alpha(foreground, 0.07)
  readonly property color keycapBorder: Util.alpha(foreground, 0.20)
  readonly property color keycapText: Util.alpha(foreground, 0.9)
  readonly property color keycapAccentFill: Util.alpha(selectedText, 0.15)
  readonly property color keycapAccentBorder: Util.alpha(selectedText, 0.45)
  readonly property color hintLabel: Util.alpha(foreground, 0.68)
  readonly property color chevron: Util.alpha(foreground, 0.45)
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.space(7)
  property int headerHeight: Style.space(34)
  readonly property int metaFont: Math.max(9, Math.round(Style.font.caption * 0.82))
  readonly property int capHeight: metaFont + Style.space(7)
  readonly property int referenceRowHeight: Style.space(15)
  readonly property int helpPopupWidth: Style.space(880)
  readonly property int helpPopupHeight: Style.space(200)
  property int contentSpacing: Style.space(6)
  property int cardWidth: Math.min(Style.space(960), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(600), panel.height - Style.gapsOut * 2)
  property int rowHeight: Style.space(48)
  property bool previewOpen: true
  readonly property int previewPadding: Style.space(11)
  property color rowHover: Util.alpha(root.foreground, 0.045)

  readonly property var views: [
    { id: "library", label: "Library", glyph: "\u{F02CB}" },
    { id: "discover", label: "Discover", glyph: "\u{F018B}" },
    { id: "continue", label: "Continue", glyph: "\u{F02DA}" }
  ]

  readonly property bool playing: status.running === true
  readonly property var nowEpisode: status.episode || ({})

  // ---- lifecycle ----

  function open(payloadJson) {
    root.opened = true
    root.now = Date.now()
    root.helpOpen = false
    root.closeActions()
    root.filterText = ""
    root.openShow = null
    root.errorText = ""
    // A fresh install lands on Discover; after that, on what you follow.
    root.view = root.subscriptions.length > 0 ? "library" : "discover"
    root.selectedIndex = 0
    root.cursorActive = true
    authStatusProc.running = true
    root.refreshView()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  // ---- views ----

  function setView(id) {
    root.view = id
    root.openShow = null
    root.filterText = ""
    root.errorText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.refreshView()
  }

  function cycleView(dir) {
    var at = 0
    for (var i = 0; i < root.views.length; i++) if (root.views[i].id === root.view) at = i
    root.setView(root.views[(at + dir + root.views.length) % root.views.length].id)
  }

  // Fetch whatever the current view needs, then rebuild the rows.
  function refreshView() {
    if (root.openShow) {
      if (!root.episodeCache[root.openShow.id]) root.request(["episodes", root.openShow.id])
    } else if (root.view === "discover") {
      var term = root.filterText.trim()
      if (term.length >= 2) searchDebounce.restart()
      else if (root.trending.length === 0 && root.apiConfigured) root.request(["trending", root.language])
    }
    root.rebuildRows()
  }

  function rebuildRows() {
    var needle = root.filterText.trim()
    var next
    if (root.openShow) {
      next = Model.episodeRows(root.episodeCache[root.openShow.id] || [], root.openShow,
                               root.progress, root.status, needle)
    } else if (root.view === "library") {
      next = Model.showRows(root.subscriptions, root.subscriptions, needle)
    } else if (root.view === "discover") {
      // The typed text is a remote query here, not a local filter; until the
      // search lands, keep showing trending rather than an empty list.
      var searching = needle.length >= 2 && root.searchedTerm === needle
      next = Model.showRows(searching ? root.searchResults : root.trending, root.subscriptions, "")
    } else {
      next = Model.continueRows(root.progress, root.status, needle)
    }
    root.rows = next
    if (root.rows.length === 0) root.selectedIndex = 0
    else if (root.selectedIndex >= root.rows.length) root.selectedIndex = root.rows.length - 1
    else if (root.selectedIndex < 0) root.selectedIndex = 0
  }

  // Row-level updates (play state, subscribed flag) without jumping the list.
  function refreshRowsInPlace() {
    var keep = root.selectedIndex
    root.rebuildRows()
    root.selectedIndex = Math.min(keep, Math.max(0, root.rows.length - 1))
  }

  function setFilter(text) {
    root.filterText = text
    root.selectedIndex = 0
    root.cursorActive = true
    if (!root.openShow && root.view === "discover") {
      if (text.trim().length >= 2) searchDebounce.restart()
      else { searchDebounce.stop(); root.errorText = "" }
    }
    root.rebuildRows()
    resultList.positionViewAtBeginning()
  }

  function openShowRow(row) {
    root.openShow = {
      id: row.id, title: row.title, author: row.author, image: row.image,
      description: row.description, url: row.url, link: row.link,
      language: row.language, categories: row.categories,
      episodeCount: row.episodeCount, newest: row.newest
    }
    root.filterText = ""
    root.errorText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.refreshView()
    resultList.positionViewAtBeginning()
  }

  function back() {
    if (!root.openShow) return false
    var feedId = root.openShow.id
    root.openShow = null
    root.filterText = ""
    root.errorText = ""
    root.rebuildRows()
    // Land back on the show you came from.
    root.selectedIndex = 0
    for (var i = 0; i < root.rows.length; i++) {
      if (root.rows[i].id === feedId) { root.selectedIndex = i; break }
    }
    Qt.callLater(function() { root.ensureVisible(root.selectedIndex) })
    return true
  }

  // ---- selection ----

  function currentRow() {
    if (!root.cursorActive || root.selectedIndex < 0 || root.selectedIndex >= root.rows.length) return null
    return root.rows[root.selectedIndex]
  }

  function ensureVisible(idx) {
    if (resultList.count > 0) resultList.positionViewAtIndex(idx, ListView.Contain)
  }

  function select(delta) {
    if (root.rows.length === 0) return
    root.lastKeyboardMove = Date.now()
    var wasActive = root.cursorActive
    root.cursorActive = true
    var idx = !wasActive ? (delta < 0 ? root.rows.length - 1 : 0)
                         : (root.selectedIndex + delta + root.rows.length) % root.rows.length
    root.selectedIndex = idx
    root.ensureVisible(idx)
  }

  readonly property bool hoverAllowed: Date.now() - lastKeyboardMove > 700

  // ---- actions on rows ----

  function activate(row, fromStart) {
    if (!row) return
    if (row.rowType === "show") root.openShowRow(row)
    else root.play(row, fromStart)
  }

  function play(row, fromStart) {
    if (!row || !row.url) return
    // Enter on what is already playing pauses or resumes it instead of
    // restarting the episode.
    if (!fromStart && root.playing && String(root.nowEpisode.id) === String(row.id)) {
      root.player(["toggle"])
      return
    }
    root.player(["play", Model.playPayload(row, fromStart)])
  }

  function player(args) {
    Quickshell.execDetached(["bash", root.playerScript].concat(args))
  }

  // Ctrl+P: follows the focused show, or the open show from its episode list.
  function toggleSubscribe() {
    var target = null
    var row = root.currentRow()
    if (row && row.rowType === "show") target = row
    else if (root.openShow) target = root.openShow
    if (!target) return
    root.subscriptions = Model.toggleSubscription(root.subscriptions, target)
    root.saveSubscriptions()
    root.refreshRowsInPlace()
  }

  function markPlayed(row, done) {
    if (!row || row.rowType !== "episode") return
    root.progress = Model.markDone(root.progress, row, done)
    progressFile.setText(JSON.stringify(root.progress, null, 2) + "\n")
    root.refreshRowsInPlace()
  }

  function removeSelected() {
    var row = root.currentRow()
    if (!row) return
    if (root.view === "library" && !root.openShow && row.rowType === "show") {
      root.subscriptions = Model.toggleSubscription(root.subscriptions, row)
      root.saveSubscriptions()
      root.refreshRowsInPlace()
    } else if (root.view === "continue" && !root.openShow && row.rowType === "episode") {
      root.markPlayed(row, false)
    }
  }

  function saveSubscriptions() {
    subscriptionsFile.setText(JSON.stringify(root.subscriptions, null, 2) + "\n")
  }

  function exportOpml() {
    exportProc.payload = Model.opml(root.subscriptions)
    exportProc.stdinEnabled = true
    exportProc.running = true
  }

  // ---- Podcast Index requests ----
  // One request at a time. A newer request queues behind the running one and
  // replaces any older queued request; stale answers are dropped by serial.

  property int requestSerial: 0
  property var pendingRequest: null

  function request(args) {
    root.requestSerial++
    var req = { args: args, serial: root.requestSerial }
    if (apiProc.running) { root.pendingRequest = req; return }
    root.startRequest(req)
  }

  function startRequest(req) {
    apiProc.req = req
    apiProc.output = ""
    apiProc.command = ["bash", root.apiScript].concat(req.args)
    apiProc.running = true
  }

  function handleApi(req, raw) {
    if (req.serial !== root.requestSerial && req.args[0] !== "episodes") return
    var data = null
    try { data = JSON.parse(raw || "{}") } catch (e) { data = { error: "Podmarchy could not read the reply." } }
    if (data.error) {
      root.errorText = data.error
      root.rebuildRows()
      return
    }
    root.errorText = ""
    var kind = req.args[0]
    if (kind === "trending") root.trending = data.feeds || []
    else if (kind === "search") { root.searchResults = data.feeds || []; root.searchedTerm = req.args[1] }
    else if (kind === "episodes") {
      var cache = root.episodeCache
      cache[data.feedId] = data.items || []
      root.episodeCache = cache
    }
    root.rebuildRows()
  }

  // ---- settings ----

  function loadSettings(raw) {
    try {
      var s = JSON.parse(String(raw || "{}"))
      if (s && typeof s.language === "string") root.language = s.language
    } catch (e) {}
  }

  function saveLanguage(text) {
    var lang = String(text || "").trim().toLowerCase()
    if (lang && !/^[a-z,-]{2,40}$/.test(lang)) return
    if (lang === root.language) return
    root.language = lang
    settingsWriter.setText(JSON.stringify({ language: lang }, null, 2) + "\n")
    root.trending = []
    if (root.view === "discover" && !root.openShow) root.refreshView()
  }

  function saveCredentials() {
    if (authSetProc.running) return
    authSetProc.payload = root.keyDraft.trim() + "\n" + root.secretDraft.trim() + "\n"
    authSetProc.output = ""
    authSetProc.stdinEnabled = true
    authSetProc.running = true
  }

  function openHelp(tab) {
    if (root.helpOpen && root.helpTab === tab) {
      root.helpOpen = false
      keyCatcher.forceActiveFocus()
      return
    }
    root.helpTab = tab
    root.helpOpen = true
    root.settingsMessage = ""
    if (tab === "shortcuts") Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  // ---- actions menu ----

  function openActions() {
    if (!root.currentRow() && !root.playing) return
    root.actionsOpen = true
    root.actionFilter = ""
    root.actionIndex = 0
    root.rebuildActions()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function closeActions() {
    root.actionsOpen = false
    root.actionFilter = ""
    root.actionIndex = 0
  }

  function rebuildActions() {
    var row = root.currentRow()
    actionsModel.clear()
    var needle = root.actionFilter.toLowerCase()

    function add(id, label, hint) {
      if (needle && label.toLowerCase().indexOf(needle) < 0) return
      actionsModel.append({ actionId: id, label: label, hint: hint })
    }

    if (row && row.rowType === "show") {
      add("open", "Show episodes", "Enter")
      add("subscribe", row.subscribed ? "Unsubscribe" : "Subscribe", "Ctrl+P")
      if (row.link) add("website", "Open website", "")
      if (row.url) add("copyfeed", "Copy feed URL", "")
    } else if (row) {
      var live = root.playing && String(root.nowEpisode.id) === String(row.id)
      add("play", live ? (root.status.paused ? "Resume" : "Pause")
                       : (row.state === "progress" ? "Resume" : "Play"), "Enter")
      if (row.position > 0 || live) add("restart", "Play from the start", "Shift+Enter")
      add(row.done ? "unplayed" : "played", row.done ? "Mark as unplayed" : "Mark as played", "")
      if (root.openShow) add("subscribe", Model.isSubscribed(root.subscriptions, root.openShow.id) ? "Unsubscribe from show" : "Subscribe to show", "Ctrl+P")
      if (row.link) add("website", "Open episode page", "")
      add("copyaudio", "Copy audio URL", "")
    }
    if (root.playing) add("stop", "Stop playback", "Ctrl+S")
    if (root.subscriptions.length > 0) add("opml", "Export subscriptions as OPML", "")

    if (root.actionIndex >= actionsModel.count) root.actionIndex = Math.max(0, actionsModel.count - 1)
  }

  function runActionById(id) {
    var row = root.currentRow()
    root.closeActions()
    if (id === "open") root.openShowRow(row)
    else if (id === "subscribe") root.toggleSubscribe()
    else if (id === "play") root.play(row, false)
    else if (id === "restart") root.play(row, true)
    else if (id === "played") root.markPlayed(row, true)
    else if (id === "unplayed") root.markPlayed(row, false)
    else if (id === "stop") root.player(["stop"])
    else if (id === "opml") root.exportOpml()
    else if (id === "website" && row && row.link) Quickshell.execDetached(["xdg-open", row.link])
    else if (id === "copyfeed" && row) Quickshell.execDetached(["wl-copy", "--", row.url])
    else if (id === "copyaudio" && row) Quickshell.execDetached(["wl-copy", "--", row.url])
  }

  function runActionIndex(index) {
    if (index < 0 || index >= actionsModel.count) return
    root.runActionById(actionsModel.get(index).actionId)
  }

  ListModel { id: actionsModel }

  // ---- storage and processes ----

  Component.onCompleted: {
    authStatusProc.running = true
    statusInitProc.running = true
  }

  FileView {
    id: subscriptionsFile
    path: root.subscriptionsPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: { root.subscriptions = Model.parseSubscriptions(text()); root.refreshRowsInPlace() }
    onLoadFailed: root.subscriptions = []
    onFileChanged: reload()
  }

  FileView {
    id: progressFile
    path: root.progressPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: { root.progress = Model.parseProgress(text()); if (root.opened) root.refreshRowsInPlace() }
    onLoadFailed: root.progress = ({})
    onFileChanged: reload()
  }

  FileView {
    id: settingsReader
    path: root.settingsPath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadSettings(text())
    onFileChanged: reload()
  }

  FileView {
    id: settingsWriter
    path: root.settingsPath
    atomicWrites: true
    printErrors: false
  }

  // mpv's status script rewrites this every second while an episode plays.
  // It only exists once podmarchy-player has run, hence statusReady.
  FileView {
    path: root.statusReady ? root.statusPath : ""
    watchChanges: true
    printErrors: false
    onLoaded: {
      var previousId = root.nowEpisode.id
      var wasRunning = root.playing
      try {
        var s = JSON.parse(text() || "{}")
        root.status = s && typeof s === "object" ? s : root.status
      } catch (e) { return }
      // Rebuild the rows only when what is playing changes, or while the
      // panel is up (so the progress in the list ticks).
      if (root.opened || previousId !== root.nowEpisode.id || wasRunning !== root.playing)
        root.refreshRowsInPlace()
    }
    onFileChanged: reload()
  }

  Process {
    id: statusInitProc
    command: ["bash", root.playerScript, "status"]
    onExited: root.statusReady = true
  }

  Process {
    id: apiProc
    property var req: null
    property string output: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: apiProc.output = text
    }
    onExited: {
      var req = apiProc.req
      var out = apiProc.output
      apiProc.output = ""
      if (req) root.handleApi(req, out)
      if (root.pendingRequest) {
        var next = root.pendingRequest
        root.pendingRequest = null
        Qt.callLater(function() { root.startRequest(next) })
      }
    }
  }

  Process {
    id: authStatusProc
    command: ["bash", root.apiScript, "auth-status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var was = root.apiConfigured
        try { root.apiConfigured = JSON.parse(text).configured === true } catch (e) {}
        // The answer lands after open(); fetch what the view was waiting for.
        if (root.apiConfigured && !was && root.opened) root.refreshView()
      }
    }
  }

  Process {
    id: authSetProc
    property string payload: ""
    property string output: ""
    command: ["bash", root.apiScript, "auth-set"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: authSetProc.output = text
    }
    onStarted: {
      write(payload)
      payload = ""
      stdinEnabled = false
    }
    onExited: function(exitCode) {
      var reply = {}
      try { reply = JSON.parse(authSetProc.output || "{}") } catch (e) {}
      if (exitCode === 0) {
        root.apiConfigured = true
        root.settingsError = false
        root.settingsMessage = "Saved. Podmarchy is connected to Podcast Index."
        root.keyDraft = ""
        root.secretDraft = ""
        keyField.text = ""
        secretField.text = ""
        keyCatcher.forceActiveFocus()
        root.errorText = ""
        root.trending = []
        root.refreshView()
      } else {
        root.settingsError = true
        root.settingsMessage = reply.error || "Could not save the key."
      }
    }
  }

  Process {
    id: exportProc
    property string payload: ""
    command: ["bash", "-c",
      "f=\"${XDG_DOCUMENTS_DIR:-$HOME}/podmarchy-subscriptions.opml\"; cat > \"$f\" && notify-send -a Podmarchy 'Subscriptions exported' \"$f\""]
    onStarted: {
      write(payload)
      payload = ""
      stdinEnabled = false
    }
  }

  Timer {
    id: searchDebounce
    interval: 450
    repeat: false
    onTriggered: {
      var term = root.filterText.trim()
      if (term.length >= 2 && term !== root.searchedTerm && root.apiConfigured) root.request(["search", term])
    }
  }

  Timer {
    interval: 30000
    repeat: true
    running: root.opened
    onTriggered: root.now = Date.now()
  }

  // ---- shared components ----

  component KeyCap: Rectangle {
    id: keyCap
    property string label
    property bool primary: false
    width: keyCapLabel.implicitWidth + Style.space(9)
    height: capHeight
    radius: 5
    color: keyCap.primary ? root.keycapAccentFill : root.keycapFill
    border.color: keyCap.primary ? root.keycapAccentBorder : root.keycapBorder
    border.width: 1

    Text {
      id: keyCapLabel
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: keyCap.label
      color: root.keycapText
      font.family: root.fontFamily
      font.pixelSize: root.metaFont
      font.weight: keyCap.primary ? Font.DemiBold : Font.Normal
    }
  }

  component ShortcutRow: Row {
    id: shortcutRow
    property var keys: []
    property string label
    spacing: Style.space(12)

    Row {
      width: Style.space(104)
      height: root.referenceRowHeight
      spacing: Style.space(3)

      Repeater {
        model: shortcutRow.keys
        delegate: KeyCap { required property string modelData; label: modelData }
      }
    }

    Text {
      textFormat: Text.PlainText
      text: shortcutRow.label
      color: root.hintLabel
      height: root.referenceRowHeight
      verticalAlignment: Text.AlignVCenter
      font.family: root.fontFamily
      font.pixelSize: root.metaFont
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  component ShortcutGroup: Column {
    id: shortcutGroup
    property string title
    property var rows: []
    spacing: Style.space(3)

    Text {
      textFormat: Text.PlainText
      text: shortcutGroup.title
      color: root.selectedText
      font.family: root.fontFamily
      font.pixelSize: root.metaFont
      font.letterSpacing: 1.4
      font.weight: Font.DemiBold
      bottomPadding: Style.space(4)
    }

    Repeater {
      model: shortcutGroup.rows
      delegate: ShortcutRow {
        required property var modelData
        keys: modelData.keys
        label: modelData.label
      }
    }
  }

  component SettingsLabel: Text {
    textFormat: Text.PlainText
    color: root.hintLabel
    font.family: root.fontFamily
    font.pixelSize: root.metaFont
    font.letterSpacing: 1.0
    font.weight: Font.DemiBold
  }

  // Keycap-styled text field, as in Yank's retention setting.
  component SettingsField: Rectangle {
    id: field
    property alias input: fieldInput
    property alias text: fieldInput.text
    property string placeholder: ""
    property bool secret: false
    signal edited(string value)
    signal submitted()
    signal focusLost()
    height: Style.space(26)
    radius: Style.space(5)
    color: root.keycapFill
    border.width: fieldInput.activeFocus ? 2 : 1
    border.color: fieldInput.activeFocus ? Util.alpha(root.selectedText, 0.6) : Util.alpha(root.foreground, 0.20)

    TextInput {
      id: fieldInput
      anchors.fill: parent
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      verticalAlignment: TextInput.AlignVCenter
      color: root.foreground
      selectionColor: Util.alpha(root.selectedText, 0.35)
      selectedTextColor: root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.metaFont
      echoMode: field.secret ? TextInput.Password : TextInput.Normal
      activeFocusOnPress: true
      clip: true
      onTextEdited: field.edited(text)
      onActiveFocusChanged: if (!activeFocus) field.focusLost()
      Keys.onReturnPressed: field.submitted()
      Keys.onEnterPressed: field.submitted()
      Keys.onEscapePressed: { root.helpOpen = false; keyCatcher.forceActiveFocus() }
    }

    Text {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      visible: fieldInput.text.length === 0
      textFormat: Text.PlainText
      text: field.placeholder
      color: root.foreground
      opacity: 0.35
      font.family: root.fontFamily
      font.pixelSize: root.metaFont
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.IBeamCursor
      onClicked: fieldInput.forceActiveFocus()
    }
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "de.gransoftware.podmarchy"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin
      opacity: root.opened ? 1 : 0
      scale: root.opened ? 1 : 0.985
      Behavior on opacity { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        z: root.actionsOpen ? 20 : 0
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          var ctrl = event.modifiers & Qt.ControlModifier
          var shift = event.modifiers & Qt.ShiftModifier

          // ---- actions overlay keys ----
          if (root.actionsOpen) {
            var n = actionsModel.count
            if (event.key === Qt.Key_Escape) root.closeActions()
            else if ((event.key === Qt.Key_K && ctrl) || event.key === Qt.Key_Up) { if (n > 0) root.actionIndex = (root.actionIndex - 1 + n) % n }
            else if ((event.key === Qt.Key_J && ctrl) || event.key === Qt.Key_Down) { if (n > 0) root.actionIndex = (root.actionIndex + 1) % n }
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.runActionIndex(root.actionIndex)
            else if (event.key === Qt.Key_Backspace) { root.actionFilter = root.actionFilter.slice(0, -1); root.rebuildActions() }
            else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
              root.actionFilter += event.text
              root.actionIndex = 0
              root.rebuildActions()
            } else return
            event.accepted = true
            Qt.callLater(function() {
              if (actionsList.count > 0) actionsList.positionViewAtIndex(root.actionIndex, ListView.Contain)
            })
            return
          }

          // ---- main keys ----
          if (event.key === Qt.Key_Escape) {
            if (root.helpOpen) root.helpOpen = false
            else if (root.filterText) root.setFilter("")
            else if (!root.back()) root.close()
          } else if (event.key === Qt.Key_Space && ctrl) {
            if (root.playing) root.player(["toggle"])
          } else if (event.key === Qt.Key_Left && ctrl) {
            root.player(["seek", "-15"])
          } else if (event.key === Qt.Key_Right && ctrl) {
            root.player(["seek", "30"])
          } else if (event.key === Qt.Key_S && ctrl) {
            root.player(["stop"])
          } else if (event.key === Qt.Key_O && ctrl) {
            root.previewOpen = !root.previewOpen
          } else if (event.key === Qt.Key_K && ctrl) {
            root.select(-1)
          } else if (event.key === Qt.Key_J && ctrl) {
            root.select(1)
          } else if (event.key === Qt.Key_P && ctrl) {
            root.toggleSubscribe()
          } else if (event.key === Qt.Key_Period && ctrl) {
            root.openActions()
          } else if (event.key === Qt.Key_D && ctrl) {
            root.removeSelected()
          } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_3 && ctrl) {
            root.setView(root.views[event.key - Qt.Key_1].id)
          } else if ((event.key === Qt.Key_H || event.key === Qt.Key_L) && ctrl) {
            root.cycleView(event.key === Qt.Key_H ? -1 : 1)
          } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            root.cycleView(event.key === Qt.Key_Backtab || shift ? -1 : 1)
          } else if (event.key === Qt.Key_Comma && ctrl) {
            root.openHelp("settings")
          } else if (event.key === Qt.Key_Question) {
            root.openHelp("shortcuts")
          } else if (event.key === Qt.Key_Backspace && !root.filterText && root.openShow) {
            // Backspace on an empty search steps out of a show, like a file browser.
            root.back()
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
          } else if (event.key === Qt.Key_Delete) {
            root.removeSelected()
          } else if (event.key === Qt.Key_Up) {
            root.select(-1)
          } else if (event.key === Qt.Key_Down) {
            root.select(1)
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.cursorActive) root.activate(root.currentRow(), shift)
            else if (root.rows.length > 0) root.cursorActive = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
          } else {
            return
          }
          event.accepted = true
        }
      }

      Column {
        id: column
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: 0

        // ---- header: back chip + search field + view chips ----
        Item {
          id: header
          width: parent.width
          height: root.headerHeight + Style.space(14)

          Rectangle {
            id: backChip
            visible: !!root.openShow
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            height: root.headerHeight
            width: visible ? backRow.implicitWidth + Style.space(22) : 0
            radius: Style.space(8)
            color: backArea.containsMouse ? Util.alpha(root.foreground, 0.09) : Util.alpha(root.foreground, 0.05)
            border.width: 1
            border.color: Util.alpha(root.foreground, 0.10)

            Row {
              id: backRow
              anchors.centerIn: parent
              spacing: Style.space(6)

              Text {
                text: "\u{F0141}"
                color: Color.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                textFormat: Text.PlainText
                text: root.openShow ? root.openShow.title : ""
                width: Math.min(implicitWidth, Style.space(200))
                elide: Text.ElideRight
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.weight: Font.DemiBold
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            MouseArea {
              id: backArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.back()
            }
          }

          Rectangle {
            id: searchField
            anchors.left: backChip.visible ? backChip.right : parent.left
            anchors.leftMargin: backChip.visible ? Style.space(8) : 0
            anchors.right: viewChips.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            height: root.headerHeight
            radius: Style.space(8)
            color: Util.alpha(root.foreground, 0.05)
            border.width: 1
            border.color: root.filterText.length > 0 ? Util.alpha(Color.accent, 0.55) : Util.alpha(root.foreground, 0.10)
            Behavior on border.color { ColorAnimation { duration: 120 } }

            Text {
              id: searchIcon
              anchors.left: parent.left
              anchors.leftMargin: Style.space(11)
              anchors.verticalCenter: parent.verticalCenter
              text: "\u{F0349}"
              color: root.filterText.length > 0 ? Color.accent : root.foreground
              opacity: root.filterText.length > 0 ? 1 : 0.4
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
            }

            Text {
              anchors.left: searchIcon.right
              anchors.leftMargin: Style.space(9)
              anchors.right: spinner.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.filterText || (root.openShow ? "Filter episodes"
                                        : root.view === "discover" ? "Search Podcast Index"
                                        : root.view === "continue" ? "Filter what you are listening to"
                                        : "Filter your podcasts")
              color: root.foreground
              opacity: root.filterText.length > 0 ? 1 : 0.38
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              elide: Text.ElideLeft
            }

            Rectangle {
              visible: root.filterText.length > 0
              width: 1.5
              height: Style.font.subtitle + 2
              color: Color.accent
              x: searchIcon.x + searchIcon.width + Style.space(9) + searchMeasure.width + 1
              anchors.verticalCenter: parent.verticalCenter
              SequentialAnimation on opacity {
                loops: Animation.Infinite
                running: root.opened && root.filterText.length > 0
                NumberAnimation { to: 0; duration: 530; easing.type: Easing.InQuad }
                NumberAnimation { to: 1; duration: 530; easing.type: Easing.OutQuad }
              }
            }
            TextMetrics {
              id: searchMeasure
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              text: root.filterText
            }

            // Spins while Podcast Index is answering.
            Text {
              id: spinner
              anchors.right: clearButton.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              visible: root.busy
              width: root.busy ? Style.font.body + 2 : 0
              horizontalAlignment: Text.AlignHCenter
              text: "\u{F0453}"
              color: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              RotationAnimation on rotation {
                running: root.busy && root.opened
                loops: Animation.Infinite
                from: 0; to: 360; duration: 900
              }
            }

            Rectangle {
              id: clearButton
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              visible: root.filterText.length > 0
              width: visible ? Style.space(18) : 0
              height: Style.space(18)
              radius: height / 2
              color: clearArea.containsMouse ? Util.alpha(root.foreground, 0.16) : Util.alpha(root.foreground, 0.07)

              Text {
                anchors.centerIn: parent
                text: "✕"
                color: root.foreground
                opacity: 0.65
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                id: clearArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setFilter("")
              }
            }
          }

          // view chips: a compact segmented control
          Rectangle {
            id: viewChips
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: root.headerHeight
            width: chipsRow.implicitWidth + Style.space(6)
            radius: Style.space(8)
            color: Util.alpha(root.foreground, 0.05)
            border.width: 1
            border.color: Util.alpha(root.foreground, 0.10)

            Row {
              id: chipsRow
              anchors.centerIn: parent
              spacing: Style.space(2)

              Repeater {
                model: root.views

                delegate: Rectangle {
                  id: chip
                  required property var modelData
                  readonly property bool active: root.view === modelData.id
                  readonly property bool hovered: chipArea.containsMouse

                  height: root.headerHeight - Style.space(6)
                  width: chipLabel.implicitWidth + Style.space(active ? 32 : 20) + (active ? chipGlyph.implicitWidth : 0)
                  radius: Style.space(6)
                  color: active ? root.background : (hovered ? Util.alpha(root.foreground, 0.06) : "transparent")
                  border.width: active ? 1 : 0
                  border.color: Util.alpha(root.foreground, 0.12)
                  Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                  Behavior on color { ColorAnimation { duration: 110 } }

                  Row {
                    anchors.centerIn: parent
                    spacing: Style.space(6)

                    Text {
                      id: chipGlyph
                      visible: chip.active
                      text: chip.modelData.glyph
                      color: Color.accent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                      id: chipLabel
                      textFormat: Text.PlainText
                      text: chip.modelData.label
                      color: root.foreground
                      opacity: chip.active ? 1 : (chip.hovered ? 0.8 : 0.5)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.weight: chip.active ? Font.DemiBold : Font.Normal
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }

                  MouseArea {
                    id: chipArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.setView(chip.modelData.id)
                  }
                }
              }
            }
          }
        }

        Rectangle { width: parent.width; height: 1; color: Util.alpha(root.foreground, 0.08) }

        // ---- body: list | detail ----
        Item {
          id: contentArea
          width: parent.width
          height: parent.height - header.height - footer.height - 2

          component SectionLabel: Text {
            textFormat: Text.PlainText
            color: root.foreground
            opacity: 0.4
            font.family: root.fontFamily
            font.pixelSize: root.metaFont
            font.letterSpacing: 1.4
            leftPadding: Style.space(12)
            topPadding: Style.space(8)
            bottomPadding: Style.space(4)
          }

          Item {
            id: listColumn
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: root.previewOpen ? Math.round(parent.width * 0.46) : parent.width
            Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

            SectionLabel {
              id: listHeading
              anchors.top: parent.top
              visible: root.rows.length > 0
              text: {
                if (root.openShow) return "EPISODES"
                if (root.view === "library") return "SUBSCRIBED"
                if (root.view === "continue") return "IN PROGRESS"
                var term = root.filterText.trim()
                return term.length >= 2 && root.searchedTerm === term ? "RESULTS" : "TRENDING"
              }
            }

            ListView {
              id: resultList
              anchors.top: listHeading.visible ? listHeading.bottom : parent.top
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.space(4)
              model: root.rows
              clip: true
              spacing: Style.space(2)
              boundsBehavior: Flickable.StopAtBounds

              delegate: Rectangle {
                id: listRow
                required property int index
                required property var modelData

                readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex
                readonly property bool hovered: rowHoverArea.containsMouse
                readonly property bool isShow: modelData.rowType === "show"
                readonly property bool live: modelData.state === "playing" || modelData.state === "paused"
                // Artwork in the tile for shows, and for episodes from mixed
                // shows (Continue). Inside one show every episode shares the
                // cover, so the tile shows the episode's state instead.
                readonly property bool showArt: modelData.image !== "" && (isShow || !root.openShow)

                width: ListView.view.width
                height: root.rowHeight
                radius: Style.space(7)
                color: hasCursor ? root.selectedBackground : (hovered ? root.rowHover : "transparent")
                Behavior on color { ColorAnimation { duration: 90 } }

                Rectangle {
                  visible: listRow.hasCursor
                  width: 3
                  height: parent.height * 0.46
                  radius: 1.5
                  color: Color.accent
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(3)
                  anchors.verticalCenter: parent.verticalCenter
                }

                Rectangle {
                  id: tile
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  width: root.rowHeight - Style.space(14)
                  height: width
                  radius: Style.space(6)
                  clip: true
                  color: Util.alpha(listRow.live || listRow.modelData.subscribed ? Color.accent : root.foreground,
                                    listRow.hasCursor ? 0.14 : 0.07)
                  border.width: 1
                  border.color: Util.alpha(root.foreground, listRow.showArt ? 0.16 : 0)

                  Image {
                    visible: listRow.showArt && status === Image.Ready
                    anchors.fill: parent
                    source: listRow.showArt ? listRow.modelData.image : ""
                    sourceSize.width: 96
                    sourceSize.height: 96
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                    cache: true
                  }

                  Text {
                    visible: !listRow.showArt || listRow.live
                    anchors.centerIn: parent
                    text: {
                      switch (listRow.modelData.state) {
                        case "playing": return "\u{F03E4}"
                        case "paused": return "\u{F040A}"
                        case "done": return "\u{F012C}"
                        case "progress": return "\u{F0150}"
                        default: return listRow.isShow ? "\u{F0994}" : "\u{F040A}"
                      }
                    }
                    color: listRow.live ? Color.accent : root.foreground
                    opacity: listRow.live ? 1 : (listRow.modelData.state === "done" ? 0.35 : 0.6)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    style: listRow.showArt ? Text.Outline : Text.Normal
                    styleColor: root.background
                  }
                }

                Column {
                  anchors.left: tile.right
                  anchors.leftMargin: Style.space(11)
                  anchors.right: trailing.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: listRow.modelData.title
                    color: listRow.live ? Color.accent : root.foreground
                    opacity: listRow.modelData.state === "done" ? 0.55 : 1
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: {
                      var r = listRow.modelData
                      var parts = []
                      if (listRow.isShow) {
                        if (r.author) parts.push(r.author)
                        if (r.episodeCount > 0) parts.push(r.episodeCount + " episodes")
                        else if (r.categories) parts.push(r.categories.split(", ")[0])
                      } else {
                        if (!root.openShow && r.show) parts.push(r.show)
                        var d = Model.day(r.date, root.now)
                        if (d) parts.push(d)
                        var left = r.position > 0 && !r.done ? Model.remaining(r.position, r.duration) : ""
                        var dur = Model.duration(r.duration)
                        if (left) parts.push(left)
                        else if (dur) parts.push(dur)
                      }
                      return parts.join("  ·  ")
                    }
                    color: root.foreground
                    opacity: 0.45
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                // Listening progress: a hairline under the row text.
                Rectangle {
                  visible: !listRow.isShow && listRow.modelData.position > 0 && listRow.modelData.duration > 0 && !listRow.modelData.done
                  anchors.left: tile.right
                  anchors.leftMargin: Style.space(11)
                  anchors.right: trailing.left
                  anchors.rightMargin: Style.space(8)
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: Style.space(4)
                  height: 2
                  radius: 1
                  color: Util.alpha(root.foreground, 0.08)

                  Rectangle {
                    height: parent.height
                    radius: 1
                    color: Color.accent
                    width: parent.width * Math.min(1, listRow.modelData.position / Math.max(1, listRow.modelData.duration))
                  }
                }

                Text {
                  id: trailing
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  width: listRow.modelData.subscribed ? implicitWidth : 0
                  text: listRow.modelData.subscribed ? "\u{F02D1}" : ""
                  color: Color.accent
                  opacity: 0.7
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Timer {
                  id: hoverDwell
                  interval: 220
                  repeat: false
                  onTriggered: {
                    if (!root.hoverAllowed) return
                    root.cursorActive = true
                    root.selectedIndex = listRow.index
                  }
                }

                MouseArea {
                  id: rowHoverArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: if (root.hoverAllowed) hoverDwell.restart()
                  onExited: hoverDwell.stop()
                  onClicked: {
                    hoverDwell.stop()
                    root.cursorActive = true
                    root.selectedIndex = listRow.index
                    root.activate(listRow.modelData, false)
                  }
                }
              }
            }

            // slim scroll indicator
            Item {
              visible: resultList.contentHeight > resultList.height + 1
              anchors.top: resultList.top
              anchors.bottom: resultList.bottom
              anchors.right: parent.right
              width: Style.space(3)

              Rectangle {
                width: parent.width
                radius: width / 2
                color: Util.alpha(root.foreground, 0.2)
                height: Math.max(Style.space(20), parent.height * (resultList.height / Math.max(1, resultList.contentHeight)))
                y: {
                  var maxScroll = Math.max(1, resultList.contentHeight - resultList.height)
                  var travel = Math.max(0, parent.height - height)
                  return Math.max(0, Math.min(travel, (resultList.contentY / maxScroll) * travel))
                }
              }
            }
          }

          Rectangle {
            visible: root.previewOpen
            anchors.left: listColumn.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 1
            color: Util.alpha(root.foreground, 0.08)
          }

          // ---- detail pane: the focused show or episode ----
          Item {
            id: previewPane
            anchors.left: listColumn.right
            anchors.leftMargin: 1
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            visible: root.previewOpen && width > Style.space(40)
            clip: true

            // With nothing focused inside a show, describe the show itself.
            readonly property var row: root.currentRow() || (root.openShow ? Model.showRow(root.openShow, Model.isSubscribed(root.subscriptions, root.openShow.id)) : null)
            readonly property bool isShow: !!row && row.rowType === "show"
            readonly property bool live: !!row && (row.state === "playing" || row.state === "paused")

            Item {
              id: detailHeader
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: root.previewPadding
              height: Style.space(22)
              visible: !!previewPane.row

              Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(20)
                width: badgeText.implicitWidth + Style.space(16)
                radius: height / 2
                color: Util.alpha(Color.accent, 0.14)

                Text {
                  id: badgeText
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: {
                    var r = previewPane.row
                    if (!r) return ""
                    if (previewPane.isShow) return r.subscribed ? "\u{F02D1}  Subscribed" : "Podcast"
                    return Model.stateLabel(r.state)
                  }
                  color: Color.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.weight: Font.DemiBold
                }
              }

              Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: {
                  var r = previewPane.row
                  if (!r) return ""
                  if (previewPane.isShow) {
                    var d = Model.day(r.newest, root.now)
                    return d ? "Latest episode " + d.charAt(0).toLowerCase() + d.slice(1) : ""
                  }
                  return Model.day(r.date, root.now)
                }
                color: root.foreground
                opacity: 0.45
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Item {
              id: detailBody
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: detailHeader.bottom
              anchors.bottom: detailMeta.top
              anchors.leftMargin: root.previewPadding
              anchors.rightMargin: root.previewPadding
              anchors.topMargin: Style.space(10)
              anchors.bottomMargin: Style.space(10)
              visible: !!previewPane.row

              // cover + title block
              Item {
                id: hero
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: cover.height

                Rectangle {
                  id: cover
                  width: Math.min(Style.space(128), detailBody.width * 0.36)
                  height: width
                  radius: Style.space(8)
                  clip: true
                  color: Util.alpha(root.foreground, 0.04)
                  border.width: 1
                  border.color: Util.alpha(root.foreground, 0.08)

                  Image {
                    id: coverImage
                    anchors.fill: parent
                    source: previewPane.row ? previewPane.row.image : ""
                    sourceSize.width: 320
                    sourceSize.height: 320
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                    mipmap: true
                  }

                  Text {
                    visible: coverImage.status !== Image.Ready
                    anchors.centerIn: parent
                    text: "\u{F0994}"
                    color: Color.accent
                    opacity: 0.5
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.displayLarge
                  }
                }

                Column {
                  anchors.left: cover.right
                  anchors.leftMargin: Style.space(12)
                  anchors.right: parent.right
                  anchors.verticalCenter: cover.verticalCenter
                  spacing: Style.space(4)

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: previewPane.row ? previewPane.row.title : ""
                    color: previewPane.live ? Color.accent : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.heading
                    font.weight: Font.DemiBold
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: {
                      var r = previewPane.row
                      if (!r) return ""
                      return previewPane.isShow ? r.author : r.show
                    }
                    visible: text !== ""
                    color: root.foreground
                    opacity: 0.6
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }

                  // episode progress, live while it plays
                  Item {
                    visible: !previewPane.isShow && !!previewPane.row && previewPane.row.duration > 0
                    width: parent.width
                    height: Style.space(22)

                    Rectangle {
                      id: detailTrack
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.top: parent.top
                      anchors.topMargin: Style.space(6)
                      height: 3
                      radius: 1.5
                      color: Util.alpha(root.foreground, 0.10)

                      Rectangle {
                        height: parent.height
                        radius: 1.5
                        color: Color.accent
                        width: {
                          var r = previewPane.row
                          if (!r || r.duration <= 0) return 0
                          var f = r.done ? 1 : r.position / r.duration
                          return parent.width * Math.max(0, Math.min(1, f))
                        }
                      }
                    }

                    Text {
                      anchors.left: parent.left
                      anchors.top: detailTrack.bottom
                      anchors.topMargin: Style.space(4)
                      textFormat: Text.PlainText
                      text: previewPane.row ? Model.clock(previewPane.row.position) : ""
                      color: root.foreground
                      opacity: 0.45
                      font.family: root.fontFamily
                      font.pixelSize: root.metaFont
                    }

                    Text {
                      anchors.right: parent.right
                      anchors.top: detailTrack.bottom
                      anchors.topMargin: Style.space(4)
                      textFormat: Text.PlainText
                      text: previewPane.row ? Model.clock(previewPane.row.duration) : ""
                      color: root.foreground
                      opacity: 0.45
                      font.family: root.fontFamily
                      font.pixelSize: root.metaFont
                    }
                  }
                }
              }

              Flickable {
                id: detailFlick
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: hero.bottom
                anchors.topMargin: Style.space(12)
                anchors.bottom: parent.bottom
                contentWidth: width
                contentHeight: detailText.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Text {
                  id: detailText
                  width: parent.width
                  textFormat: Text.PlainText
                  text: previewPane.row ? (previewPane.row.description || "No description.") : ""
                  color: root.foreground
                  opacity: 0.85
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  lineHeight: 1.25
                  wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                }
              }
            }

            Text {
              id: detailMeta
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.margins: root.previewPadding
              visible: !!previewPane.row
              textFormat: Text.PlainText
              text: {
                var r = previewPane.row
                if (!r) return ""
                var parts = []
                if (previewPane.isShow) {
                  if (r.categories) parts.push(r.categories)
                  if (r.language) parts.push(r.language)
                  if (r.episodeCount > 0) parts.push(r.episodeCount + " episodes")
                } else {
                  var dur = Model.duration(r.duration)
                  if (dur) parts.push(dur)
                  var left = r.position > 0 && !r.done ? Model.remaining(r.position, r.duration) : ""
                  if (left) parts.push(left)
                }
                return parts.join("  ·  ")
              }
              color: root.foreground
              opacity: 0.45
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          // ---- empty / error state ----
          Column {
            anchors.centerIn: parent
            width: parent.width * 0.7
            spacing: Style.space(8)
            visible: root.rows.length === 0 && !root.actionsOpen

            Text {
              text: (root.errorText !== "" && !root.apiConfigured) || (root.view === "discover" && !root.apiConfigured)
                    ? "\u{F0306}" : (root.errorText ? "\u{F0028}" : "\u{F0994}")
              color: Color.accent
              opacity: 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
              text: {
                if (!root.apiConfigured && (root.view === "discover" || root.openShow))
                  return "Connect Podcast Index to discover shows"
                if (root.errorText) return root.errorText
                if (root.busy) return "Asking Podcast Index…"
                if (root.filterText) return "Nothing matches “" + root.filterText + "”"
                if (root.openShow) return "No episodes found"
                if (root.view === "library") return "No subscriptions yet"
                if (root.view === "continue") return "Nothing in progress"
                if (!root.apiConfigured) return "Connect Podcast Index to discover shows"
                return "Nothing trending right now"
              }
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
              visible: text !== ""
              text: {
                if (root.busy || root.filterText) return ""
                if (!root.apiConfigured && (root.view === "discover" || root.openShow))
                  return "It is free: get a key at api.podcastindex.org, then paste it in settings (Ctrl+,)."
                if (root.view === "library" && !root.openShow) return "Press Tab to discover shows, then Ctrl+P to subscribe."
                if (root.view === "continue") return "Episodes you start show up here."
                return ""
              }
              color: root.hintLabel
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        // The divider doubles as the now-playing progress bar.
        Rectangle {
          width: parent.width
          height: 1
          color: Util.alpha(root.foreground, 0.08)

          Rectangle {
            visible: root.playing && root.status.duration > 0
            height: 2
            y: -0.5
            radius: 1
            color: Color.accent
            width: parent.width * Math.max(0, Math.min(1, root.status.position / Math.max(1, root.status.duration)))
          }
        }

        // ---- footer: now playing + key hints ----
        Item {
          id: footer
          width: parent.width
          height: Style.space(34)

          Row {
            id: nowPlaying
            anchors.left: parent.left
            anchors.leftMargin: Style.space(4)
            anchors.right: hints.left
            anchors.rightMargin: Style.space(14)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(7)

            Text {
              id: nowGlyph
              visible: root.playing
              text: root.status.paused ? "\u{F040A}" : "\u{F03E4}"
              color: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              anchors.verticalCenter: parent.verticalCenter

              MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                cursorShape: Qt.PointingHandCursor
                onClicked: root.player(["toggle"])
              }
            }

            Text {
              width: nowPlaying.width - (nowGlyph.visible ? nowGlyph.width + nowPlaying.spacing : 0)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: {
                if (root.playing) {
                  var t = root.nowEpisode.title || "Playing"
                  var time = Model.clock(root.status.position) + (root.status.duration > 0 ? " / " + Model.clock(root.status.duration) : "")
                  return (root.status.buffering ? "Buffering…  " : "") + t + "  ·  " + time
                }
                var n = root.rows.length
                return n === 0 ? "" : n + (root.openShow ? (n === 1 ? " episode" : " episodes") : (n === 1 ? " show" : " shows"))
              }
              color: root.foreground
              opacity: root.playing ? 0.8 : 0.45
              font.family: root.fontFamily
              font.pixelSize: root.metaFont
              elide: Text.ElideRight
            }
          }

          Row {
            id: hints
            anchors.right: gear.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(14)

            Repeater {
              model: {
                var r = root.currentRow()
                var first = r && r.rowType === "show" ? { keys: "Enter", label: "Episodes", primary: true }
                                                     : { keys: "Enter", label: "Play", primary: true }
                var list = [first, { keys: "Ctrl+P", label: "Subscribe" }]
                if (root.playing) list.push({ keys: "Ctrl+Space", label: root.status.paused ? "Resume" : "Pause" })
                list.push({ keys: "Ctrl+.", label: "Actions" }, { keys: "?", label: "Keys" })
                return list
              }

              delegate: Row {
                required property var modelData
                spacing: Style.space(6)
                KeyCap { label: modelData.keys; primary: !!modelData.primary; anchors.verticalCenter: parent.verticalCenter }
                Text {
                  textFormat: Text.PlainText
                  text: modelData.label
                  color: root.hintLabel
                  font.family: root.fontFamily
                  font.pixelSize: root.metaFont
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }
          }

          Item {
            id: gear
            width: Style.space(22)
            height: width
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
              anchors.fill: parent
              radius: width / 2
              color: gearArea.containsMouse || root.helpOpen ? Util.alpha(root.foreground, 0.08) : "transparent"
              Behavior on color { ColorAnimation { duration: 110 } }
            }

            Text {
              anchors.centerIn: parent
              text: "\u{F0493}"
              color: root.helpOpen ? root.selectedText : (root.apiConfigured ? root.chevron : Color.accent)
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            MouseArea {
              id: gearArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openHelp("settings")
            }
          }
        }
      }

      // ---- help popup: shortcuts and settings ----
      Rectangle {
        anchors.fill: parent
        radius: root.cornerRadius
        color: Util.alpha(root.foreground, 0.28)
        visible: opacity > 0.01
        opacity: root.helpOpen ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent; onClicked: { root.helpOpen = false; keyCatcher.forceActiveFocus() } }
      }

      BorderSurface {
        id: helpCard
        anchors.centerIn: parent
        width: Math.min(root.helpPopupWidth, card.width - Style.space(60))
        height: Math.min(root.helpPopupHeight, card.height - Style.space(60))
        radius: root.cornerRadius
        color: Util.alpha(root.background, 1)
        borderSpec: root.borderSpec
        padding: root.contentMargin
        visible: opacity > 0.01
        opacity: root.helpOpen ? 1 : 0
        scale: root.helpOpen ? 1 : 0.99
        Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
          anchors.fill: parent
          anchors.topMargin: parent.contentTopInset + Style.space(4)
          anchors.rightMargin: parent.contentRightInset + Style.space(2)
          anchors.bottomMargin: parent.contentBottomInset
          anchors.leftMargin: parent.contentLeftInset + Style.space(2)
          spacing: root.contentSpacing

          // Page switcher. Explicit items rather than a Repeater: repeated
          // delegates in this popup did not render in Yank.
          Row {
            spacing: Style.space(4)

            Item {
              id: tabShortcuts
              width: tabShortcutsLabel.implicitWidth + Style.space(18)
              height: Style.space(24)
              readonly property bool active: root.helpTab === "shortcuts"

              Rectangle {
                anchors.fill: parent
                radius: Style.space(5)
                color: tabShortcuts.active ? Util.alpha(root.selectedText, 0.16)
                                           : (tabShortcutsArea.containsMouse ? Util.alpha(root.foreground, 0.06) : "transparent")
                border.width: 1
                border.color: tabShortcuts.active ? Util.alpha(root.selectedText, 0.45) : Util.alpha(root.foreground, 0.16)
              }

              Text {
                id: tabShortcutsLabel
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "SHORTCUTS"
                color: tabShortcuts.active ? root.selectedText : root.foreground
                font.family: root.fontFamily
                font.pixelSize: root.metaFont
                font.letterSpacing: 1.0
                font.weight: tabShortcuts.active ? Font.DemiBold : Font.Normal
              }

              MouseArea {
                id: tabShortcutsArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.helpTab = "shortcuts"; keyCatcher.forceActiveFocus() }
              }
            }

            Item {
              id: tabSettings
              width: tabSettingsLabel.implicitWidth + Style.space(18)
              height: Style.space(24)
              readonly property bool active: root.helpTab === "settings"

              Rectangle {
                anchors.fill: parent
                radius: Style.space(5)
                color: tabSettings.active ? Util.alpha(root.selectedText, 0.16)
                                          : (tabSettingsArea.containsMouse ? Util.alpha(root.foreground, 0.06) : "transparent")
                border.width: 1
                border.color: tabSettings.active ? Util.alpha(root.selectedText, 0.45) : Util.alpha(root.foreground, 0.16)
              }

              Text {
                id: tabSettingsLabel
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "SETTINGS"
                color: tabSettings.active ? root.selectedText : root.foreground
                font.family: root.fontFamily
                font.pixelSize: root.metaFont
                font.letterSpacing: 1.0
                font.weight: tabSettings.active ? Font.DemiBold : Font.Normal
              }

              MouseArea {
                id: tabSettingsArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.helpTab = "settings"
              }
            }
          }

          // ---- page: settings ----
          Column {
            visible: root.helpTab === "settings"
            width: parent.width
            spacing: Style.space(8)

            // The panel owns the keyboard, so a field claims focus explicitly
            // when the page opens: the key field until one is saved.
            onVisibleChanged: if (visible && root.helpOpen) Qt.callLater(function() {
              if (!root.apiConfigured) keyField.input.forceActiveFocus()
            })

            Row {
              spacing: Style.space(8)

              SettingsLabel { text: "PODCAST INDEX"; anchors.verticalCenter: parent.verticalCenter }

              Text {
                textFormat: Text.PlainText
                text: root.apiConfigured ? "\u{F012C} connected" : "not connected"
                color: root.apiConfigured ? Color.accent : root.hintLabel
                font.family: root.fontFamily
                font.pixelSize: root.metaFont
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Row {
              spacing: Style.space(7)

              SettingsField {
                id: keyField
                width: Style.space(220)
                placeholder: root.apiConfigured ? "New API key" : "API key"
                text: root.keyDraft
                onEdited: function(value) { root.keyDraft = value }
                onSubmitted: secretField.input.forceActiveFocus()
              }

              SettingsField {
                id: secretField
                width: Style.space(300)
                placeholder: "API secret"
                secret: true
                text: root.secretDraft
                onEdited: function(value) { root.secretDraft = value }
                onSubmitted: root.saveCredentials()
              }

              Rectangle {
                width: saveLabel.implicitWidth + Style.space(18)
                height: Style.space(26)
                radius: Style.space(5)
                readonly property bool ready: root.keyDraft.trim() !== "" && root.secretDraft.trim() !== ""
                color: ready ? root.keycapAccentFill : root.keycapFill
                border.width: 1
                border.color: ready ? root.keycapAccentBorder : root.keycapBorder
                opacity: ready ? 1 : 0.6

                Text {
                  id: saveLabel
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: authSetProc.running ? "Saving…" : "Save"
                  color: root.keycapText
                  font.family: root.fontFamily
                  font.pixelSize: root.metaFont
                  font.weight: Font.DemiBold
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: if (parent.ready) root.saveCredentials()
                }
              }
            }

            Row {
              spacing: Style.space(4)

              Text {
                textFormat: Text.PlainText
                text: root.settingsMessage || "Free key, no card: sign up at"
                color: root.settingsError ? "#d04860" : root.hintLabel
                font.family: root.fontFamily
                font.pixelSize: root.metaFont
              }

              Text {
                visible: !root.settingsMessage
                textFormat: Text.PlainText
                text: "api.podcastindex.org"
                color: Color.accent
                font.family: root.fontFamily
                font.pixelSize: root.metaFont
                font.underline: signupArea.containsMouse

                MouseArea {
                  id: signupArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: Quickshell.execDetached(["xdg-open", "https://api.podcastindex.org/signup"])
                }
              }

              Text {
                visible: !root.settingsMessage
                textFormat: Text.PlainText
                text: "· stored only on this machine"
                color: root.hintLabel
                font.family: root.fontFamily
                font.pixelSize: root.metaFont
              }
            }

            Item { width: 1; height: Style.space(4) }

            SettingsLabel { text: "TRENDING LANGUAGE" }

            Row {
              spacing: Style.space(7)

              SettingsField {
                id: languageField
                width: Style.space(90)
                placeholder: "any"
                text: root.language
                onSubmitted: root.saveLanguage(text)
                onFocusLost: root.saveLanguage(text)
              }

              Text {
                textFormat: Text.PlainText
                text: "Language code such as en or de, several with commas. Empty shows every language."
                color: root.hintLabel
                font.family: root.fontFamily
                font.pixelSize: root.metaFont
                anchors.verticalCenter: parent.verticalCenter
              }
            }
          }

          // ---- page: shortcuts ----
          Row {
            visible: root.helpTab === "shortcuts"
            spacing: Style.space(20)

            ShortcutGroup {
              title: "NAVIGATE"
              rows: [
                { keys: ["Ctrl+J", "Ctrl+K"], label: "move" },
                { keys: ["Tab", "Shift+Tab"], label: "switch view" },
                { keys: ["Ctrl+1–3"], label: "pick a view" },
                { keys: ["Esc"], label: "back, then close" }
              ]
            }

            ShortcutGroup {
              title: "LISTEN"
              rows: [
                { keys: ["Enter"], label: "open show / play" },
                { keys: ["Shift+Enter"], label: "play from start" },
                { keys: ["Ctrl+Space"], label: "pause / resume" },
                { keys: ["Ctrl+←", "Ctrl+→"], label: "back 15 s / ahead 30 s" }
              ]
            }

            ShortcutGroup {
              title: "LIBRARY"
              rows: [
                { keys: ["Ctrl+P"], label: "subscribe / unsubscribe" },
                { keys: ["Delete", "Ctrl+D"], label: "remove from view" },
                { keys: ["Ctrl+S"], label: "stop playback" },
                { keys: ["Backspace"], label: "leave a show" }
              ]
            }

            ShortcutGroup {
              title: "PANEL"
              rows: [
                { keys: ["?"], label: "this reference" },
                { keys: ["Ctrl+,"], label: "settings" },
                { keys: ["Ctrl+O"], label: "detail pane" },
                { keys: ["Ctrl+."], label: "actions menu" }
              ]
            }
          }
        }
      }

      // ---- actions overlay ----
      Rectangle {
        anchors.fill: parent
        visible: root.actionsOpen
        radius: root.cornerRadius
        color: Util.alpha(root.background, 0.35)
      }

      BorderSurface {
        visible: root.actionsOpen
        anchors.centerIn: parent
        width: Math.min(Style.space(560), card.width - Style.space(40))
        height: Math.min(Style.space(520), card.height - Style.space(40))
        radius: root.cornerRadius
        color: root.background
        borderSpec: root.borderSpec
        padding: root.contentMargin

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
          anchors.fill: parent
          anchors.topMargin: parent.contentTopInset
          anchors.rightMargin: parent.contentRightInset
          anchors.bottomMargin: parent.contentBottomInset
          anchors.leftMargin: parent.contentLeftInset
          spacing: root.contentSpacing

          Text {
            id: actionsHeading
            textFormat: Text.PlainText
            text: "Actions"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
          }

          Rectangle {
            id: actionSearchBox
            width: parent.width
            height: Style.space(42)
            radius: root.cornerRadius
            color: Util.alpha(root.border, 0.08)

            Text {
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.leftMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              text: root.actionFilter || "Search actions…"
              color: root.foreground
              opacity: root.actionFilter ? 1 : 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
            }
          }

          ListView {
            id: actionsList
            width: parent.width
            height: parent.height - actionsHeading.height - actionSearchBox.height - root.contentSpacing * 2
            model: actionsModel
            clip: true
            spacing: Style.space(4)
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
              id: actionRow
              required property int index
              required property string actionId
              required property string label
              required property string hint

              readonly property bool hasCursor: index === root.actionIndex

              width: ListView.view.width
              height: Style.space(46)
              radius: root.cornerRadius
              color: hasCursor ? root.selectedBackground : "transparent"

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(22)
                anchors.right: actionHint.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: actionRow.label
                color: actionRow.hasCursor ? root.selectedText : (actionRow.actionId === "stop" ? "#d04860" : root.foreground)
                font.family: root.fontFamily
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
                color: actionRow.hasCursor ? root.selectedText : root.foreground
                opacity: 0.5
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: function(mouse) {
                  if (!pointerGate.moved(actionRow, mouse)) return
                  root.actionIndex = actionRow.index
                }
                onClicked: root.runActionIndex(actionRow.index)
              }
            }
          }
        }
      }
    }
  }
}
