import {
  QueryClient,
  QueryClientProvider,
  useMutation,
  useQuery,
  useQueryClient,
} from "@tanstack/react-query"
import { useEffect, useRef, useState } from "react"
import { createRoot } from "react-dom/client"
import { toCurl, toFetch } from "../export"
import type { EntriesResponse, Entry, LogEntry, RequestEntry, RuntimeMessage } from "../protocol"

const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } })

const activeTabId = async () => {
  const [tab] = await browser.tabs.query({ active: true, currentWindow: true })
  if (tab?.id === undefined) throw new Error("No active tab.")
  return tab.id
}

const sendToTab = async (message: RuntimeMessage) => {
  const tabId = await activeTabId()
  try {
    return await browser.tabs.sendMessage(tabId, message)
  } catch {
    throw new Error(
      "DevTools isn't running on this page. Allow the extension on this website, then reload the page.",
    )
  }
}

const entriesKey = ["entries"]

const merge = (current: Entry[], incoming: Entry[]) => {
  const byId = new Map(current.map((entry) => [entry.id, entry]))
  for (const entry of incoming) byId.set(entry.id, entry)
  return [...byId.values()]
}

const useEntries = () => {
  const client = useQueryClient()
  const query = useQuery({
    queryKey: entriesKey,
    queryFn: async () => {
      const tabId = await activeTabId()
      const response = (await sendToTab({ type: "getEntries" })) as EntriesResponse
      return { tabId, entries: response.entries }
    },
  })
  const tabId = query.data?.tabId

  // content.js pushes batches for every tab; keep the active tab's only.
  useEffect(() => {
    if (tabId === undefined) return
    const listener = (raw: unknown, sender: { tab?: { id?: number } }) => {
      const message = raw as RuntimeMessage
      if (message.type !== "entries" || sender.tab?.id !== tabId) return undefined
      client.setQueryData<{ tabId: number; entries: Entry[] }>(entriesKey, (data) =>
        data ? { ...data, entries: merge(data.entries, message.entries) } : data,
      )
      return undefined
    }
    browser.runtime.onMessage.addListener(listener)
    return () => browser.runtime.onMessage.removeListener(listener)
  }, [client, tabId])

  return query
}

// iOS replaces straight quotes and dashes while typing; JavaScript needs the originals.
const unsmarten = (code: string) =>
  code
    .replace(/[“”„‟″‶]/g, '"')
    .replace(/[‘’‚‛′‵]/g, "'")
    .replace(/…/g, "...")
    .replace(/[–—]/g, "-")

const duration = (request: RequestEntry) => {
  if (request.endTime === undefined) return "pending"
  const ms = request.endTime - request.startTime
  return ms < 1000 ? `${ms} ms` : `${(ms / 1000).toFixed(2)} s`
}

const pathOf = (url: string) => {
  try {
    const parsed = new URL(url)
    return parsed.pathname + parsed.search
  } catch {
    return url
  }
}

const prettyBody = (body: string) => {
  try {
    return JSON.stringify(JSON.parse(body), null, 2)
  } catch {
    return body
  }
}

const levelPrefix: Partial<Record<LogEntry["level"], string>> = { command: "› ", result: "‹ " }

function Console({ logs }: { logs: LogEntry[] }) {
  const [code, setCode] = useState("")
  const end = useRef<HTMLDivElement>(null)
  const run = useMutation({ mutationFn: (code: string) => sendToTab({ type: "eval", code }) })

  useEffect(() => end.current?.scrollIntoView(), [logs.length])

  return (
    <div className="panel">
      <div className="scroll">
        {logs.length === 0 && <p className="empty">No console output yet.</p>}
        {logs.map((log) => (
          <div key={log.id} className={`row log ${log.level}`}>
            <span className="message">
              {levelPrefix[log.level]}
              {log.message}
            </span>
          </div>
        ))}
        <div ref={end} />
      </div>
      {run.error && <p className="error">{run.error.message}</p>}
      <form
        className="prompt"
        onSubmit={(event) => {
          event.preventDefault()
          if (!code.trim()) return
          run.mutate(code)
          setCode("")
        }}
      >
        <input
          value={code}
          onChange={(event) => setCode(unsmarten(event.target.value))}
          placeholder="Run JavaScript"
          autoComplete="off"
          autoCapitalize="off"
          autoCorrect="off"
          spellCheck={false}
          enterKeyHint="go"
        />
      </form>
    </div>
  )
}

