# Contributing to TokenBar

Thanks for helping! Small, focused PRs are easiest to review.

## Setup

```bash
git clone https://github.com/Techit-Kakaew/token-bar && cd token-bar
swift test                 # run the unit tests
./build.sh --install       # build and install to /Applications (Xcode 16+, Xcode 26 for Liquid Glass)
```

No Xcode project — it is a plain Swift Package. Open the folder in Xcode or any editor.

## Adding a provider

1. Create `Sources/TokenBar/Providers/<Name>Source.swift` implementing `UsageSource`
   (`roots`, `matches(_:)`, `parse(file:)`). Parse defensively: unknown shape → return `[]`, never crash.
2. Add a case to `Provider` in `Models.swift` (display name, vendor, accent colour, SF Symbol, `logoFile`).
3. Register it in `UsageStore.sources` (and the `--dump` list in `main.swift`).
4. Add a small **anonymised** fixture to `Tests/TokenBarTests/Fixtures` and a test in `ParserTests.swift`.
5. Add pricing prefixes in `Pricing.swift` if the models are new.
6. Document the source path and verification status in the README table.

Optional: an SVG logo in `Sources/TokenBar/Resources/logos/` — only marks you have the right to redistribute (e.g. CC0 from Simple Icons).

## Strings

All user-facing text goes through `L("key")` with English + Thai entries in `L10n.swift`.
Data (model ids, project names, exports) stays untranslated.

## Before opening a PR

- `swift test` passes and `swift build -c release` is warning-free.
- Run the app once and check the popover and dashboard in both light and dark appearance.
- Describe what you tested on (macOS version, which tools you had logs for).
- Don't commit real logs or tokens — fixtures must be synthetic or scrubbed.

## Releases

Maintainers only: bump `CFBundleShortVersionString` / `CFBundleVersion` in `Info.plist`, then tag `vX.Y.Z`. CI publishes the dmg.
