import { ArrowLeft } from "lucide-react"
import { useState } from "react"
import type { NetworkEntry } from "@/types"

interface NetworkProps {
  requests: NetworkEntry[]
}

export function Network({ requests }: NetworkProps) {
  const [selected, setSelected] = useState<NetworkEntry | null>(null)

  const getStatusClass = (status?: number) => {
    if (!status) return "status-pending"
    if (status >= 200 && status < 300) return "status-success"
    if (status >= 300 && status < 400) return "status-redirect"
    if (status >= 400) return "status-error"
    return ""
  }

  const formatDuration = (entry: NetworkEntry) => {
    if (!entry.endTime) return "pending"
    const ms = entry.endTime - entry.startTime
    if (ms < 1000) return `${ms}ms`
    return `${(ms / 1000).toFixed(2)}s`
  }

  const formatBody = (body: string | null | undefined) => {
    if (!body) return null
    try {
      const parsed = JSON.parse(body)
      return JSON.stringify(parsed, null, 2)
    } catch {
      return body
    }
  }

  const getUrlName = (url: string) => {
    try {
      const u = new URL(url)
      return u.pathname + u.search
    } catch {
      return url
    }
  }

  if (selected) {
    return (
      <div className="devtools-panel h-full overflow-auto">
        <div className="network-detail-header">
          <button
            type="button"
            className="toolbar-btn flex items-center gap-1"
            onClick={() => setSelected(null)}
          >
            <ArrowLeft size={14} />
            Back
          </button>
        </div>

        <div className="network-detail-section">
          <div className="network-detail-title">General</div>
          <div className="network-detail-row">
            <span className="network-detail-key">Request URL:</span>
            <span className="network-detail-value">{selected.url}</span>
          </div>
          <div className="network-detail-row">
            <span className="network-detail-key">Request Method:</span>
            <span className="network-detail-value">{selected.method}</span>
          </div>
          <div className="network-detail-row">
            <span className="network-detail-key">Status Code:</span>
            <span
              className={`network-detail-value ${getStatusClass(selected.status)}`}
            >
              {selected.status} {selected.statusText}
            </span>
          </div>
          <div className="network-detail-row">
            <span className="network-detail-key">Duration:</span>
            <span className="network-detail-value">
              {formatDuration(selected)}
            </span>
          </div>
          {selected.error && (
            <div className="network-detail-row">
              <span className="network-detail-key">Error:</span>
              <span className="network-detail-value status-error">
                {selected.error}
              </span>
            </div>
          )}
        </div>

        {selected.requestHeaders &&
          Object.keys(selected.requestHeaders).length > 0 && (
            <div className="network-detail-section">
              <div className="network-detail-title">Request Headers</div>
              {Object.entries(selected.requestHeaders).map(([k, v]) => (
                <div key={k} className="network-detail-row">
                  <span className="network-detail-key">{k}:</span>
                  <span className="network-detail-value">{v}</span>
                </div>
              ))}
            </div>
          )}

        {selected.requestBody && (
          <div className="network-detail-section">
            <div className="network-detail-title">Request Payload</div>
            <pre className="network-detail-value whitespace-pre-wrap break-all text-[11px]">
              {formatBody(selected.requestBody)}
            </pre>
          </div>
        )}

        {selected.requestCookies &&
          Object.keys(selected.requestCookies).length > 0 && (
            <div className="network-detail-section">
              <div className="network-detail-title">Request Cookies</div>
              {Object.entries(selected.requestCookies).map(([k, v]) => (
                <div key={k} className="network-detail-row">
                  <span className="network-detail-key">{k}:</span>
                  <span className="network-detail-value">{v}</span>
                </div>
              ))}
            </div>
          )}

        {selected.responseHeaders &&
          Object.keys(selected.responseHeaders).length > 0 && (
            <div className="network-detail-section">
              <div className="network-detail-title">Response Headers</div>
              {Object.entries(selected.responseHeaders).map(([k, v]) => (
                <div key={k} className="network-detail-row">
                  <span className="network-detail-key">{k}:</span>
                  <span className="network-detail-value">{v}</span>
                </div>
              ))}
            </div>
          )}

        {selected.responseBody && (
          <div className="network-detail-section">
            <div className="network-detail-title">Response</div>
            <pre className="network-detail-value whitespace-pre-wrap break-all text-[11px]">
              {formatBody(selected.responseBody)}
            </pre>
          </div>
        )}

        {selected.responseCookies &&
          Object.keys(selected.responseCookies).length > 0 && (
            <div className="network-detail-section">
              <div className="network-detail-title">Response Cookies</div>
              {Object.entries(selected.responseCookies).map(([k, v]) => (
                <div key={k} className="network-detail-row">
                  <span className="network-detail-key">{k}:</span>
                  <span className="network-detail-value">{v}</span>
                </div>
              ))}
            </div>
          )}
      </div>
    )
  }

  return (
    <div className="devtools-panel h-full flex flex-col">
      {/* Table header */}
      <div className="network-header">
        <span className="network-col-method">Method</span>
        <span className="network-col-status">Status</span>
        <span className="network-col-time">Time</span>
        <span className="network-col-name">Name</span>
      </div>

      {/* Table body */}
      <div className="flex-1 overflow-auto">
        {requests.length === 0 ? (
          <div className="empty-state">Recording network activity...</div>
        ) : (
          requests.map((req) => (
            <button
              type="button"
              key={req.id}
              onClick={() => setSelected(req)}
              className="network-row w-full text-left"
            >
              <span className="network-col-method">{req.method}</span>
              <span
                className={`network-col-status ${getStatusClass(req.status)}`}
              >
                {req.status ?? "..."}
              </span>
              <span className="network-col-time">{formatDuration(req)}</span>
              <span className="network-col-name">
                {req.error ? (
                  <span className="status-error">{req.error}</span>
                ) : (
                  getUrlName(req.url)
                )}
              </span>
            </button>
          ))
        )}
      </div>
    </div>
  )
}
