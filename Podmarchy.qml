import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "PodmarchyModel.js" as Model
import "components"

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
  property string savedKeyMask: ""
  property string savedSecretMask: ""
  property string settingsMessage: ""
  property bool settingsError: false

  property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/podmarchy"
  property string runtimeDir: {
    var run = Quickshell.env("XDG_RUNTIME_DIR")
    if (!run) {
      console.warn("Podmarchy: XDG_RUNTIME_DIR is not set; playback may not work")
      run = "/tmp"
    }
    return run + "/podmarchy"
  }
  property string subscriptionsPath: stateDir + "/subscriptions.json"
  property string progressPath: stateDir + "/progress.json"
  property string settingsPath: stateDir + "/settings.json"
  property string credentialsPath: stateDir + "/credentials.json"
  property string statusPath: runtimeDir + "/status.json"
  property string apiScript: Qt.resolvedUrl("podmarchy-api").toString().replace(/^file:\/\//, "")
  property string playerScript: Qt.resolvedUrl("podmarchy-player").toString().replace(/^file:\/\//, "")
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
    { id: "library", label: "Library", glyph: "\u{F02CB}", tip: "Shows you subscribe to  (1)" },
    { id: "discover", label: "Discover", glyph: "\u{F018B}", tip: "Find new shows: what is trending, or type to search  (2)" },
    { id: "continue", label: "Continue", glyph: "\u{F02DA}", tip: "Episodes you started but have not finished  (3)" }
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

  function isHttpUrl(value) {
    var s = String(value || "")
    return /^https?:\/\//i.test(s) && !/[\r\n]/.test(s)
  }

  function ensureVisible(idx) {
    if (resultList.count > 0) resultList.positionViewAtIndex(idx, ListView.Contain)
  }

  function select(delta) {
    if (root.rows.length === 0) return
    root.lastKeyboardMove = Date.now()
    root.hoverAllowed = false
    hoverTimer.restart()
    var wasActive = root.cursorActive
    root.cursorActive = true
    var idx = !wasActive ? (delta < 0 ? root.rows.length - 1 : 0)
                         : (root.selectedIndex + delta + root.rows.length) % root.rows.length
    root.selectedIndex = idx
    root.ensureVisible(idx)
  }

  property bool hoverAllowed: true

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
    root.toggleSubscribeShow(root.subscribeTarget())
  }

  function toggleSubscribeShow(target) {
    if (!target) return
    root.subscriptions = Model.toggleSubscription(root.subscriptions, target)
    root.saveSubscriptions()
    root.refreshRowsInPlace()
  }

  // The show Ctrl+P would act on, or null.
  function subscribeTarget() {
    var row = root.currentRow()
    if (row && row.rowType === "show") return row
    return root.openShow
  }

  // Footer hints double as buttons.
  function runHint(id) {
    if (id === "open" || id === "play") root.activate(root.currentRow(), false)
    else if (id === "subscribe") root.toggleSubscribe()
    else if (id === "pause") root.player(["toggle"])
    else if (id === "actions") root.openActions()
    else if (id === "keys") root.openHelp("shortcuts")
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

  function maskCredential(value) {
    var s = String(value || "")
    if (s.length <= 8) return "••••••••"
    return s.slice(0, 4) + "••••" + s.slice(-4)
  }

  function loadCredentialsMask(raw) {
    try {
      var c = JSON.parse(String(raw || "{}"))
      root.savedKeyMask = c.key ? root.maskCredential(c.key) : ""
      root.savedSecretMask = c.secret ? "••••••••" : ""
    } catch (e) {
      root.savedKeyMask = ""
      root.savedSecretMask = ""
    }
  }

  function loadSettings(raw) {
    try {
      var s = JSON.parse(String(raw || "{}"))
      if (s && typeof s.language === "string") root.language = s.language
    } catch (e) {}
  }

  function focusSearch() {
    searchField.focus = true
  }

  function blurSearch() {
    searchField.focus = false
    keyCatcher.forceActiveFocus()
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
      add("subscribe", row.subscribed ? "Unsubscribe" : "Subscribe", "s")
      if (root.isHttpUrl(row.link)) add("website", "Open website", "")
      if (root.isHttpUrl(row.url)) add("copyfeed", "Copy feed URL", "")
    } else if (row) {
      var live = root.playing && String(root.nowEpisode.id) === String(row.id)
      add("play", live ? (root.status.paused ? "Resume" : "Pause")
                       : (row.state === "progress" ? "Resume" : "Play"), "Enter")
      if (row.position > 0 || live) add("restart", "Play from the start", "Shift+Enter")
      add(row.done ? "unplayed" : "played", row.done ? "Mark as unplayed" : "Mark as played", "")
      if (root.openShow) add("subscribe", Model.isSubscribed(root.subscriptions, root.openShow.id) ? "Unsubscribe from show" : "Subscribe to show", "s")
      if (root.isHttpUrl(row.link)) add("website", "Open episode page", "")
      if (root.isHttpUrl(row.url)) add("copyaudio", "Copy audio URL", "")
    }
    if (root.playing) add("stop", "Stop playback", "q")
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
    else if (id === "website" && row && root.isHttpUrl(row.link)) Quickshell.execDetached(["xdg-open", row.link])
    else if (id === "copyfeed" && row && root.isHttpUrl(row.url)) Quickshell.execDetached(["wl-copy", "--", row.url])
    else if (id === "copyaudio" && row && root.isHttpUrl(row.url)) Quickshell.execDetached(["wl-copy", "--", row.url])
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

  FileView {
    id: credentialsReader
    path: root.credentialsPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadCredentialsMask(text())
    onLoadFailed: root.loadCredentialsMask("")
    onFileChanged: reload()
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
    onExited: function(exitCode, exitStatus) {
      var reply = {}
      try { reply = JSON.parse(authSetProc.output || "{}") } catch (e) {}
      if (exitCode === 0) {
        root.apiConfigured = true
        root.settingsError = false
        root.settingsMessage = "Saved. Podmarchy is connected to Podcast Index."
        root.keyDraft = ""
        root.secretDraft = ""
        credentialsReader.reload()
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

  Timer {
    id: hoverTimer
    interval: 700
    repeat: false
    onTriggered: root.hoverAllowed = true
  }

  // ---- shared components ----

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
            else if (event.key === Qt.Key_Up) { if (n > 0) root.actionIndex = (root.actionIndex - 1 + n) % n }
            else if (event.key === Qt.Key_Down) { if (n > 0) root.actionIndex = (root.actionIndex + 1) % n }
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.runActionIndex(root.actionIndex)
            else if (event.key === Qt.Key_Backspace) { root.actionFilter = root.actionFilter.slice(0, -1); root.rebuildActions() }
            else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
              root.actionFilter += event.text
              root.actionIndex = 0
              root.rebuildActions()
            } else return
            event.accepted = true
            Qt.callLater(function() { actionsOverlay.scrollTo(root.actionIndex) })
            return
          }

          // ---- main keys ----
          if (event.key === Qt.Key_Escape) {
            if (root.helpOpen) root.helpOpen = false
            else if (searchField.focus) root.blurSearch()
            else if (root.filterText) root.setFilter("")
            else if (!root.back()) root.close()
          } else if (event.key === Qt.Key_Question || (event.key === Qt.Key_Slash && ctrl)) {
            root.openHelp("shortcuts")
          } else if (event.key === Qt.Key_Comma || (event.key === Qt.Key_Comma && ctrl)) {
            root.openHelp("settings")
          } else if (event.key === Qt.Key_Period || (event.key === Qt.Key_Period && ctrl)) {
            root.openActions()
          } else if (event.key === Qt.Key_O || (event.key === Qt.Key_O && ctrl)) {
            root.previewOpen = !root.previewOpen
          } else if (event.key === Qt.Key_Slash) {
            root.focusSearch()
          } else if (event.key === Qt.Key_Space && !searchField.focus) {
            if (root.playing) root.player(["toggle"])
            else if (root.cursorActive) root.activate(root.currentRow(), shift)
            else if (root.rows.length > 0) root.cursorActive = true
          } else if (event.key === Qt.Key_K && !ctrl || event.key === Qt.Key_MediaTogglePlayPause) {
            root.player(["toggle"])
          } else if (event.key === Qt.Key_J && !ctrl) {
            root.player(["seek", "-10"])
          } else if (event.key === Qt.Key_L && !ctrl) {
            root.player(["seek", "30"])
          } else if (event.key === Qt.Key_Left) {
            root.player(["seek", "-15"])
          } else if (event.key === Qt.Key_Right) {
            root.player(["seek", "30"])
          } else if (event.key === Qt.Key_Q || event.key === Qt.Key_MediaStop) {
            root.player(["stop"])
          } else if (event.key === Qt.Key_S) {
            root.toggleSubscribe()
          } else if (event.key === Qt.Key_D || event.key === Qt.Key_Delete) {
            root.removeSelected()
          } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_3) {
            root.setView(root.views[event.key - Qt.Key_1].id)
          } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab || (event.key === Qt.Key_H && ctrl) || (event.key === Qt.Key_L && ctrl)) {
            root.cycleView(event.key === Qt.Key_Backtab || event.key === Qt.Key_H ? -1 : 1)
          } else if (event.key === Qt.Key_Backspace && !root.filterText && root.openShow) {
            // Backspace on an empty search steps out of a show, like a file browser.
            root.back()
          } else if (event.key === Qt.Key_Up || (event.key === Qt.Key_K && ctrl)) {
            root.select(-1)
          } else if (event.key === Qt.Key_Down || (event.key === Qt.Key_J && ctrl)) {
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

            PanelToolTip { visible: backArea.containsMouse; text: "Back to the list of shows  (Esc or Backspace)" }
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
            border.color: searchField.focus ? Util.alpha(Color.accent, 0.55) : Util.alpha(root.foreground, 0.10)
            Behavior on border.color { ColorAnimation { duration: 120 } }

            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
              var ctrl = event.modifiers & Qt.ControlModifier
              if (event.key === Qt.Key_Escape) {
                root.blurSearch()
                event.accepted = true
              } else if (event.key === Qt.Key_Up || (event.key === Qt.Key_K && ctrl)) {
                root.select(-1)
                event.accepted = true
              } else if (event.key === Qt.Key_Down || (event.key === Qt.Key_J && ctrl)) {
                root.select(1)
                event.accepted = true
              } else if (event.key === Qt.Key_H && ctrl) {
                root.cycleView(-1)
                event.accepted = true
              } else if (event.key === Qt.Key_L && ctrl) {
                root.cycleView(1)
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (root.cursorActive) root.activate(root.currentRow(), shift)
                else if (root.rows.length > 0) root.cursorActive = true
                event.accepted = true
              } else if (Util.editsFilter(event, root.filterText)) {
                root.setFilter(Util.editedFilter(event, root.filterText))
                event.accepted = true
              } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
                root.setFilter(root.filterText + event.text)
                event.accepted = true
              }
            }

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

            // Typing caret. It only blinks when the search field explicitly
            // has focus, so single-letter playback keys (j/k/l) work elsewhere.
            Rectangle {
              id: caret
              readonly property bool focused: searchField.focus
              visible: focused
              width: 1.5
              height: Style.font.subtitle + 2
              color: Color.accent
              x: searchIcon.x + searchIcon.width + Style.space(9) + (root.filterText.length > 0 ? searchMeasure.width + 1 : 0)
              anchors.verticalCenter: parent.verticalCenter
              SequentialAnimation on opacity {
                loops: Animation.Infinite
                running: caret.focused
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

              MouseArea { id: spinnerArea; anchors.fill: parent; hoverEnabled: true }
              PanelToolTip { visible: spinnerArea.containsMouse; text: "Loading from Podcast Index…" }
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

              PanelToolTip { visible: clearArea.containsMouse; text: "Clear the search  (Esc or click)" }
            }

            MouseArea {
              anchors.fill: parent
              onClicked: root.focusSearch()
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

                  PanelToolTip { visible: chipArea.containsMouse; text: chip.modelData.tip }
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
              reuseItems: true

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

                // Heart: filled when subscribed; on show rows an outline appears
                // on hover, and clicking it subscribes or unsubscribes.
                Text {
                  id: trailing
                  readonly property bool shown: listRow.modelData.subscribed || (listRow.isShow && (listRow.hovered || heartArea.containsMouse || listRow.hasCursor))
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  width: listRow.isShow || listRow.modelData.subscribed ? Style.font.title : 0
                  horizontalAlignment: Text.AlignHCenter
                  text: listRow.modelData.subscribed ? "\u{F02D1}" : "\u{F02D5}"
                  color: Color.accent
                  opacity: !shown ? 0 : (heartArea.containsMouse ? 1 : (listRow.modelData.subscribed ? 0.7 : 0.45))
                  font.family: root.fontFamily
                  font.pixelSize: heartArea.containsMouse ? Style.font.title : Style.font.body
                  Behavior on opacity { NumberAnimation { duration: 110 } }
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

                MouseArea {
                  id: heartArea
                  visible: listRow.isShow
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  width: Style.space(40)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.toggleSubscribeShow(listRow.modelData)
                }

                PanelToolTip {
                  visible: heartArea.containsMouse
                  text: listRow.modelData.subscribed ? "Unsubscribe: remove from your Library" : "Subscribe: add to your Library"
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

                  // Subscribe button for the show in view.
                  Rectangle {
                    id: subButton
                    // A show's own pane, or an episode's pane inside an open show.
                    readonly property var show: previewPane.isShow ? previewPane.row : root.openShow
                    readonly property bool subbed: !!show && Model.isSubscribed(root.subscriptions, show.id)
                    readonly property bool hot: subArea.containsMouse
                    visible: !!show
                    width: subLabel.implicitWidth + Style.space(22)
                    height: Style.space(26)
                    radius: Style.space(6)
                    color: subbed ? (hot ? Util.alpha(root.foreground, 0.08) : "transparent")
                                  : (hot ? Util.alpha(Color.accent, 0.26) : Util.alpha(Color.accent, 0.16))
                    border.width: 1
                    border.color: subbed ? Util.alpha(root.foreground, 0.18) : Util.alpha(Color.accent, 0.5)
                    Behavior on color { ColorAnimation { duration: 110 } }

                    Text {
                      id: subLabel
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: subButton.subbed ? (subButton.hot ? "Unsubscribe" : "\u{F012C}  Subscribed") : "\u{F02D1}  Subscribe"
                      color: subButton.subbed ? root.foreground : Color.accent
                      opacity: subButton.subbed && !subButton.hot ? 0.75 : 1
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.weight: Font.DemiBold
                    }

                    MouseArea {
                      id: subArea
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.toggleSubscribeShow(subButton.show)
                    }

                    PanelToolTip {
                      visible: subArea.containsMouse
                      text: (subButton.subbed ? "Remove " : "Add ") + (previewPane.isShow ? "this show" : "“" + (subButton.show ? subButton.show.title : "") + "”")
                            + (subButton.subbed ? " from" : " to") + " your Library  (s)"
                    }
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
                  return "It is free: get a key at api.podcastindex.org, then paste it in settings (,)."
                if (root.view === "library" && !root.openShow) return "Press Tab to discover shows, then s to subscribe."
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
                id: nowGlyphArea
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.player(["toggle"])
              }

              PanelToolTip { visible: nowGlyphArea.containsMouse; text: root.status.paused ? "Carry on playing  (Space or k)" : "Pause  (Space or k)" }
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
                var list = []
                if (r && r.rowType === "show")
                  list.push({ id: "open", keys: "Enter", label: "Episodes", primary: true, tip: "See this show's episodes" })
                else if (r) {
                  var live = root.playing && String(root.nowEpisode.id) === String(r.id)
                  list.push({ id: "play", keys: "Enter", label: live ? (root.status.paused ? "Resume" : "Pause") : "Play", primary: true,
                              tip: live ? (root.status.paused ? "Carry on playing this episode" : "Pause this episode")
                                        : (r.position > 0 && !r.done ? "Play this episode from where you stopped" : "Play this episode") })
                }
                var target = root.subscribeTarget()
                if (target) {
                  var subbed = Model.isSubscribed(root.subscriptions, target.id)
                  list.push({ id: "subscribe", keys: "s", label: subbed ? "Unsubscribe" : "Subscribe",
                              tip: subbed ? "Remove this show from your Library" : "Add this show to your Library" })
                }
                if (root.playing && !(r && r.rowType === "episode" && String(root.nowEpisode.id) === String(r.id)))
                  list.push({ id: "pause", keys: "k", label: root.status.paused ? "Resume" : "Pause",
                              tip: root.status.paused ? "Carry on playing what you were listening to" : "Pause what is playing" })
                list.push({ id: "actions", keys: ".", label: "Actions", tip: "More things you can do with this item" },
                          { id: "keys", keys: "?", label: "Keys", tip: "Show all keyboard shortcuts" })
                return list
              }

              delegate: Item {
                id: hint
                required property var modelData
                width: hintRow.implicitWidth
                height: hintRow.implicitHeight

                Row {
                  id: hintRow
                  spacing: Style.space(6)
                  PodmarchyKeyCap { ctx: root; label: hint.modelData.keys; primary: !!hint.modelData.primary; anchors.verticalCenter: parent.verticalCenter }
                  Text {
                    textFormat: Text.PlainText
                    text: hint.modelData.label
                    color: hintArea.containsMouse ? root.foreground : root.hintLabel
                    font.family: root.fontFamily
                    font.pixelSize: root.metaFont
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                MouseArea {
                  id: hintArea
                  anchors.fill: parent
                  anchors.margins: -3
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.runHint(hint.modelData.id)
                }

                PanelToolTip { visible: hintArea.containsMouse; text: hint.modelData.tip }
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

            PanelToolTip {
              visible: gearArea.containsMouse
              text: root.apiConfigured ? "Settings  (,)" : "Settings: add your free Podcast Index key here  (,)"
            }
          }
        }
      }

      PodmarchyHelpPopup {
        root: root
        keyCatcher: keyCatcher
      }

      PodmarchyActionsOverlay {
        id: actionsOverlay
        root: root
        pointerGate: pointerGate
      }
    }
  }
}
