<p align="center">
  <img src="docs/appicon-256.png" width="128" alt="TokenBar icon">
</p>

<h1 align="center">TokenBar</h1>

<p align="center">
  <a href="https://github.com/Techit-Kakaew/token-bar/actions/workflows/ci.yml"><img src="https://github.com/Techit-Kakaew/token-bar/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/Techit-Kakaew/token-bar/releases/latest"><img src="https://img.shields.io/github/v/release/Techit-Kakaew/token-bar" alt="Release"></a>
</p>

<p align="center">
  <img src="docs/popover.png" width="380" alt="TokenBar popover">
</p>

macOS menu-bar app that shows AI token usage & estimated cost across local AI coding CLIs.
Reads local logs only — no API keys, no network.

| Provider | Source | Status |
|---|---|---|
| Claude Code | `~/.claude/projects/**/*.jsonl` (`message.usage`, deduped by message id) | verified |
| Codex CLI | `~/.codex/sessions/**/*.jsonl` (`token_count` → `last_token_usage`) | verified |
| Gemini CLI | `~/.gemini/tmp/*/chats/*.json` (`tokens` field) | format from Gemini CLI source; not exercised locally |
| Zed Agent (native panel) | `~/Library/Application Support/Zed/threads/threads.db` — zstd JSON, `request_token_usage` (needs `brew install zstd`) | verified; no per-message timestamps → attributed to thread `updated_at` |
| OpenCode | `~/.local/share/opencode/storage/message/*/*.json` (`tokens`, `modelID`) | **unverified** — written from the documented JSON layout; please open an issue with a sample if it misparses |
| Qwen Code | `~/.qwen/tmp/*/chats/*.json` (Gemini CLI fork, same layout) | unverified |

Providers with no local files are hidden automatically. Adding one = implement `UsageSource` (roots, matches, parse) + a `Provider` case.

Providers without local data are hidden. Features: Today / 7d / 30d / All windows, input/output/cache breakdown, 14-day sparkline,
per-model cost (tap a card), launch-at-login, auto refresh every 60 s. Light / dark / system theme (⚙️ menu). UI in **English or Thai** — follows the system language (Thai → ไทย, anything else → English), overridable in ⚙️ → Language.
Menu-bar item can show the combined total or a single provider (its logo + tokens + worst limit) — ⚙️ → "แสดงบน menubar".

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

## Privacy

- Reads **local log files only**; nothing is uploaded, no telemetry, no analytics.
- The single network call is optional: with *Claude limits* enabled, TokenBar reads Claude Code's OAuth token from your
  Keychain (macOS asks once) and calls `api.anthropic.com/api/oauth/usage` to show 5h / weekly limits.
  Turn it off in ⚙️ at any time. A once-a-day check against the GitHub Releases API looks for new versions (no identifiers sent).
- Settings live in `UserDefaults` (`dev.techit.tokenbar.app`); nothing else is written outside the app.

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

**Download**: latest `.dmg` from [Releases](https://github.com/Techit-Kakaew/token-bar/releases/latest)
(all versions on [Releases](https://github.com/Techit-Kakaew/token-bar/releases)),
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

**Release**: bump `CFBundleShortVersionString` in `Info.plist`, commit, then `git tag vX.Y.Z && git push origin vX.Y.Z`.
GitHub Actions builds the universal dmg and publishes the release automatically (`.github/workflows/release.yml`).

App icon: PNGs in `Assets/AppIcon.xcassets` (regenerate with `scripts/make_appicon.swift`); `build.sh` compiles them with `actool` into `Assets.car` + `AppIcon.icns`.

## Pricing overrides

Built-in table in `Sources/TokenBar/Pricing.swift` (USD per 1M tokens). Override or add models via
`~/.config/tokenbar/pricing.json`, matched by model-id prefix:

```json
{ "gpt-5.6": { "input": 1.75, "output": 14, "cacheRead": 0.175, "cacheWrite": 0 } }
```

## Vendor logos

`Sources/TokenBar/Resources/logos/*.svg` — Claude, Gemini and OpenAI marks as published by [Simple Icons](https://simpleicons.org) (CC0).
Trademarks belong to their owners; used here only to identify the tool. Loaded as template
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
