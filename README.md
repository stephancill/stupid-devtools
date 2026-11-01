# browser devtools

A Safari Web Extension for iOS that adds a console and network inspector to mobile Safari, plus a host app that keeps per-tab history. Built with the stupid-app CLI (SwiftPM, no Xcode project).

## Features

- **Console:** `console.log/info/warn/error/debug` (with `%s %d %o %c` substitutions), uncaught errors and unhandled rejections. Values are formatted safely: circular references, `undefined`, bigint, functions, DOM nodes, Maps and Sets.
- **Run JavaScript** on the current page from the popup. Pages whose CSP forbids `unsafe-eval` show the error instead.
- **Network:** `fetch` and `XMLHttpRequest`, with headers, request bodies (text, form data, binary size), response bodies (text-like, first 100,000 characters) and same-origin `document.cookie`.
- **Copy as cURL / fetch / response:** long-press a request in the popup or the app.
- **History in the app:** entries are stored per Safari tab and removed when the tab closes, after the retention period, or past the per-tab limits in Settings.

## How it works

```
page.js (MAIN world)  patches console, error events, fetch, XHR at document_start
   │ CustomEvent "stupid-devtools:entry" (JSON string)
content.js            validates with zod, holds this tab's entries, batches every 500 ms
   │ runtime.sendMessage({ type: "entries" })
   ├──> popup          shows the active tab (initial load asks content.js directly)
   └──> background.js  stateless; forwards finished entries
          │ sendNativeMessage
        DevToolsSafari (native handler) ──> devtools.sqlite in the App Group
                                              │
                                     DevTools app (reads, refreshes every 2 s)
```

## Layout

| Path | Contents |
|---|---|
| `web/` | Extension scripts and popup (Bun, TypeScript, React, zod/mini). `bun run build` writes into `SafariExtension/Resources/`. |
| `web/test-page/` | A page that exercises every capture path: `bun run test-page/server.ts`. |
| `SafariExtension/` | Extension `Info.plist`, entitlements, `manifest.json` and icons. |
| `Sources/DevToolsCore/` | Entry models, SQLite store, settings, cURL/fetch export. |
| `Sources/DevToolsSafari/` | Native message handler. |
| `Sources/DevTools/` | SwiftUI app. |

## Development

```bash
cd web && bun install && bun run build    # required before any stupid-app build
bun run check                             # typecheck, oxlint, oxfmt --check, bun test

cd .. && stupid-app run --simulator --udid <udid>
xcodebuild test -scheme DevTools-Package -destination 'platform=iOS Simulator,id=<udid>' | xcpretty
```

In the simulator, enable the extension from Safari's page menu (Manage Extensions), then open it from the same menu and allow it on the site.

## Release

```bash
stupid-app release preflight
stupid-app release bump
stupid-app release archive && stupid-app release upload --wait
```
