.pragma library

// Pure helpers for Podmarchy.qml: row shaping, filtering, formatting. Nothing
// here touches QML objects, so the file can be loaded and exercised by node.

const MONTHS = [
  "Jan", "Feb", "Mar", "Apr", "May", "Jun",
  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
]

const ROW_TYPES = {
  SHOW: "show",
  EPISODE: "episode"
}

const STATES = {
  PLAYING: "playing",
  PAUSED: "paused",
  PROGRESS: "progress",
  DONE: "done",
  NEW: "new"
}

/**
 * Return a blank row template. Every row carries the same keys, whether it is a
 * show or an episode, so the list delegate can bind to any of them without
 * undefined checks.
 */
function blankRow() {
  return {
    rowType: ROW_TYPES.SHOW,
    id: "",
    feedId: "",
    title: "",
    author: "",
    show: "",
    image: "",
    description: "",
    url: "",
    link: "",
    language: "",
    categories: "",
    episodeCount: 0,
    newest: 0,
    date: 0,
    duration: 0,
    position: 0,
    done: false,
    subscribed: false,
    state: STATES.NEW
  }
}

function toString(value) {
  return String(value || "")
}

function toNumber(value) {
  const n = Number(value)
  return Number.isFinite(n) ? n : 0
}

/**
 * Case-insensitive substring search across an array of fields.
 * @param {string} needle
 * @param {Array<*>} fields
 * @returns {boolean}
 */
function matches(needle, fields) {
  if (!needle) return true
  const n = toString(needle).toLowerCase()
  if (!Array.isArray(fields)) return false
  for (let i = 0; i < fields.length; i++) {
    if (toString(fields[i]).toLowerCase().indexOf(n) >= 0) return true
  }
  return false
}

/**
 * Build a Set of subscribed feed ids from a subscriptions array. The Set can be
 * passed to isSubscribed() to avoid rebuilding it on every check.
 * @param {Array<{id: *}>|Set<string>|null|undefined} subs
 * @returns {Set<string>}
 */
function subscribedSet(subs) {
  if (!subs) return new Set()
  if (subs instanceof Set) return subs
  if (!Array.isArray(subs)) return new Set()
  const ids = new Set()
  for (let i = 0; i < subs.length; i++) {
    const s = subs[i]
    if (s && s.id != null) ids.add(toString(s.id))
  }
  return ids
}

/**
 * @param {Array<{id: *}>|Set<string>} subs
 * @param {string|number} feedId
 * @returns {boolean}
 */
function isSubscribed(subs, feedId) {
  return subscribedSet(subs).has(toString(feedId))
}

function showRow(feed, subscribed) {
  const row = blankRow()
  row.rowType = ROW_TYPES.SHOW
  row.id = toString(feed.id)
  row.feedId = row.id
  row.title = toString(feed.title) || "Untitled podcast"
  row.author = toString(feed.author)
  row.image = toString(feed.image)
  row.description = toString(feed.description)
  row.url = toString(feed.url)
  row.link = toString(feed.link)
  row.language = toString(feed.language)
  row.categories = toString(feed.categories)
  row.episodeCount = toNumber(feed.episodeCount)
  row.newest = toNumber(feed.newest)
  row.subscribed = !!subscribed
  return row
}

function showRows(feeds, subs, needle) {
  const ids = subscribedSet(subs)
  const rows = []
  for (let i = 0; i < (feeds || []).length; i++) {
    const f = feeds[i]
    if (!f) continue
    if (!matches(needle, [f.title, f.author, f.categories])) continue
    rows.push(showRow(f, ids.has(toString(f.id))))
  }
  return rows
}

/**
 * Determine episode state: "playing", "paused", "progress" (started, not
 * finished), "done" or "new".
 * @param {string|number} id
 * @param {Object} progress
 * @param {Object} status
 * @returns {string}
 */
function episodeState(id, progress, status) {
  const key = toString(id)
  if (status && status.running && status.episode && toString(status.episode.id) === key) {
    return status.paused ? STATES.PAUSED : STATES.PLAYING
  }
  const p = progress ? progress[key] : null
  if (p && p.done) return STATES.DONE
  if (p && p.position > 0) return STATES.PROGRESS
  return STATES.NEW
}

