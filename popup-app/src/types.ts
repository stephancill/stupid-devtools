export interface LogEntry {
  id: string
  type: "log" | "warn" | "error" | "info"
  args: unknown[]
  timestamp: number
}

export interface NetworkEntry {
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

export interface DataResponse {
  logs: LogEntry[]
  requests: NetworkEntry[]
}

declare global {
  const browser: {
    runtime: {
      sendMessage: (message: unknown) => Promise<DataResponse | undefined>
      onMessage: {
        addListener: (callback: (message: unknown) => void) => void
        removeListener: (callback: (message: unknown) => void) => void
      }
      getURL: (path: string) => string
    }
    tabs: {
      query: (options: {
        active: boolean
        currentWindow: boolean
      }) => Promise<{ id?: number }[]>
      sendMessage: (tabId: number, message: unknown) => Promise<unknown>
    }
  }
}
