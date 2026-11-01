// Decides how to display a request or response body from its content type, sniffing
// the text when the type is missing. Mirrors Sources/DevToolsCore/BodyFormat.swift;
// keep the two identical (shared cases in body.test.ts and the Swift tests).
import type { RequestEntry } from "./protocol"

export type BodyView =
  | { kind: "json"; text: string }
  | { kind: "form"; fields: [string, string][] }
  | { kind: "xml"; text: string }
  | { kind: "html"; text: string }
  | { kind: "text"; text: string }
  | { kind: "image"; dataUrl: string }

export const bodyLabels: Record<BodyView["kind"], string> = {
  json: "JSON",
  form: "Form",
  xml: "XML",
  html: "HTML",
  text: "Text",
  image: "Image",
}

export const headerValue = (headers: Record<string, string> | undefined, name: string) => {
  if (!headers) return undefined
  const key = Object.keys(headers).find((k) => k.toLowerCase() === name)
  return key === undefined ? undefined : headers[key]
}

const isJson = (text: string) => {
  try {
    JSON.parse(text)
    return true
  } catch {
    return false
  }
}

export const bodyView = ({
  body,
  contentType,
  encoding,
}: {
  body: string
  contentType?: string
  encoding?: "base64"
}): BodyView => {
  const type = (contentType ?? "").toLowerCase()
  if (encoding === "base64") {
    return { kind: "image", dataUrl: `data:${type.split(";")[0] || "image/*"};base64,${body}` }
  }
  const trimmed = body.trimStart()
  // Many APIs send JSON as text/plain, so sniff it there too.
  const sniff = !type || type.startsWith("text/plain")
  if (/json/.test(type) || (sniff && /^[[{]/.test(trimmed))) {
    if (isJson(body)) return { kind: "json", text: indentJson(body) }
  }
  if (type.includes("x-www-form-urlencoded")) {
    return { kind: "form", fields: [...new URLSearchParams(body)] }
  }
  if (/xml/.test(type) || (!type && trimmed.startsWith("<?xml"))) {
    return { kind: "xml", text: indentXml(body) }
  }
  if (type.includes("html") || (!type && /^<(!doctype html|html)/i.test(trimmed))) {
    return { kind: "html", text: body }
  }
  return { kind: "text", text: body }
}

// Re-indents valid JSON without parsing it, so key order and number formatting stay
// exactly as sent.
export const indentJson = (json: string): string => {
  let out = ""
  let depth = 0
  let inString = false
  const newline = () => `\n${"  ".repeat(depth)}`
  for (let i = 0; i < json.length; i++) {
    const char = json[i] as string
    if (inString) {
      out += char
      if (char === "\\") out += json[++i] ?? ""
      else if (char === '"') inString = false
      continue
    }
    if (/\s/.test(char)) continue
    if (char === '"') {
      inString = true
      out += char
    } else if (char === "{" || char === "[") {
      const close = char === "{" ? "}" : "]"
      const next = json.slice(i + 1).trimStart()[0]
      if (next === close) {
        out += char + close
        i = json.indexOf(close, i + 1)
      } else {
        depth++
        out += char + newline()
      }
    } else if (char === "}" || char === "]") {
      depth--
      out += newline() + char
    } else if (char === ",") {
      out += char + newline()
    } else if (char === ":") {
      out += ": "
    } else {
      out += char
    }
  }
  return out
}

// Puts each tag on its own line, indented by nesting. Text between tags keeps its
// own line; whitespace-only text is dropped.
export const indentXml = (xml: string): string => {
  const lines: string[] = []
  let depth = 0
  for (const token of xml.split(/(<[^>]+>)/)) {
    const text = token.trim()
    if (!text) continue
    if (text.startsWith("</")) depth = Math.max(0, depth - 1)
    lines.push("  ".repeat(depth) + text)
    const opens =
      text.startsWith("<") &&
      !text.startsWith("</") &&
      !text.startsWith("<?") &&
      !text.startsWith("<!") &&
      !text.endsWith("/>")
    if (opens) depth++
  }
  return lines.join("\n")
}

export const responseView = (request: RequestEntry): BodyView | undefined =>
  request.responseBody === undefined
    ? undefined
    : bodyView({
        body: request.responseBody,
        contentType: headerValue(request.responseHeaders, "content-type"),
        encoding: request.responseBodyEncoding,
      })

// What "Copy response" puts on the clipboard: the text as captured, or a data URL
// for a captured image.
export const responseCopyText = (request: RequestEntry) => {
  const view = responseView(request)
  return view?.kind === "image" ? view.dataUrl : (request.responseBody ?? "")
}