const copy = async (text: string, onDone: (status: string) => void) => {
  try {
    await navigator.clipboard.writeText(text)
    onDone("Copied")
  } catch (error) {
    onDone(`Copy failed: ${error instanceof Error ? error.message : String(error)}`)
  }
}

// Long press opens the copy menu; a normal tap still selects the row.
const useLongPress = (onLongPress: () => void) => {
  const timer = useRef<ReturnType<typeof setTimeout>>(undefined)
  const fired = useRef(false)
  const cancel = () => clearTimeout(timer.current)
  return {
    onPointerDown: () => {
      fired.current = false
      timer.current = setTimeout(() => {
        fired.current = true
        onLongPress()
      }, 450)
    },
    onPointerUp: cancel,
    onPointerLeave: cancel,
    onPointerCancel: cancel,
    onContextMenu: (event: React.MouseEvent) => {
      event.preventDefault()
      cancel()
      fired.current = true
      onLongPress()
    },
    // Lets the click handler skip the tap that ended a long press.
    consumeLongPress: () => {
      const wasLongPress = fired.current
      fired.current = false
      return wasLongPress
    },
  }
}

function RequestRow({
  request,
  onSelect,
  onMenu,
}: {
  request: RequestEntry
  onSelect: () => void
  onMenu: () => void
}) {
  const { consumeLongPress, ...handlers } = useLongPress(onMenu)
  const failed = request.error !== undefined || (request.status ?? 0) >= 400
  return (
    <button
      type="button"
      className={`row request ${failed ? "failed" : ""}`}
      {...handlers}
      onClick={() => {
        if (!consumeLongPress()) onSelect()
      }}
    >
      <span className="method">{request.method}</span>
      <span className="message">{pathOf(request.url)}</span>
      <span className="muted">{request.error ? "failed" : (request.status ?? "…")}</span>
    </button>
  )
}

function CopyMenu({
  request,
  onClose,
}: {
  request: RequestEntry
  onClose: (status?: string) => void
}) {
  const dialog = useRef<HTMLDialogElement>(null)
  useEffect(() => dialog.current?.showModal(), [])
  const choose = (text: string) => copy(text, onClose)
  return (
    <dialog ref={dialog} className="menu" onClose={() => onClose()}>
      <p className="menu-title">{pathOf(request.url)}</p>
      <button type="button" onClick={() => choose(toCurl(request))}>
        Copy as cURL
      </button>
      <button type="button" onClick={() => choose(toFetch(request))}>
        Copy as fetch
      </button>
      <button type="button" onClick={() => choose(request.url)}>
        Copy URL
      </button>
      {request.responseBody !== undefined && (
        <button type="button" onClick={() => choose(request.responseBody ?? "")}>
          Copy response
        </button>
      )}
      <button type="button" onClick={() => onClose()}>
        Cancel
      </button>
    </dialog>
  )
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section>
      <h2>{title}</h2>
      {children}
    </section>
  )
}

function Fields({ fields }: { fields: Record<string, string> }) {
  const entries = Object.entries(fields)
  if (entries.length === 0) return <p className="empty">None</p>
  return (
    <dl>
      {entries.map(([name, value]) => (
        <div key={name}>
          <dt>{name}</dt>
          <dd>{value}</dd>
        </div>
      ))}
    </dl>
  )
}

