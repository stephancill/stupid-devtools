// Message shapes and constants with no runtime dependencies, so page.js stays tiny.
import type { Entry } from "./entries"

export type { Entry, LogEntry, LogLevel, RequestBody, RequestEntry } from "./entries"

// page.js (MAIN world) and content.js (isolated world) talk through DOM events on
// `document` carrying JSON strings, which cross worlds and stay out of the page's
// own `message` listeners.
export const entryEvent = "stupid-devtools:entry"
export const evalEvent = "stupid-devtools:eval"

// Messages between content.js, the popup and background.js.
export type RuntimeMessage =
  | { type: "entries"; pageUrl: string; entries: Entry[] }
  | { type: "getEntries" }
  | { type: "eval"; code: string }
  | { type: "clear" }

export type EntriesResponse = { pageUrl: string; entries: Entry[] }

// Response bodies are cut at this many characters before leaving the page.
export const maxBodyLength = 100_000
