// Runs in the page's MAIN world at document_start (see manifest.json), so it is in
// place before any page script. Captures console output, errors and network traffic
// and hands each entry to content.js as a DOM event.
import { formatConsoleArgs, formatValueForDisplay } from "./format"
import {
  type Entry,
  type LogLevel,
  type RequestBody,
  type RequestEntry,
  entryEvent,
  evalEvent,
  maxBodyLength,
  maxImageBytes,
} from "./protocol"

const installed = "__stupidDevtoolsInstalled"
const flags = window as unknown as Record<string, boolean>

if (!flags[installed]) {
  flags[installed] = true
  install()
}

function install() {
  const dispatch = document.dispatchEvent.bind(document)
  const emit = (entry: Entry) => {
    dispatch(new CustomEvent(entryEvent, { detail: JSON.stringify(entry) }))
  }

  const randomId = () => {
    const bytes = crypto.getRandomValues(new Uint8Array(12))
    return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("")
  }

  const log = (level: LogLevel, message: string) => {
    emit({ kind: "log", id: randomId(), level, message, time: Date.now() })
  }

  // Console. A getter or toString on a logged value may itself log; the guard stops
  // that from recursing.
  let formatting = false
  for (const level of ["log", "info", "warn", "error", "debug"] as const) {
    const original = console[level]
    console[level] = function (...args: unknown[]) {
      original.apply(this, args)
      if (formatting) return
      formatting = true
      try {
        log(level, formatConsoleArgs(args))
      } finally {
        formatting = false
      }
    }
  }

  window.addEventListener("error", (event) => {
    // Resource load failures (img, script) bubble here without a message.
    if (!(event instanceof ErrorEvent)) return
    const location = event.filename ? ` (${event.filename}:${event.lineno}:${event.colno})` : ""
    log("error", event.error ? formatValueForDisplay(event.error) : `${event.message}${location}`)
  })

  window.addEventListener("unhandledrejection", (event) => {
    log("error", `Uncaught (in promise) ${formatValueForDisplay(event.reason)}`)
  })

  // Console input from the popup. Uses indirect eval so code runs in global scope;
  // pages whose CSP forbids 'unsafe-eval' will reject it and the error is shown.
  document.addEventListener(evalEvent, (event) => {
    const code = (event as CustomEvent<unknown>).detail
    if (typeof code !== "string") return
    log("command", code)
    try {
      // oxlint-disable-next-line no-eval -- running console input is the point
      const result: unknown = (0, eval)(code)
      if (result instanceof Promise) {
        result.then(
          (value) => log("result", `Promise {<fulfilled>: ${formatValueForDisplay(value)}}`),
          (error) => log("error", `Uncaught (in promise) ${formatValueForDisplay(error)}`),
        )
      } else {
        // Quote strings so "1" and 1 read differently, as desktop consoles do.
        log(
          "result",
          typeof result === "string" ? JSON.stringify(result) : formatValueForDisplay(result),
        )
      }
    } catch (error) {
      log("error", `Uncaught ${formatValueForDisplay(error)}`)
    }
  })

  // Network helpers.
  const absoluteUrl = (url: string) => {
    try {
      return new URL(url, location.href).href
    } catch {
      return url
    }
  }

  const sameOriginCookies = (url: string) => {
    try {
      if (new URL(url).origin !== location.origin) return undefined
      return document.cookie || undefined
    } catch {
      // Sandboxed frames throw on document.cookie.
      return undefined
    }
  }

  const describeBody = (body: unknown): RequestBody | undefined => {
    if (body === null || body === undefined) return undefined
    if (typeof body === "string") return { kind: "text", text: body }
    if (body instanceof URLSearchParams) return { kind: "text", text: body.toString() }
    if (body instanceof FormData) {
      const fields = [...body].map(([name, value]) =>
        typeof value === "string" ? { name, value } : { name, fileName: value.name },
      )
      return { kind: "form", fields }
    }
    if (body instanceof Blob) return { kind: "binary", byteLength: body.size }
    if (body instanceof ArrayBuffer || ArrayBuffer.isView(body)) {
      return { kind: "binary", byteLength: body.byteLength }
    }
    return { kind: "binary" }
  }

  const isTextual = (contentType: string | null) =>
    !contentType || /json|text\/|javascript|xml|x-www-form-urlencoded|graphql/i.test(contentType)

  const isImage = (contentType: string | null) =>
    !!contentType && /^image\//i.test(contentType) && !/svg/i.test(contentType)

  const base64 = (bytes: Uint8Array) => {
    let binary = ""
    for (let i = 0; i < bytes.length; i += 0x8000) {
      binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000))
    }
    return btoa(binary)
  }

  // Captures small images for previewing; larger ones only report their size.
  const imageBody = async (blob: Blob): Promise<Partial<RequestEntry>> =>
    blob.size > maxImageBytes
      ? { responseBody: `[image, ${blob.size} bytes, too large to preview]` }
      : {
          responseBody: base64(new Uint8Array(await blob.arrayBuffer())),
          responseBodyEncoding: "base64",
        }

  const truncate = (text: string) =>
    text.length > maxBodyLength
      ? { body: text.slice(0, maxBodyLength), truncated: true }
      : { body: text, truncated: false }

  // Reads at most maxBodyLength characters, then cancels, so large or streamed
  // responses are never buffered in full.
  const readBody = async (response: Response) => {
    if (!response.body) return { body: "", truncated: false }
    const reader = response.body.getReader()
    const decoder = new TextDecoder()
    let text = ""
    while (text.length <= maxBodyLength) {
      const { done, value } = await reader.read()
      if (done) return truncate(text + decoder.decode())
      text += decoder.decode(value, { stream: true })
    }
    reader.cancel().catch(() => {})
    return truncate(text)
  }

  const errorMessage = (error: unknown) => (error instanceof Error ? error.message : String(error))

  // fetch
  const nativeFetch = window.fetch
  const patchedFetch = function (input: RequestInfo | URL, init?: RequestInit) {
    const request = input instanceof Request ? input : undefined
    const headers = new Headers(request?.headers)
    for (const [name, value] of new Headers(init?.headers)) headers.set(name, value)

    const entry: RequestEntry = {
      kind: "request",
      id: randomId(),
      initiator: "fetch",
      method: (init?.method ?? request?.method ?? "GET").toUpperCase(),
      url: absoluteUrl(request ? request.url : String(input)),
      requestHeaders: Object.fromEntries(headers),
      requestBody: describeBody(init?.body),
      startTime: Date.now(),
    }
    if ((init?.credentials ?? request?.credentials) !== "omit") {
      entry.cookies = sameOriginCookies(entry.url)
    }

    // A Request object's body is only readable from a clone, and reading is async.
    const bodyRead =
      init?.body === undefined && request?.body
        ? request
            .clone()
            .text()
            .then((text) => {
              entry.requestBody = { kind: "text", text }
            })
            .catch(() => {
              entry.requestBody = { kind: "binary" }
            })
        : Promise.resolve()

    emit(entry)

    const finish = (fields: Partial<RequestEntry>) => {
      bodyRead.finally(() => emit(Object.assign(entry, fields, { endTime: Date.now() })))
    }

    const pending = nativeFetch.call(window, input, init)
    pending.then(
      (response) => {
        Object.assign(entry, {
          status: response.status,
          statusText: response.statusText,
          responseHeaders: Object.fromEntries(response.headers),
        })
        if (response.type === "opaque" || response.type === "opaqueredirect") {
          finish({ responseBody: "[opaque response, body unavailable]" })
        } else if (isImage(response.headers.get("content-type"))) {
          const length = Number(response.headers.get("content-length") ?? 0)
          if (length > maxImageBytes) {
            finish({ responseBody: `[image, ${length} bytes, too large to preview]` })
          } else {
            response
              .clone()
              .blob()
              .then(imageBody)
              .then(finish, (error) =>
                finish({ error: `Failed to read body: ${errorMessage(error)}` }),
              )
          }
        } else if (!isTextual(response.headers.get("content-type"))) {
          finish({ responseBody: `[binary: ${response.headers.get("content-type")}]` })
        } else {
          // Show the status while the body downloads; the page's response is untouched.
          emit(entry)
          readBody(response.clone()).then(
            ({ body, truncated }) =>
              finish({ responseBody: body, responseBodyTruncated: truncated }),
            (error) => finish({ error: `Failed to read body: ${errorMessage(error)}` }),
          )
        }
      },
      (error) => finish({ error: errorMessage(error) }),
    )
    return pending
  }
  window.fetch = Object.assign(patchedFetch, { preconnect: nativeFetch.preconnect })

  // XMLHttpRequest
  type TrackedXHR = XMLHttpRequest & { __stupidDevtools?: RequestEntry }
  const xhr = XMLHttpRequest.prototype
  const { open, send, setRequestHeader } = xhr

  xhr.open = function (this: TrackedXHR, method: string, url: string | URL, ...rest: unknown[]) {
    this.__stupidDevtools = {
      kind: "request",
      id: randomId(),
      initiator: "xhr",
      method: method.toUpperCase(),
      url: absoluteUrl(String(url)),
      requestHeaders: {},
      startTime: 0,
    }
    return (open as (...args: unknown[]) => void).call(this, method, url, ...rest)
  }

  xhr.setRequestHeader = function (this: TrackedXHR, name: string, value: string) {
    const entry = this.__stupidDevtools
    if (entry) entry.requestHeaders[name.toLowerCase()] = value
    return setRequestHeader.call(this, name, value)
  }

  xhr.send = function (this: TrackedXHR, body?: Document | XMLHttpRequestBodyInit | null) {
    const entry = this.__stupidDevtools
    if (entry) {
      entry.startTime = Date.now()
      entry.requestBody = describeBody(body)
      entry.cookies = sameOriginCookies(entry.url)
      emit(entry)

      let failure = "Network error"
      this.addEventListener("abort", () => (failure = "Aborted"))
      this.addEventListener("timeout", () => (failure = "Timed out"))
      this.addEventListener("loadend", () => {
        if (this.status === 0) {
          emit(Object.assign(entry, { error: failure, endTime: Date.now() }))
          return
        }
        const responseHeaders: Record<string, string> = {}
        for (const line of this.getAllResponseHeaders().trim().split(/\r?\n/)) {
          const index = line.indexOf(":")
          if (index > 0) {
            responseHeaders[line.slice(0, index).trim().toLowerCase()] = line
              .slice(index + 1)
              .trim()
          }
        }
        const done = (body: Partial<RequestEntry>) =>
          emit(
            Object.assign(entry, {
              status: this.status,
              statusText: this.statusText,
              responseHeaders,
              ...body,
              endTime: Date.now(),
            }),
          )
        const text = (value: string) => {
          const { body, truncated } = truncate(value)
          return { responseBody: body, responseBodyTruncated: truncated }
        }
        if (this.responseType === "" || this.responseType === "text") {
          done(text(this.responseText))
        } else if (this.responseType === "json") {
          done(text(JSON.stringify(this.response)))
        } else if (isImage(responseHeaders["content-type"] ?? null) && this.response) {
          const blob = this.response instanceof Blob ? this.response : new Blob([this.response])
          imageBody(blob).then(done, () => done({ responseBody: "[image, unreadable]" }))
        } else {
          done({ responseBody: `[${this.responseType} response]` })
        }
      })
    }
    return send.call(this, body)
  }
}