function episodeRow(item, show, progress, status) {
  const row = blankRow()
  const key = toString(item.id)
  const p = progress ? progress[key] : null
  row.rowType = ROW_TYPES.EPISODE
  row.id = key
  row.feedId = toString(item.feedId || (show && show.id))
  row.title = toString(item.title) || "Untitled episode"
  row.show = toString((show && show.title) || item.show)
  row.author = toString((show && show.author) || item.author)
  row.image = toString(item.image || (show && show.image))
  row.description = toString(item.description)
  row.url = toString(item.url)
  row.link = toString(item.link)
  row.date = toNumber(item.date)
  row.duration = toNumber(item.duration) || (p ? toNumber(p.duration) : 0)
  row.position = p ? toNumber(p.position) : 0
  row.done = !!(p && p.done)
  row.state = episodeState(row.id, progress, status)

  // The live position beats the saved one while this episode is playing.
  if ((row.state === STATES.PLAYING || row.state === STATES.PAUSED) && status) {
    row.position = toNumber(status.position) || row.position
    if (toNumber(status.duration) > 0) row.duration = toNumber(status.duration)
  }
  return row
}

function episodeRows(items, show, progress, status, needle) {
  const rows = []
  for (let i = 0; i < (items || []).length; i++) {
    const it = items[i]
    if (!it) continue
    if (!matches(needle, [it.title, it.description])) continue
    rows.push(episodeRow(it, show, progress, status))
  }
  return rows
}

/**
 * Episodes started but not finished, most recently heard first. The playing
 * episode is always listed, even before its first progress save.
 * @param {Object} progress
 * @param {Object} status
 * @param {string} needle
 * @returns {Array<Object>}
 */
function continueRows(progress, status, needle) {
  const entries = []
  const seen = new Set()
  const playing = status && status.running && status.episode && status.episode.id
  if (playing) {
    const e = status.episode
    entries.push({
      id: toString(e.id),
      feedId: e.feedId,
      title: e.title,
      show: e.show,
      image: e.image,
      url: e.url,
      updated: Infinity
    })
    seen.add(toString(e.id))
  }

  for (const id in (progress || {})) {
    if (!Object.prototype.hasOwnProperty.call(progress, id)) continue
    const p = progress[id]
    if (!p || p.done || seen.has(id)) continue
    entries.push({
      id: id,
      feedId: p.feedId,
      title: p.title,
      show: p.show,
      image: p.image,
      url: p.url,
      updated: toNumber(p.updated)
    })
  }

  entries.sort(function(a, b) { return b.updated - a.updated })

  const rows = []
  for (let i = 0; i < entries.length; i++) {
    const en = entries[i]
    if (!matches(needle, [en.title, en.show])) continue
    rows.push(episodeRow(en, { title: en.show, image: en.image, id: en.feedId }, progress, status))
  }
  return rows
}

function toggleSubscription(subs, show) {
  const id = toString(show.id || show.feedId)
  const next = []
  let removed = false
  for (let i = 0; i < (subs || []).length; i++) {
    const s = subs[i]
    if (!s) continue
    if (toString(s.id) === id) {
      removed = true
      continue
    }
    next.push(s)
  }
  if (!removed) {
    next.push({
      id: id,
      title: toString(show.title),
      author: toString(show.author),
      image: toString(show.image),
      description: toString(show.description),
      url: toString(show.url),
      link: toString(show.link),
      language: toString(show.language),
      categories: toString(show.categories),
      episodeCount: toNumber(show.episodeCount),
      newest: toNumber(show.newest),
      addedAt: new Date().toISOString()
    })
  }
  next.sort(function(a, b) { return toString(a.title).localeCompare(toString(b.title)) })
  return next
}

function parseSubscriptions(raw) {
  try {
    const parsed = JSON.parse(toString(raw || "[]"))
    if (!Array.isArray(parsed)) return []
    return parsed.filter(function(s) {
      return s && typeof s === "object" && /^[0-9]+$/.test(toString(s.id))
    })
  } catch (e) {
    return []
  }
}

function parseProgress(raw) {
  try {
    const parsed = JSON.parse(toString(raw || "{}"))
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {}
  } catch (e) {
    return {}
  }
}

function markDone(progress, row, done) {
  const next = Object.assign({}, progress || {})
  const key = toString(row.id)
  if (!done) {
    delete next[key]
    return next
  }
  next[key] = {
    position: 0,
    duration: toNumber(row.duration),
    done: true,
    updated: Math.floor(Date.now() / 1000),
    feedId: row.feedId,
    title: row.title,
    show: row.show,
    image: row.image,
    url: row.url
  }
  return next
}

