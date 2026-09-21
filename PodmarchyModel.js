.pragma library

// Pure helpers for Podmarchy.qml: row shaping, filtering, formatting. Nothing
// here touches QML objects, so the file can be loaded and exercised by node.

// Every row carries the same keys, whether it is a show or an episode, so the
// list delegate can bind to any of them without undefined checks.
function blankRow() {
  return {
    rowType: "show", id: "", feedId: "", title: "", author: "", show: "",
    image: "", description: "", url: "", link: "", language: "", categories: "",
    episodeCount: 0, newest: 0, date: 0, duration: 0, position: 0,
    done: false, subscribed: false, state: "new"
  }
}

function matches(needle, fields) {
  if (!needle) return true
  var n = String(needle).toLowerCase()
  for (var i = 0; i < fields.length; i++) {
    if (String(fields[i] || "").toLowerCase().indexOf(n) >= 0) return true
  }
  return false
}

function subscribedIds(subs) {
  var ids = {}
  for (var i = 0; i < (subs || []).length; i++) ids[String(subs[i].id)] = true
  return ids
}

function isSubscribed(subs, feedId) {
  return !!subscribedIds(subs)[String(feedId)]
}

function showRow(feed, subscribed) {
  var row = blankRow()
  row.rowType = "show"
  row.id = String(feed.id || "")
  row.feedId = row.id
  row.title = String(feed.title || "Untitled podcast")
  row.author = String(feed.author || "")
  row.image = String(feed.image || "")
  row.description = String(feed.description || "")
  row.url = String(feed.url || "")
  row.link = String(feed.link || "")
  row.language = String(feed.language || "")
  row.categories = String(feed.categories || "")
  row.episodeCount = Number(feed.episodeCount) || 0
  row.newest = Number(feed.newest) || 0
  row.subscribed = !!subscribed
  return row
}

function showRows(feeds, subs, needle) {
  var ids = subscribedIds(subs)
  var rows = []
  for (var i = 0; i < (feeds || []).length; i++) {
    var f = feeds[i]
    if (!matches(needle, [f.title, f.author, f.categories])) continue
    rows.push(showRow(f, ids[String(f.id)]))
  }
  return rows
}

// "playing", "paused", "progress" (started, not finished), "done" or "new".
function episodeState(id, progress, status) {
  var key = String(id)
  if (status && status.running && status.episode && String(status.episode.id) === key)
    return status.paused ? "paused" : "playing"
  var p = progress ? progress[key] : null
  if (p && p.done) return "done"
  if (p && p.position > 0) return "progress"
  return "new"
}

function episodeRow(item, show, progress, status) {
  var row = blankRow()
  var p = progress ? progress[String(item.id)] : null
  row.rowType = "episode"
  row.id = String(item.id || "")
  row.feedId = String(item.feedId || (show && show.id) || "")
  row.title = String(item.title || "Untitled episode")
  row.show = String((show && show.title) || item.show || "")
  row.author = String((show && show.author) || "")
  row.image = String(item.image || (show && show.image) || "")
  row.description = String(item.description || "")
  row.url = String(item.url || "")
  row.link = String(item.link || "")
  row.date = Number(item.date) || 0
  row.duration = Number(item.duration) || (p ? Number(p.duration) || 0 : 0)
  row.position = p ? Number(p.position) || 0 : 0
  row.done = !!(p && p.done)
  row.state = episodeState(row.id, progress, status)
  // The live position beats the saved one while this episode is playing.
  if ((row.state === "playing" || row.state === "paused") && status) {
    row.position = Number(status.position) || row.position
    if (Number(status.duration) > 0) row.duration = Number(status.duration)
  }
  return row
}

function episodeRows(items, show, progress, status, needle) {
  var rows = []
  for (var i = 0; i < (items || []).length; i++) {
    var it = items[i]
    if (!matches(needle, [it.title, it.description])) continue
    rows.push(episodeRow(it, show, progress, status))
  }
  return rows
}

// Episodes started but not finished, most recently heard first. The playing
// episode is always listed, even before its first progress save.
function continueRows(progress, status, needle) {
  var entries = []
  var seen = {}
  var playing = status && status.running && status.episode && status.episode.id
  if (playing) {
    var e = status.episode
    entries.push({ id: String(e.id), feedId: e.feedId, title: e.title, show: e.show,
                   image: e.image, url: e.url, updated: Infinity })
    seen[String(e.id)] = true
  }
  for (var id in (progress || {})) {
    var p = progress[id]
    if (!p || p.done || seen[id]) continue
    entries.push({ id: id, feedId: p.feedId, title: p.title, show: p.show,
                   image: p.image, url: p.url, updated: Number(p.updated) || 0 })
  }
  entries.sort(function(a, b) { return b.updated - a.updated })

  var rows = []
  for (var i = 0; i < entries.length; i++) {
    var en = entries[i]
    if (!matches(needle, [en.title, en.show])) continue
    rows.push(episodeRow(en, { title: en.show, image: en.image, id: en.feedId }, progress, status))
  }
  return rows
}

