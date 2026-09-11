# TokenBar

<p align="center">
  <img src="docs/popover.png" width="380" alt="TokenBar popover">
</p>

macOS menu-bar app that shows AI token usage & estimated cost across local AI coding CLIs.
Reads local logs only — no API keys, no network.

| Provider | Source |
|---|---|
| Claude Code | `~/.claude/projects/**/*.jsonl` (`message.usage`, deduped by message id) |
| Codex CLI | `~/.codex/sessions/**/*.jsonl` (`token_count` → `last_token_usage`) |
| Gemini CLI | `~/.gemini/tmp/*/chats/*.json` (`tokens` field) |

Features: Today / 7d / 30d / All windows, input/output/cache breakdown, 14-day sparkline,
per-model cost (tap a card), launch-at-login, auto refresh every 60 s.

## Dashboard window

<img src="docs/dashboard.png" width="900" alt="TokenBar dashboard">

"Dashboard" button in the popover footer opens a separate resizable window: 7/14/30-day stacked
daily chart (tokens or cost), top **projects** (from `cwd` in logs), models, sources, and per-provider
breakdown with rate-limit gauges. **Click a bar** to drill into that day — projects / models / sources
switch to day-scoped data; click again or "Back" to return.
Debug render: `TokenBar --snapshot-dashboard out.png` (`TOKENBAR_SNAPSHOT_DAY=1` preselects yesterday).

## Export

Dashboard → **Export** menu: events CSV (last 30 days, or the drilled-down day), daily summary CSV,
or a Markdown report for the selected window. Headless for scripts / cron:

```bash
/Applications/TokenBar.app/Contents/MacOS/TokenBar --export events 7d  > events.csv
/Applications/TokenBar.app/Contents/MacOS/TokenBar --export daily      > daily.csv
/Applications/TokenBar.app/Contents/MacOS/TokenBar --export report 30d > report.md
```

## Sources

Each card splits usage by where the call came from:

- **Claude Code** — `entrypoint` field: `cli` → Terminal, `claude-desktop` → Claude Desktop, `sdk-*` → Zed (ACP) / Agent SDK, `claude-vscode` → VS Code.
- **Codex** — `session_meta.originator` / `source`: Codex CLI, Codex Desktop, VS Code.

## Rate limits (5h / weekly)

| Provider | Source |
|---|---|
| Claude Code | `GET api.anthropic.com/api/oauth/usage` using the OAuth token Claude Code stores in Keychain (`Claude Code-credentials`). Polled every 5 min. **First run shows a Keychain prompt → click "Always Allow"**. If the token expires, run `claude` once to refresh it. |
| Codex CLI | `rate_limits` payload in the newest session log (updates while Codex runs). |

Gauges turn amber ≥70 %, red ≥90 %.

## Limit alerts

Notification when any 5h / weekly window crosses 80 % (configurable: off / 70 / 80 / 90) and again at 95 %,
once per reset cycle. The menu-bar icon turns amber / red and shows the worst percentage while over threshold.

## Break reminder

Detects a continuous usage streak (calls across all providers with gaps < 15 min) and posts a macOS
notification suggesting a break after 90 min, repeating every 45 min while the streak continues.
Thresholds live in the ⚙️ menu in the popover footer. First launch asks for Notification permission.

## Install

**Download**: grab `TokenBar-x.y.z.dmg` from [Releases](https://github.com/Techit-Kakaew/token-bar/releases),
drag TokenBar.app to Applications. The build is universal (Apple Silicon + Intel) but **not notarized**
(no Apple Developer account yet), so on first launch macOS may refuse it. Fix once:

```bash
xattr -cr /Applications/TokenBar.app
```

then open normally (or right-click → Open).

**Build from source** (Xcode 15+, macOS 14+):

```bash
./build.sh --install     # native build → /Applications/TokenBar.app
./build.sh --dmg         # universal build → dist/TokenBar-<version>.dmg
```

App icon: `swift scripts/make_appicon.swift Sources/TokenBar/Resources && iconutil -c icns …/AppIcon.iconset`.

## Pricing overrides

Built-in table in `Sources/TokenBar/Pricing.swift` (USD per 1M tokens). Override or add models via
`~/.config/tokenbar/pricing.json`, matched by model-id prefix:

```json
{ "gpt-5.6": { "input": 1.75, "output": 14, "cacheRead": 0.175, "cacheWrite": 0 } }
```

## Vendor logos

`Sources/TokenBar/Resources/logos/*.svg` — Claude and Gemini marks from [Simple Icons](https://simpleicons.org) (CC0);
OpenAI blossom is a hand-drawn approximation (the official mark is not redistributable). Loaded as template
NSImages and tinted with each provider's accent colour. Swap the SVG to change a logo.

## Custom menu-bar icon

Icon is a **template image** (black + alpha, 18×18 pt) at `Sources/TokenBar/Resources/MenuBarIcon.png`
and `MenuBarIcon@2x.png` (36×36 px). macOS tints it for light/dark menu bars automatically.

- Regenerate the built-in hexagon-bars icon: `swift scripts/make_icon.swift Sources/TokenBar/Resources`
- Or drop in your own PNGs with the same names, then `./build.sh --install`
- Check which file is loaded: `/Applications/TokenBar.app/Contents/MacOS/TokenBar --icon`

## Debug

```bash
.build/release/TokenBar --dump               # print aggregated stats
.build/release/TokenBar --snapshot out.png   # render popover to PNG
```

## License

MIT
