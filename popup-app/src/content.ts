// DevTools Content Script
// Runs in isolated content script context, bridges page and extension

// Prevent multiple injections
if (
  (window as unknown as { __DEVTOOLS_CONTENT_INJECTED__?: boolean })
    .__DEVTOOLS_CONTENT_INJECTED__
) {
  throw new Error("DevTools content script already injected")
}
;(
  window as unknown as { __DEVTOOLS_CONTENT_INJECTED__?: boolean }
).__DEVTOOLS_CONTENT_INJECTED__ = true

interface LogMessage {
  id: string
  type: "log" | "warn" | "error" | "info"
  args: unknown[]
  timestamp: number
}

interface NetworkMessage {
  id: string
  method: string
  url: string
  status?: number
  statusText?: string
  startTime: number
  endTime?: number
  requestHeaders?: Record<string, string>
  requestBody?: string | null
  requestCookies?: Record<string, string>
  responseHeaders?: Record<string, string>
  responseBody?: string | null
  responseCookies?: Record<string, string>
  error?: string
}

interface DevToolsMessage {
  source: "devtools-page"
  type: "CONSOLE_LOG" | "NETWORK_REQUEST"
  log?: LogMessage
  request?: NetworkMessage
}

// Inject the page script
const script = document.createElement("script")
script.src = browser.runtime.getURL("inject.js")
script.onload = () => script.remove()
;(document.head || document.documentElement).appendChild(script)

// Listen for messages from injected script
window.addEventListener("message", (event) => {
  if (
    event.source !== window ||
    !event.data ||
    event.data.source !== "devtools-page"
  ) {
    return
  }

  const message = event.data as DevToolsMessage

  if (message.type === "CONSOLE_LOG" && message.log) {
    browser.runtime.sendMessage({ type: "CONSOLE_LOG", log: message.log })
  } else if (message.type === "NETWORK_REQUEST" && message.request) {
    browser.runtime.sendMessage({
      type: "NETWORK_REQUEST",
      request: message.request,
    })
  }
})

// Listen for execute commands from popup
browser.runtime.onMessage.addListener((msg: unknown) => {
  const message = msg as { type: string; code?: string }
  if (message.type === "EXECUTE_JS" && message.code) {
    const execScript = document.createElement("script")
    execScript.textContent = `
      try {
        const result = eval(${JSON.stringify(message.code)});
        if (result !== undefined) {
          console.log(result);
        }
      } catch (error) {
        console.error(error.message);
      }
    `
    ;(document.head || document.documentElement).appendChild(execScript)
    execScript.remove()
  }
})
