# Agent Instructions

## Before making changes

1. Read this file, `README.md` and `docs/implementation-notes.md` (latest entries first, plus any related to the task).
2. Check the current code rather than assuming the notes are current. If code and docs disagree, investigate and fix whichever is wrong.

## Before committing

- Append a dated entry to `docs/implementation-notes.md` describing what changed, why, and how it was verified. Update `README.md` when behaviour, layout or commands change.
- Notes are public: never include personal information, credentials, device identifiers or private hostnames.
- Use conventional commits (`feat:`, `fix:`, `chore:`, ...).

## Stack

- iOS app and Safari extension built with the `stupid-app` CLI (SwiftPM, no Xcode project). Bundle IDs `co.za.stephancill.devtools` and `.Extension`, App Group `group.co.za.stephancill.devtools`, iOS 17+, iPhone only.
- Swift 6, SwiftUI, SQLite (no SwiftData). Format with `swift format -i -r Sources Tests`.
- Extension scripts in `web/`: Bun (package manager, bundler, tests), TypeScript, React with react-query in the popup, zod/mini for validating page messages. Lint and format with oxlint and oxfmt (`bun run check`).

## Rules

- `web/src/entries.ts` and `Sources/DevToolsCore/Entry.swift` describe the same JSON; change both together.
- `web/src/export.ts` and `Sources/DevToolsCore/RequestExport.swift` must produce identical text; the tests in `web/src/export.test.ts` and `Tests/DevToolsCoreTests` cover the same cases. Change both together.
- Keep `page.js` free of runtime dependencies (it runs in every page's MAIN world) and `content.js` small.
- `background.js` must stay stateless: Safari suspends it at any time.
- Fail loudly: surface errors in the popup or app rather than silently falling back.
- SwiftUI follows the stupid-ios-design rules: native long-press copy, `.alert` confirmations for destructive actions, system fonts only.
- After changing app or extension code, run `bun run build` in `web/` and reinstall on a simulator (`stupid-app run --simulator`).

## Commands

```bash
cd web && bun run build && bun run check
stupid-app build
stupid-app run --simulator --udid <udid>
xcodebuild test -scheme DevTools-Package -destination 'platform=iOS Simulator,id=<udid>' | xcpretty
```
