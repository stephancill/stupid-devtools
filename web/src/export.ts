// Rebuilds a captured request as a cURL command or a fetch() call. Mirrors
// Sources/DevToolsCore/RequestExport.swift; keep the output of the two identical.
import type { RequestEntry } from "./protocol"

// Headers the browser sets itself; copying them would only add noise.
const skippedHeaders = new Set(["content-length", "host"])

// Sorted so the Swift exporter, which reads headers from a dictionary, matches.
const headersOf = (request: RequestEntry) =>
  Object.entries(request.requestHeaders)
    .filter(([name]) => !skippedHeaders.has(name.toLowerCase()))
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))

const hasCookieHeader = (request: RequestEntry) =>
  Object.keys(request.requestHeaders).some((name) => name.toLowerCase() === "cookie")

const shellQuote = (value: string) => `'${value.replaceAll("'", `'\\''`)}'`

export const toCurl = (request: RequestEntry): string => {
  const parts = [`curl ${shellQuote(request.url)}`]
  const body = request.requestBody
  const impliedMethod = body && body.kind !== "binary" ? "POST" : "GET"
  if (request.method !== impliedMethod) parts.push(`-X ${request.method}`)
  for (const [name, value] of headersOf(request))
    parts.push(`-H ${shellQuote(`${name}: ${value}`)}`)
  if (request.cookies && !hasCookieHeader(request)) parts.push(`-b ${shellQuote(request.cookies)}`)
  const notes: string[] = []
  if (body?.kind === "text") parts.push(`--data-raw ${shellQuote(body.text)}`)
  if (body?.kind === "form") {
    for (const field of body.fields) {
      if (field.value !== undefined) {
        parts.push(`-F ${shellQuote(`${field.name}=${field.value}`)}`)
      } else {
        parts.push(`-F ${shellQuote(`${field.name}=@${field.fileName ?? "file"}`)}`)
      }
    }
  }
  if (body?.kind === "binary")
    notes.push(`# binary request body (${byteLabel(body.byteLength)}) not captured`)
  return [parts.join(" \\\n  "), ...notes].join("\n")
}

export const toFetch = (request: RequestEntry): string => {
  const lines: string[] = []
  const options: string[] = []
  if (request.method !== "GET") options.push(`method: ${JSON.stringify(request.method)}`)
  const headers = headersOf(request)
  if (headers.length > 0) {
    const fields = headers.map(
      ([name, value]) => `    ${JSON.stringify(name)}: ${JSON.stringify(value)},`,
    )
    options.push(`headers: {\n${fields.join("\n")}\n  }`)
  }
  const body = request.requestBody
  if (body?.kind === "text") options.push(`body: ${JSON.stringify(body.text)}`)
  if (body?.kind === "form") {
    lines.push("const body = new FormData()")
    for (const field of body.fields) {
      if (field.value !== undefined) {
        lines.push(`body.append(${JSON.stringify(field.name)}, ${JSON.stringify(field.value)})`)
      } else {
        lines.push(
          `// file field ${JSON.stringify(field.name)} (${field.fileName ?? "file"}) not captured`,
        )
      }
    }
    options.push("body")
  }
  if (body?.kind === "binary")
    lines.push(`// binary request body (${byteLabel(body.byteLength)}) not captured`)
  if (request.cookies) options.push(`credentials: "include"`)
  const init = options.length > 0 ? `, {\n${options.map((o) => `  ${o},`).join("\n")}\n}` : ""
  lines.push(`await fetch(${JSON.stringify(request.url)}${init})`)
  return lines.join("\n")
}

const byteLabel = (byteLength?: number) =>
  byteLength === undefined ? "unknown size" : `${byteLength} bytes`
