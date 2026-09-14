# Security Policy

## Supported versions

Only the latest release on the [Releases](https://github.com/Techit-Kakaew/token-bar/releases) page receives fixes.

## What TokenBar touches

- Reads local log files of AI coding tools (`~/.claude`, `~/.codex`, `~/.gemini`, Zed, OpenCode, Qwen). Read-only.
- Optionally reads the Claude Code OAuth token from the macOS Keychain (item `Claude Code-credentials`) to call
  `api.anthropic.com/api/oauth/usage`. The token never leaves the process except in that request and is never written to disk or logged.
- Once a day calls the public GitHub Releases API to check for a new version. No identifiers are sent.
- Writes only to `UserDefaults` and `~/Library/Caches/dev.techit.tokenbar.app/`.

Anything outside this list is a bug — please report it.

## Reporting a vulnerability

Please **do not open a public issue** for security problems.

Use GitHub's private reporting: **Security → Report a vulnerability** on this repository
(https://github.com/Techit-Kakaew/token-bar/security/advisories/new). Include steps to reproduce, the macOS and
TokenBar versions, and impact as you understand it.

You should get an acknowledgement within 7 days. Fixes ship as a new release; credit is given in the release notes unless you prefer otherwise.

## Scope notes

- Cost figures are list-price estimates, not billing data; discrepancies there are not security issues.
- Releases are currently ad-hoc signed (not notarized). Verify downloads against the `.sha256` file attached to each release.
