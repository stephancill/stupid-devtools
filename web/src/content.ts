// Isolated-world content script. Holds this page's entries (so the popup always sees
// the current tab only) and forwards new or updated entries in batches to the popup
// and background.js.
import { entrySchema } from "./entries"
import { type Entry, type RuntimeMessage, entryEvent, evalEvent } from "./protocol"

const limits = { log: 1000, request: 500 }
const flushDelay = 500

const entries = new Map<string, Entry>()
const unsent = new Map<string, Entry>()
let flushTimer: ReturnType<typeof setTimeout> | undefined

const trim = (kind: Entry["kind"]) => {
  const ids = [...entries.values()].filter((e) => e.kind === kind).map((e) => e.id)
  for (const id of ids.slice(0, Math.max(0, ids.length - limits[kind]))) entries.delete(id)
}

const flush = () => {
  flushTimer = undefined
  const batch = [...unsent.values()]
  unsent.clear()
  const message: RuntimeMessage = { type: "entries", pageUrl: location.href, entries: batch }
  browser.runtime.sendMessage(message).catch((error: unknown) => {
    console.debug("[stupid devtools] failed to forward entries", error)
  })
}

document.addEventListener(entryEvent, (event) => {
  const detail = (event as CustomEvent<unknown>).detail
  if (typeof detail !== "string") return
  let json: unknown
  try {
    json = JSON.parse(detail)
  } catch {
    return
  }
  const parsed = entrySchema.safeParse(json)
  if (!parsed.success) {
    console.debug("[stupid devtools] dropped malformed entry", parsed.error)
    return
  }
  const entry = parsed.data
  const isNew = !entries.has(entry.id)
  entries.set(entry.id, entry)
  if (isNew) trim(entry.kind)
  unsent.set(entry.id, entry)
  flushTimer ??= setTimeout(flush, flushDelay)
})

browser.runtime.onMessage.addListener((raw: unknown) => {
  const message = raw as RuntimeMessage
  switch (message.type) {
    case "getEntries":
      return Promise.resolve({ pageUrl: location.href, entries: [...entries.values()] })
    case "eval":
      document.dispatchEvent(new CustomEvent(evalEvent, { detail: message.code }))
      return Promise.resolve(true)
    case "clear":
      entries.clear()
      unsent.clear()
      return Promise.resolve(true)
  }
  return undefined
})
