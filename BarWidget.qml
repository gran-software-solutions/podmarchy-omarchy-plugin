import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Podmarchy in the bar: lights up while an episode plays. Click opens the
// panel, right-click pauses or resumes, scrolling seeks.
BarWidget {
  id: root

  moduleName: "de.gransoftware.podmarchy"

  property bool running: false
  property bool paused: false
  property int position: 0
  property int duration: 0
  property string title: ""
  property string show: ""
  property bool statusReady: false
  readonly property string playerPath: Qt.resolvedUrl("podmarchy-player").toString().replace(/^file:\/\//, "")
  readonly property string statusPath: Quickshell.env("XDG_RUNTIME_DIR") + "/podmarchy/status.json"

  function clock(seconds) {
    var s = Math.max(0, Math.floor(seconds || 0))
    var h = Math.floor(s / 3600)
    var m = Math.floor((s % 3600) / 60)
    var sec = s % 60
    return (h > 0 ? h + ":" + (m < 10 ? "0" : "") : "") + m + ":" + (sec < 10 ? "0" : "") + sec
  }

  function oneLine(value, limit) {
    return String(value || "").replace(/[\r\n\t]+/g, " ").slice(0, limit).replace(/</g, "‹").replace(/>/g, "›")
  }

  function applyStatus(raw) {
    try {
      if (typeof raw !== "string" || raw.length > 65536) return
      var s = JSON.parse(raw || "{}")
      var ep = s.episode || {}
      root.running = s.running === true
      root.paused = s.paused === true
      root.position = Number(s.position) || 0
      root.duration = Number(s.duration) || 0
      root.title = root.oneLine(ep.title, 160)
      root.show = root.oneLine(ep.show, 120)
    } catch (e) {}
  }

  function player(args) {
    Quickshell.execDetached(["bash", root.playerPath].concat(args))
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  FileView {
    path: root.statusReady ? root.statusPath : ""
    watchChanges: true
    printErrors: false
    onLoaded: root.applyStatus(text())
    onFileChanged: reload()
  }

  // Creates the status file (and clears a stale one) before it is watched.
  Process {
    id: statusInit
    command: ["bash", root.playerPath, "status"]
    onExited: root.statusReady = true
  }

  Component.onCompleted: statusInit.running = true

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\u{F0994}"
    active: root.running && !root.paused
    tooltipText: root.running
      ? (root.paused ? "Paused: " : "Playing: ") + root.title
        + (root.show ? " — " + root.show : "")
        + "  ·  " + root.clock(root.position) + (root.duration > 0 ? " / " + root.clock(root.duration) : "")
      : "Open Podmarchy"

    onPressed: function(mouseButton) {
      if (!root.bar) return
      if (mouseButton === Qt.RightButton) {
        if (root.running) root.player(["toggle"])
        return
      }
      if (mouseButton === Qt.MiddleButton) {
        if (root.running) root.player(["stop"])
        return
      }
      root.bar.run("omarchy-shell shell toggle de.gransoftware.podmarchy")
    }

    onWheelMoved: function(delta) {
      if (root.running) root.player(["seek", delta > 0 ? "30" : "-15"])
    }
  }
}
