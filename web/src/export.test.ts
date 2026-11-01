import { expect, test } from "bun:test"
import { toCurl, toFetch } from "./export"
import type { RequestEntry } from "./protocol"

const base: RequestEntry = {
  kind: "request",
  id: "1",
  initiator: "fetch",
  method: "GET",
  url: "https://example.com/a?b=1",
  requestHeaders: {},
  startTime: 0,
}

test("GET with no extras", () => {
  expect(toCurl(base)).toBe("curl 'https://example.com/a?b=1'")
  expect(toFetch(base)).toBe('await fetch("https://example.com/a?b=1")')
})

test("POST with headers, quotes and cookies", () => {
  const request: RequestEntry = {
    ...base,
    method: "POST",
    requestHeaders: { "content-type": "application/json", "content-length": "9" },
    requestBody: { kind: "text", text: `{"a":"it's"}` },
    cookies: "session=abc",
  }
  expect(toCurl(request)).toBe(
    [
      "curl 'https://example.com/a?b=1' \\",
      "  -H 'content-type: application/json' \\",
      "  -b 'session=abc' \\",
      `  --data-raw '{"a":"it'\\''s"}'`,
    ].join("\n"),
  )
  expect(toFetch(request)).toBe(
    [
      'await fetch("https://example.com/a?b=1", {',
      '  method: "POST",',
      "  headers: {",
      '    "content-type": "application/json",',
      "  },",
      '  body: "{\\"a\\":\\"it\'s\\"}",',
      '  credentials: "include",',
      "})",
    ].join("\n"),
  )
})

test("PUT keeps -X, form data uses -F", () => {
  const request: RequestEntry = {
    ...base,
    method: "PUT",
    requestBody: {
      kind: "form",
      fields: [
        { name: "a", value: "1" },
        { name: "f", fileName: "x.png" },
      ],
    },
  }
  expect(toCurl(request)).toBe(
    "curl 'https://example.com/a?b=1' \\\n  -X PUT \\\n  -F 'a=1' \\\n  -F 'f=@x.png'",
  )
  expect(toFetch(request)).toBe(
    [
      "const body = new FormData()",
      'body.append("a", "1")',
      '// file field "f" (x.png) not captured',
      'await fetch("https://example.com/a?b=1", {',
      '  method: "PUT",',
      "  body,",
      "})",
    ].join("\n"),
  )
})

test("binary body is noted, not invented", () => {
  const request: RequestEntry = {
    ...base,
    method: "POST",
    requestBody: { kind: "binary", byteLength: 4 },
  }
  expect(toCurl(request)).toBe(
    "curl 'https://example.com/a?b=1' \\\n  -X POST\n# binary request body (4 bytes) not captured",
  )
})