function toggleSubscription(subs, show) {
  var id = String(show.id || show.feedId)
  var next = []
  var removed = false
  for (var i = 0; i < (subs || []).length; i++) {
    if (String(subs[i].id) === id) { removed = true; continue }
    next.push(subs[i])
  }
  if (!removed) {
    next.push({
      id: id, title: show.title || "", author: show.author || "", image: show.image || "",
      description: show.description || "", url: show.url || "", link: show.link || "",
      language: show.language || "", categories: show.categories || "",
      episodeCount: show.episodeCount || 0, newest: show.newest || 0,
      addedAt: new Date().toISOString()
    })
  }
  next.sort(function(a, b) { return String(a.title).localeCompare(String(b.title)) })
  return next
}

function parseSubscriptions(raw) {
  try {
    var parsed = JSON.parse(String(raw || "[]"))
    if (!Array.isArray(parsed)) return []
    return parsed.filter(function(s) { return s && /^[0-9]+$/.test(String(s.id)) })
  } catch (e) {
    return []
  }
}

function parseProgress(raw) {
  try {
    var parsed = JSON.parse(String(raw || "{}"))
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {}
  } catch (e) {
    return {}
  }
}

function markDone(progress, row, done) {
  var next = {}
  for (var k in (progress || {})) next[k] = progress[k]
  var key = String(row.id)
  if (!done) {
    delete next[key]
    return next
  }
  next[key] = {
    position: 0, duration: Number(row.duration) || 0, done: true,
    updated: Math.floor(Date.now() / 1000), feedId: row.feedId, title: row.title,
    show: row.show, image: row.image, url: row.url
  }
  return next
}

function xmlEscape(s) {
  return String(s || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;").replace(/'/g, "&apos;")
}

function opml(subs) {
  var lines = [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<opml version="2.0">',
    '  <head><title>Podmarchy subscriptions</title></head>',
    '  <body>'
  ]
  for (var i = 0; i < (subs || []).length; i++) {
    var s = subs[i]
    if (!s.url) continue
    lines.push('    <outline type="rss" text="' + xmlEscape(s.title) + '" title="' + xmlEscape(s.title)
               + '" xmlUrl="' + xmlEscape(s.url) + '"'
               + (s.link ? ' htmlUrl="' + xmlEscape(s.link) + '"' : '') + '/>')
  }
  lines.push('  </body>', '</opml>')
  return lines.join("\n") + "\n"
}

// 754 -> "12:34", 3754 -> "1:02:34"
function clock(seconds) {
  var s = Math.max(0, Math.floor(Number(seconds) || 0))
  var h = Math.floor(s / 3600)
  var m = Math.floor((s % 3600) / 60)
  var sec = s % 60
  var mm = h > 0 && m < 10 ? "0" + m : String(m)
  return (h > 0 ? h + ":" : "") + mm + ":" + (sec < 10 ? "0" + sec : sec)
}

// 2520 -> "42 min", 3900 -> "1 h 5 min"
function duration(seconds) {
  var s = Math.floor(Number(seconds) || 0)
  if (s <= 0) return ""
  var m = Math.round(s / 60)
  if (m < 60) return Math.max(1, m) + " min"
  var h = Math.floor(m / 60)
  var rest = m % 60
  return h + " h" + (rest ? " " + rest + " min" : "")
}

function remaining(position, total) {
  var left = (Number(total) || 0) - (Number(position) || 0)
  if (!(Number(total) > 0) || left <= 0) return ""
  return duration(left) + " left"
}

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

// Unix seconds -> "Today", "Yesterday", "3 days ago", "Mar 3" or "Mar 3, 2024".
function day(unixSeconds, nowMs) {
  var t = Number(unixSeconds) || 0
  if (t <= 0) return ""
  var d = new Date(t * 1000)
  var now = new Date(nowMs || Date.now())
  var startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
  var diffDays = Math.floor((startOfToday - new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()) / 86400000)
  if (diffDays <= 0) return "Today"
  if (diffDays === 1) return "Yesterday"
  if (diffDays < 7) return diffDays + " days ago"
  var label = MONTHS[d.getMonth()] + " " + d.getDate()
  return d.getFullYear() === now.getFullYear() ? label : label + ", " + d.getFullYear()
}

function stateLabel(state) {
  switch (state) {
    case "playing": return "Playing"
    case "paused": return "Paused"
    case "progress": return "In progress"
    case "done": return "Played"
    default: return "Episode"
  }
}

// Plain JSON for podmarchy-player play.
function playPayload(row, fromStart) {
  return JSON.stringify({
    id: row.id, feedId: row.feedId, title: row.title, show: row.show,
    image: row.image, url: row.url,
    start: fromStart || row.done ? 0 : Math.max(0, Math.floor(Number(row.position) || 0) - 3)
  })
}

if (typeof module !== "undefined") module.exports = {
  blankRow: blankRow, matches: matches, isSubscribed: isSubscribed, showRow: showRow,
  showRows: showRows, episodeState: episodeState, episodeRow: episodeRow,
  episodeRows: episodeRows, continueRows: continueRows, toggleSubscription: toggleSubscription,
  parseSubscriptions: parseSubscriptions, parseProgress: parseProgress, markDone: markDone,
  xmlEscape: xmlEscape, opml: opml, clock: clock, duration: duration, remaining: remaining,
  day: day, stateLabel: stateLabel, playPayload: playPayload
}
