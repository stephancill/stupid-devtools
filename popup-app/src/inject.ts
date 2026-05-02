// DevTools Page Injector
// Runs in the actual page context to intercept console, errors, and network

// Prevent multiple injections
if (
  (window as unknown as { __DEVTOOLS_INJECTED__?: boolean })
    .__DEVTOOLS_INJECTED__
) {
  throw new Error("DevTools already injected")
}
;(
  window as unknown as { __DEVTOOLS_INJECTED__?: boolean }
).__DEVTOOLS_INJECTED__ = true

const generateId = () => Math.random().toString(36).substring(2, 15)

// Intercept console methods
const originalConsole = {
  log: console.log.bind(console),
  warn: console.warn.bind(console),
  error: console.error.bind(console),
  info: console.info.bind(console),
}

const interceptConsole = (type: "log" | "warn" | "error" | "info") => {
  console[type] = (...args: unknown[]) => {
    originalConsole[type](...args)

    const serializedArgs = args.map((arg) => {
      try {
        if (arg instanceof Error) {
          return { message: arg.message, stack: arg.stack }
        }
        return JSON.parse(JSON.stringify(arg))
      } catch {
        return String(arg)
      }
    })

    window.postMessage(
      {
        source: "devtools-page",
        type: "CONSOLE_LOG",
        log: {
          id: generateId(),
          type: type,
          args: serializedArgs,
          timestamp: Date.now(),
        },
      },
      "*",
    )
  }
}

;(["log", "warn", "error", "info"] as const).forEach(interceptConsole)

// Intercept runtime errors
window.addEventListener("error", (event) => {
  window.postMessage(
    {
      source: "devtools-page",
      type: "CONSOLE_LOG",
      log: {
        id: generateId(),
        type: "error",
        args: [
          `${event.message} at ${event.filename}:${event.lineno}:${event.colno}`,
        ],
        timestamp: Date.now(),
      },
    },
    "*",
  )
})

// Intercept unhandled promise rejections
window.addEventListener("unhandledrejection", (event) => {
  const reason =
    event.reason instanceof Error
      ? `${event.reason.message}\n${event.reason.stack}`
      : String(event.reason)

  window.postMessage(
    {
      source: "devtools-page",
      type: "CONSOLE_LOG",
      log: {
        id: generateId(),
        type: "error",
        args: [`Unhandled Promise Rejection: ${reason}`],
        timestamp: Date.now(),
      },
    },
    "*",
  )
})

// Helper to extract headers
const headersToObject = (
  headers: HeadersInit | null | undefined,
): Record<string, string> => {
  const obj: Record<string, string> = {}
  if (headers) {
    if (headers instanceof Headers) {
      headers.forEach((value, key) => {
        obj[key] = value
      })
    } else if (Array.isArray(headers)) {
      headers.forEach(([key, value]) => {
        obj[key] = value
      })
    } else {
      Object.assign(obj, headers)
    }
  }
  return obj
}

// Parse document.cookie into key-value pairs
const parseDocumentCookies = (): Record<string, string> => {
  const cookies: Record<string, string> = {}
  document.cookie.split(";").forEach((c) => {
    const trimmed = c.trim()
    const eqIdx = trimmed.indexOf("=")
    if (eqIdx > 0) {
      cookies[trimmed.substring(0, eqIdx)] = trimmed.substring(eqIdx + 1)
    }
  })
  return cookies
}

// Parse Set-Cookie header value into name=value (ignores attributes)
const parseSetCookieValue = (value: string): Record<string, string> => {
  const cookies: Record<string, string> = {}
  const match = value.match(/^([^=]+)=([^;]*)/)
  if (match) {
    cookies[match[1]] = match[2]
  }
  return cookies
}

// Intercept fetch
const originalFetch = window.fetch
window.fetch = async function (
  input: RequestInfo | URL,
  init?: RequestInit,
): Promise<Response> {
  const id = generateId()
  const url =
    typeof input === "string"
      ? input
      : input instanceof URL
        ? input.href
        : input.url
  const method =
    init?.method || (input instanceof Request ? input.method : "GET") || "GET"
  const requestHeaders = headersToObject(
    init?.headers || (input instanceof Request ? undefined : undefined),
  )
  let requestBody: string | null = null

  try {
    if (init?.body) {
      if (typeof init.body === "string") {
        requestBody = init.body
      } else if (init.body instanceof FormData) {
        requestBody = "[FormData]"
      } else {
        requestBody = "[Binary Data]"
      }
    }
  } catch {
    // ignore
  }

  window.postMessage(
    {
      source: "devtools-page",
      type: "NETWORK_REQUEST",
      request: {
        id,
        method: method.toUpperCase(),
        url,
        requestHeaders,
        requestBody,
        requestCookies: parseDocumentCookies(),
        startTime: Date.now(),
      },
    },
    "*",
  )

  try {
    const response = await originalFetch.call(this, input, init)
    const clonedResponse = response.clone()

    // Extract response headers and cookies
    const responseHeaders: Record<string, string> = {}
    const responseCookies: Record<string, string> = {}
    response.headers.forEach((value, key) => {
      responseHeaders[key] = value
      if (key.toLowerCase() === "set-cookie") {
        Object.assign(responseCookies, parseSetCookieValue(value))
      }
    })

    // Try to get response body
    let responseBody: string | null = null
    try {
      const contentType = response.headers.get("content-type") || ""
      if (contentType.includes("application/json")) {
        responseBody = await clonedResponse.text()
      } else if (contentType.includes("text/")) {
        responseBody = await clonedResponse.text()
        if (responseBody.length > 10000) {
          responseBody = `${responseBody.substring(0, 10000)}... [truncated]`
        }
      } else {
        responseBody = `[Binary Data: ${contentType}]`
      }
    } catch {
      // ignore
    }

    window.postMessage(
      {
        source: "devtools-page",
        type: "NETWORK_REQUEST",
        request: {
          id,
          method: method.toUpperCase(),
          url,
          status: response.status,
          statusText: response.statusText,
          responseHeaders,
          responseBody,
          responseCookies,
          startTime: 0,
          endTime: Date.now(),
        },
      },
      "*",
    )

    return response
  } catch (error) {
    window.postMessage(
      {
        source: "devtools-page",
        type: "NETWORK_REQUEST",
        request: {
          id,
          method: method.toUpperCase(),
          url,
          error: error instanceof Error ? error.message : String(error),
          startTime: 0,
          endTime: Date.now(),
        },
      },
      "*",
    )
    throw error
  }
}