function RequestDetail({ request, onBack }: { request: RequestEntry; onBack: () => void }) {
  const [menuOpen, setMenuOpen] = useState(false)
  const [status, setStatus] = useState<string>()
  const body = request.requestBody
  return (
    <div className="panel scroll detail">
      <div className="bar">
        <button type="button" onClick={onBack}>
          ‹ Back
        </button>
        <span className="spacer" />
        <button type="button" onClick={() => setMenuOpen(true)}>
          Copy
        </button>
      </div>
      {status && <p className="status">{status}</p>}
      {menuOpen && (
        <CopyMenu
          request={request}
          onClose={(result) => {
            setMenuOpen(false)
            setStatus(result)
          }}
        />
      )}
      <Section title={request.method}>
        <Fields
          fields={{
            URL: request.url,
            Status:
              request.error ?? `${request.status ?? "pending"} ${request.statusText ?? ""}`.trim(),
            Duration: duration(request),
          }}
        />
      </Section>
      {request.responseBody !== undefined ? (
        <Section
          title={request.responseBodyTruncated ? "Response body (truncated)" : "Response body"}
        >
          <pre>{prettyBody(request.responseBody)}</pre>
        </Section>
      ) : (
        <Section title="Response body">
          <pre className="muted">
            {request.endTime === undefined ? "Waiting for response…" : "None"}
          </pre>
        </Section>
      )}
      <Section title="Request headers">
        <Fields fields={request.requestHeaders} />
      </Section>
      {request.cookies && (
        <Section title="Cookies">
          <pre>{request.cookies}</pre>
        </Section>
      )}
      {body && (
        <Section title="Request body">
          {body.kind === "text" && <pre>{prettyBody(body.text)}</pre>}
          {body.kind === "form" && (
            <Fields
              fields={Object.fromEntries(
                body.fields.map((f) => [f.name, f.value ?? `[file ${f.fileName ?? ""}]`]),
              )}
            />
          )}
          {body.kind === "binary" && <p className="empty">Binary body, not captured</p>}
        </Section>
      )}
      {request.responseHeaders && (
        <Section title="Response headers">
          <Fields fields={request.responseHeaders} />
        </Section>
      )}
    </div>
  )
}

function Network({ requests }: { requests: RequestEntry[] }) {
  const [selectedId, setSelectedId] = useState<string>()
  const [menuFor, setMenuFor] = useState<RequestEntry>()
  const [status, setStatus] = useState<string>()
  const selected = requests.find((r) => r.id === selectedId)

  if (selected) return <RequestDetail request={selected} onBack={() => setSelectedId(undefined)} />
  return (
    <div className="panel scroll">
      {status && <p className="status">{status}</p>}
      {requests.length === 0 && <p className="empty">No requests yet.</p>}
      {requests.map((request) => (
        <RequestRow
          key={request.id}
          request={request}
          onSelect={() => setSelectedId(request.id)}
          onMenu={() => setMenuFor(request)}
        />
      ))}
      {menuFor && (
        <CopyMenu
          request={menuFor}
          onClose={(result) => {
            setMenuFor(undefined)
            setStatus(result)
          }}
        />
      )}
    </div>
  )
}

function App() {
  const [tab, setTab] = useState<"console" | "network">("console")
  const query = useEntries()
  const client = useQueryClient()
  const clear = useMutation({
    mutationFn: () => sendToTab({ type: "clear" }),
    onSuccess: () =>
      client.setQueryData<{ tabId: number; entries: Entry[] }>(
        entriesKey,
        (d) => d && { ...d, entries: [] },
      ),
  })

  const entries = query.data?.entries ?? []
  const logs = entries.filter((e): e is LogEntry => e.kind === "log")
  const requests = entries.filter((e): e is RequestEntry => e.kind === "request")

  return (
    <main>
      <nav className="bar">
        <button type="button" aria-pressed={tab === "console"} onClick={() => setTab("console")}>
          Console
        </button>
        <button type="button" aria-pressed={tab === "network"} onClick={() => setTab("network")}>
          Network
        </button>
        <span className="spacer" />
        <button type="button" onClick={() => clear.mutate()}>
          Clear
        </button>
      </nav>
      {query.error ? (
        <p className="error">{query.error.message}</p>
      ) : query.isPending ? (
        <p className="empty">Loading…</p>
      ) : tab === "console" ? (
        <Console logs={logs} />
      ) : (
        <Network requests={requests} />
      )}
    </main>
  )
}

const root = document.getElementById("root")
if (!root) throw new Error("Missing #root")
createRoot(root).render(
  <QueryClientProvider client={queryClient}>
    <App />
  </QueryClientProvider>,
)
