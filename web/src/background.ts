// Stateless relay from content scripts to the native extension handler, which
// persists entries for the host app. Safari may suspend this script at any time.
import type { Entry, RuntimeMessage } from "./protocol"

type NativeMessage =
  | { type: "store"; tabId: number; pageUrl: string; entries: Entry[] }
  | { type: "tabClosed"; tabId: number }
  | { type: "syncTabs"; tabIds: number[] }

const sendNative = async (message: NativeMessage) => {
  // Safari ignores the application id and routes to this extension's handler.
  const response = (await browser.runtime.sendNativeMessage("application.id", message)) as
    | { error?: string }
    | undefined
  if (response?.error) throw new Error(response.error)
}

const report = (error: unknown) => console.error("[stupid devtools] native store failed", error)

// Only finished entries are stored; in-flight requests are only shown in the popup.
const isFinished = (entry: Entry) => entry.kind === "log" || entry.endTime !== undefined

browser.runtime.onMessage.addListener((raw: unknown, sender: { tab?: { id?: number } }) => {
  const message = raw as RuntimeMessage
  const tabId = sender.tab?.id
  if (message.type !== "entries" || tabId === undefined) return undefined
  const entries = message.entries.filter(isFinished)
  if (entries.length > 0) {
    sendNative({ type: "store", tabId, pageUrl: message.pageUrl, entries }).catch(report)
  }
  return undefined
})

browser.tabs.onRemoved.addListener((tabId: number) => {
  sendNative({ type: "tabClosed", tabId }).catch(report)
})

// Drops entries for tabs that closed while this script was not running.
browser.tabs
  .query({})
  .then((tabs) => sendNative({ type: "syncTabs", tabIds: tabs.flatMap((t) => t.id ?? []) }))
  .catch(report)
