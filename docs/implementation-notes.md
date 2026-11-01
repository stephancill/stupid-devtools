# Implementation Notes

## 2026-11-01 - Rewrite on stupid-app (1.1.0)

Rewrote the 1.0 Xcode project as a stupid-app SwiftPM project, keeping the bundle IDs, App Group and settings keys so it ships as an update.

### Fixes over 1.0

- **Per-tab popup.** 1.0 kept one global list in the background script, so the popup mixed every tab and lost everything when Safari suspended the non-persistent background. Entries now live in each tab's content script; the popup asks the active tab's content script and filters pushed batches by sender tab. The background script is stateless.
- **Dropped responses.** 1.0 wrote each start and completion event as separate native calls into separate SwiftData contexts; a completion processed first went down the insert path, which discarded the response body and end time. Now only finished requests are persisted, as one full record, upserted by id in SQLite.
- **Native write load.** One native message per log became one per 500 ms batch per tab, in a single SQLite transaction.
- **Cookies.** `Set-Cookie` is never visible to page scripts and `document.cookie` excludes HttpOnly cookies, so response cookies were always empty. Removed them; same-origin `document.cookie` is kept and labelled as such.
- **Early logs and CSP.** `page.js` is now a `world: "MAIN"` content script at `document_start` instead of a `<script src>` tag added by the content script, so it runs before page scripts and is not subject to the page's CSP. Verified on iOS 27 Safari: a log from an inline `<head>` script is captured. Console input uses indirect eval in the page; a CSP without `unsafe-eval` reports the error in the console.
- **fetch blocked on the body.** 1.0 awaited the full response body before resolving the page's `fetch`, delaying every request and breaking streams. Now the body is read from a clone after returning, capped at 100,000 characters by cancelling the reader.
- **Request details.** Headers and bodies passed via a `Request` object are captured, FormData fields are kept (for `curl -F`), XHR abort and timeout are distinguished, and `console.debug` is captured.
- **Serialization.** A custom formatter replaces the JSON round trip (circular references, undefined, bigint, functions, DOM nodes, Map/Set, throwing getters) and applies printf-style substitutions.
- **Page message channel.** `page.js` and `content.js` talk through `CustomEvent`s carrying JSON strings instead of `window.postMessage`, so the page's own `message` listeners never see devtools traffic. `content.js` validates every entry with zod/mini.

### New

- Copy as cURL, Copy as fetch and Copy URL on long press of a request, in the popup (custom long-press menu) and the app (`contextMenu`). The TypeScript and Swift exporters share test cases and produce identical text.
- The app polls the store every two seconds while a screen is visible, and supports pull to refresh.
- New icon set.

### Simplifications

- SQLite with one `entries` table (JSON per entry) replaces two SwiftData models. 1.0's `logs.store` is deleted on launch rather than migrated, since it only held short-lived debug data.
- The popup dropped Vite, Tailwind, Radix and shadcn for plain CSS and a Bun build script.
- Permissions reduced to `nativeMessaging` (content scripts get host access via `<all_urls>` matches).
- The unused `maxResponseBodySize` setting was removed.

### Limits

- Streaming responses that never finish (for example server-sent events) appear in the popup but are not stored in the app.
- Entries in the content script reset on navigation; the app keeps history across navigations in the same tab.
- Any page can dispatch fake devtools events into its own tab; this is the same trust level as the page calling `console.log`.

### Verification

- `bun run check` (typecheck, oxlint, oxfmt, 9 bun tests) and 7 Swift tests via `xcodebuild test` on an iOS 27 simulator.
- On an iOS 27 simulator with the test page: console levels, substitutions, circular values, uncaught errors and rejections, popup eval, fetch (JSON, FormData, `Request` object, 404, unreachable host), XHR; entries persisted to the App Group store and shown in the app; long-press Copy as cURL / fetch in the popup and app, and the copied cURL replayed successfully against the test server.

## 2026-11-01 - Copy response

- Added "Copy response" to the request long-press menus (popup and app) and the popup request detail bar. It copies the captured response body as stored, so a truncated body is copied truncated and binary or opaque responses copy their placeholder text.
- The popup toolbar wraps so the extra button fits.
- Verified on an iOS 27 simulator: both menus put the exact JSON response body on the pasteboard.

## 2026-11-01 - 1.1.0 (40) to internal TestFlight