// Intercept XMLHttpRequest
const originalXHROpen = XMLHttpRequest.prototype.open
const originalXHRSend = XMLHttpRequest.prototype.send
const originalXHRSetRequestHeader = XMLHttpRequest.prototype.setRequestHeader

interface DevToolsXHR extends XMLHttpRequest {
  _devtools?: {
    id: string
    method: string
    url: string
    requestHeaders: Record<string, string>
    requestBody?: string | null
    startTime: number
  }
}

XMLHttpRequest.prototype.open = function (
  this: DevToolsXHR,
  method: string,
  url: string | URL,
  async?: boolean,
  username?: string | null,
  password?: string | null,
) {
  this._devtools = {
    id: generateId(),
    method: method.toUpperCase(),
    url: String(url),
    requestHeaders: {},
    startTime: 0,
  }
  return originalXHROpen.call(
    this,
    method,
    url,
    async ?? true,
    username,
    password,
  )
}

XMLHttpRequest.prototype.setRequestHeader = function (
  this: DevToolsXHR,
  name: string,
  value: string,
) {
  if (this._devtools) {
    this._devtools.requestHeaders[name] = value
  }
  return originalXHRSetRequestHeader.call(this, name, value)
}

XMLHttpRequest.prototype.send = function (
  this: DevToolsXHR,
  body?: Document | XMLHttpRequestBodyInit | null,
) {
  if (this._devtools) {
    const devtools = this._devtools
    devtools.startTime = Date.now()
    devtools.requestBody = body
      ? typeof body === "string"
        ? body
        : "[Binary Data]"
      : null

    window.postMessage(
      {
        source: "devtools-page",
        type: "NETWORK_REQUEST",
        request: {
          id: devtools.id,
          method: devtools.method,
          url: devtools.url,
          requestHeaders: devtools.requestHeaders,
          requestBody: devtools.requestBody,
          requestCookies: parseDocumentCookies(),
          startTime: devtools.startTime,
        },
      },
      "*",
    )

    this.addEventListener("load", () => {
      // Parse response headers and cookies
      const responseHeaders: Record<string, string> = {}
      const responseCookies: Record<string, string> = {}
      const headerLines = this.getAllResponseHeaders().trim().split("\r\n")
      headerLines.forEach((line) => {
        const idx = line.indexOf(": ")
        if (idx > 0) {
          const key = line.substring(0, idx)
          const value = line.substring(idx + 2)
          responseHeaders[key] = value
          if (key.toLowerCase() === "set-cookie") {
            Object.assign(responseCookies, parseSetCookieValue(value))
          }
        }
      })

      // Get response body
      let responseBody: string | null = null
      try {
        if (this.responseType === "" || this.responseType === "text") {
          responseBody = this.responseText
          if (responseBody && responseBody.length > 10000) {
            responseBody = `${responseBody.substring(0, 10000)}... [truncated]`
          }
        } else if (this.responseType === "json") {
          responseBody = JSON.stringify(this.response)
        } else {
          responseBody = "[Binary Data]"
        }
      } catch {
        // ignore
      }

      window.postMessage(
        {
          source: "devtools-page",
          type: "NETWORK_REQUEST",
          request: {
            id: devtools.id,
            method: devtools.method,
            url: devtools.url,
            status: this.status,
            statusText: this.statusText,
            responseHeaders,
            responseBody,
            responseCookies,
            startTime: devtools.startTime,
            endTime: Date.now(),
          },
        },
        "*",
      )
    })

    this.addEventListener("error", () => {
      window.postMessage(
        {
          source: "devtools-page",
          type: "NETWORK_REQUEST",
          request: {
            id: devtools.id,
            method: devtools.method,
            url: devtools.url,
            error: "Network error",
            startTime: devtools.startTime,
            endTime: Date.now(),
          },
        },
        "*",
      )
    })
  }

  return originalXHRSend.call(this, body)
}
