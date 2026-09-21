<div align="center">

# Podmarchy

**A podcast player for the Omarchy shell.**
Find shows on Podcast Index, subscribe with one key, and stream episodes that
pick up where you stopped — without leaving the keyboard.

`de.gransoftware.podmarchy`&nbsp;&nbsp;·&nbsp;&nbsp;![version](https://img.shields.io/badge/version-0.1.0-2f6f4e?style=flat-square)&nbsp;![shell](https://img.shields.io/badge/Omarchy-shell%20plugin-3b4252?style=flat-square)&nbsp;![qml](https://img.shields.io/badge/built%20with-Quickshell%20%2F%20QML-41cd52?style=flat-square)&nbsp;![mpv](https://img.shields.io/badge/plays%20with-mpv-690b6b?style=flat-square)

<sub>Podmarchy follows the active Omarchy theme.</sub>

</div>

> [!IMPORTANT]
> Podmarchy needs a free **Podcast Index API key and secret** to search and
> discover shows. Create them at
> [api.podcastindex.org/signup](https://api.podcastindex.org/signup) before
> you start — see [Connect Podcast Index](#connect-podcast-index).

---

## <img src="icons/lightbulb.png" width="20" alt=""> Why

Podcasts, and nothing else. No Podmarchy account, no sync service, no ads: an
index to search, a list of shows you follow, and mpv doing the playing.

## <img src="icons/list-checks.png" width="20" alt=""> Features

- **Discover** trending shows, or search the whole
  [Podcast Index](https://podcastindex.org) — an open catalogue of more than
  four million podcasts.
- **Library** of the shows you subscribe to, kept on your machine.
- **Continue** lists every episode you started and did not finish, the one
  playing first.
- **Resumes** each episode where you left it. Progress is saved on pause,
  every few seconds while playing and on stop; an episode heard to within 30
  seconds of its end counts as played.
- **Keeps playing** when the panel closes or the shell restarts: mpv runs on
  its own. Media keys work through MPRIS (`mpv-mpris` ships with Omarchy).
- **Bar widget** lights up while something plays. Click opens the panel,
  right-click pauses, middle-click stops, scrolling seeks.
- **Detail pane** with the cover, show notes and a live progress bar.
- **OPML export** of your subscriptions, for any other podcast app.

## <img src="icons/keyboard.png" width="20" alt=""> Keys

`?` shows the same list inside the app.

<table>
  <tr><td width="28"><img src="icons/arrows-vertical.png" width="18" alt=""></td><td><code>Ctrl+J</code> <code>Ctrl+K</code> · arrows</td><td>Move through the list</td></tr>
  <tr><td width="28"><img src="icons/funnel.png" width="18" alt=""></td><td><code>Tab</code> · <code>Ctrl+H</code> <code>Ctrl+L</code> · <code>Ctrl+1–3</code></td><td>Library, Discover, Continue</td></tr>
  <tr><td width="28"><img src="icons/arrow-elbow-down-left.png" width="18" alt=""></td><td><code>Enter</code></td><td>Open a show · play or pause an episode</td></tr>
  <tr><td width="28"><img src="icons/copy.png" width="18" alt=""></td><td><code>Shift+Enter</code></td><td>Play from the start</td></tr>
  <tr><td width="28"><img src="icons/push-pin.png" width="18" alt=""></td><td><code>Ctrl+P</code></td><td>Subscribe / unsubscribe</td></tr>
  <tr><td width="28"><img src="icons/flow-arrow.png" width="18" alt=""></td><td><code>Ctrl+Space</code> · <code>Ctrl+←</code> <code>Ctrl+→</code> · <code>Ctrl+S</code></td><td>Pause · back 15 s / ahead 30 s · stop</td></tr>
  <tr><td width="28"><img src="icons/eye.png" width="18" alt=""></td><td><code>Ctrl+O</code></td><td>Show or hide the detail pane</td></tr>
  <tr><td width="28"><img src="icons/dots-three.png" width="18" alt=""></td><td><code>Ctrl+.</code></td><td>Actions menu</td></tr>
  <tr><td width="28"><img src="icons/trash.png" width="18" alt=""></td><td><code>Delete</code> <code>Ctrl+D</code></td><td>Unsubscribe (Library) · forget progress (Continue)</td></tr>
  <tr><td width="28"><img src="icons/gear.png" width="18" alt=""></td><td><code>Ctrl+,</code></td><td>Settings</td></tr>
  <tr><td width="28"><img src="icons/x.png" width="18" alt=""></td><td><code>Esc</code> · <code>Backspace</code></td><td>Clear search, leave a show, then close</td></tr>
</table>

## <img src="icons/download-simple.png" width="20" alt=""> Install

```bash
omarchy plugin add https://github.com/gran-software-solutions/podmarchy-omarchy-plugin.git --enable --yes
```

The bar widget lands on the right; move it with `omarchy bar move`. For a
keybinding too, add one in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + P", "Podmarchy", "omarchy-shell shell toggle de.gransoftware.podmarchy")
```

### Connect Podcast Index

**Required.** Podmarchy has no catalogue of its own: search, trending and
episode lists all come from the Podcast Index API, which needs your own API
key **and** API secret. Both are free — no card, no cost:

1. Sign up at [api.podcastindex.org/signup](https://api.podcastindex.org/signup).
2. Copy the **API key** and the **API secret** Podcast Index gives you. You
   need both.
3. Open Podmarchy, press `Ctrl+,`, paste the key and the secret, press Enter.

The pair is stored in `~/.local/state/omarchy/podmarchy/credentials.json`
(mode 600) and only ever sent to Podcast Index, as a signed header. Without
it you can't search, see trending shows or load a show's episodes; only
episodes already in Continue can still be resumed.

### Dependencies

Nothing to install first: `mpv`, `socat`, `curl`, `jq` and `mpv-mpris` all
ship with Omarchy.

### Update and remove

```bash
omarchy plugin update de.gransoftware.podmarchy
omarchy plugin remove de.gransoftware.podmarchy
```

Your subscriptions and progress stay in `~/.local/state/omarchy/podmarchy/`
until you delete that folder too.

## <img src="icons/eye.png" width="20" alt=""> Privacy

Podmarchy talks to two kinds of server: Podcast Index, for search, trending
and episode lists, and each podcast's own host, for artwork and audio — the
same requests any podcast app makes. Nothing is collected or sent anywhere
else. Subscriptions and listening progress live only in your state directory.

<details>
<summary><img src="icons/flow-arrow.png" width="18" alt=""> <b>How it works</b></summary>

<br>

```
  Podmarchy.qml ──▶ podmarchy-api ──▶ Podcast Index (signed GET)
        │                               one normalised JSON line
        │
        └──▶ podmarchy-player ──▶ mpv ──▶ podmarchy-status.lua
                                              │
                    status.json (every second)◀┤──▶ progress.json (resume)
                          │
                    bar widget + panel
```

| File | Purpose |
|------|---------|
| `Podmarchy.qml` | Overlay UI shell: views, list, detail pane, state, processes |
| `PodmarchyModel.js` | Row shaping, filtering, formatting — pure, tested with node |
| `BarWidget.qml` | Bar button with now-playing tooltip |
| `components/*.qml` | Reusable UI pieces: keycaps, settings fields, popups |
| `podmarchy-api` | Podcast Index client; HTML to plain text; key storage |
| `podmarchy-player` | Starts, pauses, seeks and stops the single mpv |
| `podmarchy-status.lua` | Runs inside mpv; writes status and progress |
| `manifest.json` | Plugin manifest — `overlay` + `bar-widget`, `keepLoaded` |
| `tests/` | Node tests for the model + bash smoke tests |

State lives in `~/.local/state/omarchy/podmarchy/` as `subscriptions.json`,
`progress.json`, `settings.json` and `credentials.json`; the live player status
is in `$XDG_RUNTIME_DIR/podmarchy/`.

</details>

<details>
<summary><img src="icons/wrench.png" width="18" alt=""> <b>Development</b></summary>

<br>

Symlink a checkout into the plugins folder; the shell hot-reloads on save:

```bash
ln -s "$PWD" ~/.config/omarchy/plugins/de.gransoftware.podmarchy
omarchy-shell shell rescanPlugins
```

Changes to `PodmarchyModel.js` need `omarchy-restart-shell` (the engine keeps
imported scripts cached). Run the tests with `npm test` or `node --test tests/`;
run `npm run test:api` for bash smoke tests. `PODMARCHY_API_BASE` points
`podmarchy-api` at a local fixture server.

</details>

## <img src="icons/robot.png" width="20" alt=""> Vibe-coded

Every line of this plugin was written by [Claude](https://claude.com/claude-code)
from conversational prompts. It runs unsandboxed inside `omarchy-shell`, so read
the source before you enable it.

## <img src="icons/scales.png" width="20" alt=""> License

[MIT](LICENSE) © Gran Software Solutions

Key icons from [Phosphor Icons](https://phosphoricons.com), MIT — see
[`icons/LICENSE`](icons/LICENSE). Podcast data from
[Podcast Index](https://podcastindex.org).
