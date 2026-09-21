// node --test tests/  — exercises PodmarchyModel.js outside QML.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"

const src = readFileSync(new URL("../PodmarchyModel.js", import.meta.url), "utf8")
  .replace(/^\.pragma library\s*$/m, "")
const module = { exports: {} }
new Function("module", src)(module)
const M = module.exports

const feed = {
  id: "42",
  title: "Hard Fork",
  author: "NYT",
  image: "https://x/a.jpg",
  url: "https://feed",
  categories: "Tech, News",
  episodeCount: 3
}

test("blank row has expected defaults", () => {
  const row = M.blankRow()
  assert.equal(row.rowType, "show")
  assert.equal(row.id, "")
  assert.equal(row.state, "new")
  assert.equal(row.episodeCount, 0)
})

test("clock and duration", () => {
  assert.equal(M.clock(754), "12:34")
  assert.equal(M.clock(3754), "1:02:34")
  assert.equal(M.clock(-5), "0:00")
  assert.equal(M.clock("not a number"), "0:00")
  assert.equal(M.duration(2520), "42 min")
  assert.equal(M.duration(3900), "1 h 5 min")
  assert.equal(M.duration(0), "")
  assert.equal(M.remaining(600, 3000), "40 min left")
  assert.equal(M.remaining(3000, 3000), "")
})

test("day labels", () => {
  const now = new Date(2026, 8, 21, 12).getTime()
  const at = (y, m, d) => new Date(y, m, d, 9).getTime() / 1000
  assert.equal(M.day(at(2026, 8, 21), now), "Today")
  assert.equal(M.day(at(2026, 8, 20), now), "Yesterday")
  assert.equal(M.day(at(2026, 8, 17), now), "4 days ago")
  assert.equal(M.day(at(2026, 2, 3), now), "Mar 3")
  assert.equal(M.day(at(2024, 2, 3), now), "Mar 3, 2024")
  assert.equal(M.day(0, now), "")
})

test("matches handles missing fields", () => {
  assert.ok(M.matches("", ["anything"]))
  assert.ok(M.matches("foo", ["Foo Bar"]))
  assert.ok(!M.matches("foo", []))
  assert.ok(!M.matches("foo", null))
  assert.ok(!M.matches("foo", ["bar"]))
})

test("subscription set accepts arrays and sets", () => {
  const set = M.subscribedSet([{ id: "1" }, { id: "2" }])
  assert.ok(set instanceof Set)
  assert.ok(set.has("1"))
  assert.ok(M.isSubscribed(set, "2"))
  assert.ok(!M.isSubscribed(set, "3"))
  // Passing a set back should reuse it.
  assert.equal(M.subscribedSet(set), set)
})

test("subscribe toggles and keeps the list sorted", () => {
  let subs = M.toggleSubscription([], feed)
  assert.equal(subs.length, 1)
  assert.ok(M.isSubscribed(subs, 42))
  subs = M.toggleSubscription(subs, { id: "7", title: "Acquired" })
  assert.deepEqual(subs.map(s => s.title), ["Acquired", "Hard Fork"])
  subs = M.toggleSubscription(subs, { feedId: "42" })
  assert.deepEqual(subs.map(s => s.id), ["7"])
})

test("show rows filter and flag subscriptions", () => {
  const rows = M.showRows([feed, { id: "7", title: "Acquired" }], [{ id: "42" }], "fork")
  assert.equal(rows.length, 1)
  assert.equal(rows[0].subscribed, true)
  assert.equal(rows[0].rowType, "show")
})

test("episode state prefers the live player", () => {
  const progress = { "1": { position: 100, duration: 1000 }, "2": { done: true } }
  const status = { running: true, paused: true, position: 250, duration: 1000, episode: { id: "3" } }
  assert.equal(M.episodeState("1", progress, status), "progress")
  assert.equal(M.episodeState("2", progress, status), "done")
  assert.equal(M.episodeState("3", progress, status), "paused")
  assert.equal(M.episodeState("4", progress, status), "new")
  const row = M.episodeRow({ id: "3", title: "Live", duration: 900, url: "https://a.mp3" }, feed, progress, status)
  assert.equal(row.position, 250)
  assert.equal(row.duration, 1000)
  assert.equal(row.image, feed.image)
})

test("continue lists the playing episode first, skips finished ones", () => {
  const progress = {
    "1": { position: 100, duration: 1000, updated: 10, title: "Old" },
    "2": { position: 200, duration: 1000, updated: 20, title: "Newer" },
    "5": { done: true, updated: 30, title: "Done" }
  }
  const status = { running: true, position: 5, episode: { id: "9", title: "Now" } }
  assert.deepEqual(M.continueRows(progress, status, "").map(r => r.title), ["Now", "Newer", "Old"])
  assert.deepEqual(M.continueRows(progress, null, "old").map(r => r.title), ["Old"])
})

test("play payload resumes a little early, restarts finished episodes", () => {
  assert.equal(JSON.parse(M.playPayload({ id: "1", url: "u", position: 100 })).start, 97)
  assert.equal(JSON.parse(M.playPayload({ id: "1", url: "u", position: 100 }, true)).start, 0)
  assert.equal(JSON.parse(M.playPayload({ id: "1", url: "u", position: 100, done: true })).start, 0)
})

test("mark played and unplayed", () => {
  let p = M.markDone({}, { id: "1", title: "A", duration: 60 }, true)
  assert.equal(p["1"].done, true)
  p = M.markDone(p, { id: "1" }, false)
  assert.deepEqual(p, {})
})

test("parsers reject junk", () => {
  assert.deepEqual(M.parseSubscriptions("nope"), [])
  assert.deepEqual(M.parseSubscriptions('[{"id":"12"},{"id":"x"},null]'), [{ id: "12" }])
  assert.deepEqual(M.parseSubscriptions('{}'), [])
  assert.deepEqual(M.parseProgress("[]"), {})
  assert.deepEqual(M.parseProgress("not json"), {})
})

test("xmlEscape escapes all five entities", () => {
  assert.equal(M.xmlEscape('A & "B" \u003cC\u003e \'D\''), 'A &amp; &quot;B&quot; &lt;C&gt; &apos;D&apos;')
})

test("OPML escapes attributes", () => {
  const xml = M.opml([{ title: 'A & "B"', url: "https://f?a=1&b=2", link: "https://example.com" }, { title: "no url" }])
  assert.match(xml, /text="A &amp; &quot;B&quot;"/)
  assert.match(xml, /xmlUrl="https:\/\/f\?a=1&amp;b=2"/)
  assert.match(xml, /htmlUrl="https:\/\/example\.com"/)
  assert.doesNotMatch(xml, /no url/)
})