function xmlEscape(s) {
  return toString(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;")
}

function opml(subs) {
  const lines = [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<opml version="2.0">',
    '  <head><title>Podmarchy subscriptions</title></head>',
    '  <body>'
  ]
  for (let i = 0; i < (subs || []).length; i++) {
    const s = subs[i]
    if (!s || !s.url) continue
    const title = xmlEscape(s.title)
    const url = xmlEscape(s.url)
    const html = s.link ? ` htmlUrl="${xmlEscape(s.link)}"` : ""
    lines.push(`    <outline type="rss" text="${title}" title="${title}" xmlUrl="${url}"${html}/>`)
  }
  lines.push('  </body>', '</opml>')
  return lines.join("\n") + "\n"
}

/**
 * Format seconds as a clock readout: 754 -> "12:34", 3754 -> "1:02:34".
 * @param {number} seconds
 * @returns {string}
 */
function clock(seconds) {
  const s = Math.max(0, Math.floor(toNumber(seconds)))
  const h = Math.floor(s / 3600)
  const m = Math.floor((s % 3600) / 60)
  const sec = s % 60
  const mm = h > 0 && m < 10 ? "0" + m : String(m)
  return (h > 0 ? h + ":" : "") + mm + ":" + (sec < 10 ? "0" + sec : sec)
}

/**
 * Format a duration in words: 2520 -> "42 min", 3900 -> "1 h 5 min".
 * @param {number} seconds
 * @returns {string}
 */
function duration(seconds) {
  const s = Math.floor(toNumber(seconds))
  if (s <= 0) return ""
  const m = Math.max(1, Math.round(s / 60))
  if (m < 60) return m + " min"
  const h = Math.floor(m / 60)
  const rest = m % 60
  return h + " h" + (rest ? " " + rest + " min" : "")
}

function remaining(position, total) {
  const left = toNumber(total) - toNumber(position)
  if (!(toNumber(total) > 0) || left <= 0) return ""
  return duration(left) + " left"
}

/**
 * Convert Unix seconds to a friendly day label.
 * @param {number} unixSeconds
 * @param {number} nowMs
 * @returns {string}
 */
function day(unixSeconds, nowMs) {
  const t = toNumber(unixSeconds)
  if (t <= 0) return ""
  const d = new Date(t * 1000)
  const now = new Date(nowMs || Date.now())
  const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
  const startOfDay = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
  const diffDays = Math.floor((startOfToday - startOfDay) / 86400000)
  if (diffDays <= 0) return "Today"
  if (diffDays === 1) return "Yesterday"
  if (diffDays < 7) return diffDays + " days ago"
  const label = MONTHS[d.getMonth()] + " " + d.getDate()
  return d.getFullYear() === now.getFullYear() ? label : label + ", " + d.getFullYear()
}

function stateLabel(state) {
  switch (state) {
    case STATES.PLAYING: return "Playing"
    case STATES.PAUSED: return "Paused"
    case STATES.PROGRESS: return "In progress"
    case STATES.DONE: return "Played"
    default: return "Episode"
  }
}

/**
 * Build the JSON payload for podmarchy-player play.
 * @param {Object} row
 * @param {boolean} fromStart
 * @returns {string}
 */
function playPayload(row, fromStart) {
  const start = fromStart || row.done ? 0 : Math.max(0, Math.floor(toNumber(row.position)) - 3)
  return JSON.stringify({
    id: row.id,
    feedId: row.feedId,
    title: row.title,
    show: row.show,
    image: row.image,
    url: row.url,
    start: start
  })
}

if (typeof module !== "undefined") {
  module.exports = {
    blankRow: blankRow,
    matches: matches,
    subscribedSet: subscribedSet,
    isSubscribed: isSubscribed,
    showRow: showRow,
    showRows: showRows,
    episodeState: episodeState,
    episodeRow: episodeRow,
    episodeRows: episodeRows,
    continueRows: continueRows,
    toggleSubscription: toggleSubscription,
    parseSubscriptions: parseSubscriptions,
    parseProgress: parseProgress,
    markDone: markDone,
    xmlEscape: xmlEscape,
    opml: opml,
    clock: clock,
    duration: duration,
    remaining: remaining,
    day: day,
    stateLabel: stateLabel,
    playPayload: playPayload
  }
}