- Provisioned App Store profiles for the app and extension with `stupid-app signing setup --kind distribution` (enables App Groups on both bundle IDs).
- Build number set to 40, following the builds uploaded by the 1.0 Xcode Cloud pipeline.
- Archived and uploaded with `stupid-app release archive` and `release upload --wait`; the build reached internal TestFlight testing.

## 2026-11-01 - Simpler design

- Popup: plain text tabs and buttons (no borders), log levels shown by text colour only (no row tints), no timestamps in the console, request rows show method, path and status only. The request detail has Back and one Copy button that opens the same menu as a long press. The menu drops the focus ring `showModal()` puts on its first item.
- App: tab rows show the host only, log rows show the message only, request rows are one line (method and path, status on the right). The request detail drops the Method row (it is the title) and Initiator, and the General header.
- Removed the "excludes HttpOnly" wording from the cookie sections; the README still documents the limitation.
- Dropped the per-tab log and request counts from `EntryStore.tabs()` since nothing shows them.
- Verified on an iOS 27 simulator (popup console, network, detail and copy menu; app tab list, console, network and detail); `bun run check` and the 7 Swift tests pass.

## 2026-11-01 - 1.1.0 (41) to internal TestFlight

- Uploaded the simplified design as build 41; it reached internal TestFlight testing.
- This repository replaced the 1.0 Xcode project on the `main` branch of the existing GitHub repository. The 1.0 history is kept on the `legacy-xcode` branch.

## 2026-11-01 - Rename to stupid devtools, new icon

- Display name is now "stupid devtools" for the app (`CFBundleDisplayName`), the extension and its manifest, and the setup instructions. Bundle IDs and the App Group are unchanged.
- New icon (an empty chip outline) for the app, the extension icons and the Safari toolbar icons.
- Verified on an iOS 27 simulator home screen.

## 2026-11-01 - 1.1.0 (42) to internal TestFlight

- Uploaded the rename and new icon as build 42; it reached internal TestFlight testing.

## 2026-11-01 - Response body first

- The request detail (popup and app) now shows the response body directly under the URL, status and duration, before the request headers, cookies, request body and response headers. It was previously last, below every header, and easy to miss.
- When there is no body yet the section says "Waiting for response" (still in flight) or "None".
- Verified on an iOS 27 simulator in the popup and the app.

## 2026-11-01 - Bodies formatted by type, raw toggle

- New `web/src/body.ts` and `Sources/DevToolsCore/BodyFormat.swift` (same rules, shared test cases) pick a view from the body's `Content-Type`: JSON is re-indented by walking the text (not parse and re-serialize, so key order and number formatting are kept; the app previously used `JSONSerialization`, which reordered keys), form-encoded bodies become name/value rows (duplicates kept), XML/SVG text is indented tag by tag, HTML and other text are shown as sent. Without a content type, or with `text/plain`, JSON, `<?xml` and HTML documents are sniffed. Request bodies use the same rules with the request's content type.
- Image responses (except SVG, which is XML) up to 100 KB are captured in `page.js` as base64 (`responseBodyEncoding: "base64"`) and previewed; larger ones record their size. "Copy response" copies a data URL for images.
- The response section is labelled with its type ("Response · JSON") and has a Raw/Formatted toggle for JSON, XML and form bodies, in the popup and the app.
- The popup's small header buttons get a full-size hit area; with the minimal padding the toggle missed taps.
- Verified on an iOS 27 simulator with new test-page routes (`/api/xml`, `/api/form`, `/api/html`, `/api/image`, `/api/untyped`): each shows the right label and formatting, and the toggle switches between formatted and raw in both the popup and the app. 17 bun tests and 15 Swift tests pass.

## 2026-11-02 - App Store screenshots for 1.1.0

- New screenshots in the stupid style (white canvas, lowercase headlines, hand-drawn doodles) under `screenshots/appstore-1.1.0/`: raw captures from an iPhone 17 Pro Max simulator, `spec.json`, and rendered 6.9" (`iphone/`, 1320×2868) and 6.5" (`iphone65/`, 1242×2688) sets. Captions alternate between top and bottom, left and right.
- The captures use a realistic demo page, `web/test-page/shop.html` served at `/shop` with `/api/v1/*` routes, instead of the bare test page.
- Fix: in the popup, holding the long press after the copy menu appeared started a text selection inside the menu. The menu is now unselectable.
