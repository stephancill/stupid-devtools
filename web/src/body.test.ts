import { expect, test } from "bun:test"
import { bodyView } from "./body"

// The same cases as Tests/DevToolsCoreTests (BodyFormatTests).

test("JSON keeps key order and string contents", () => {
  expect(
    bodyView({
      body: '{"b":1,"a":[1,{"c":"x,y"}],"e":{},"s":"q\\"}"}',
      contentType: "application/json; charset=utf-8",
    }),
  ).toEqual({
    kind: "json",
    text: [
      "{",
      '  "b": 1,',
      '  "a": [',
      "    1,",
      "    {",
      '      "c": "x,y"',
      "    }",
      "  ],",
      '  "e": {},',
      '  "s": "q\\"}"',
      "}",
    ].join("\n"),
  })
})

test("JSON is sniffed without a content type", () => {
  expect(bodyView({ body: " [1, 2]" })).toEqual({ kind: "json", text: "[\n  1,\n  2\n]" })
})

test("JSON is sniffed in text/plain", () => {
  expect(bodyView({ body: '{"a":1}', contentType: "text/plain;charset=utf-8" })).toEqual({
    kind: "json",
    text: '{\n  "a": 1\n}',
  })
})

test("invalid JSON falls back to text", () => {
  expect(bodyView({ body: "{nope", contentType: "application/json" })).toEqual({
    kind: "text",
    text: "{nope",
  })
})

test("form bodies become fields", () => {
  expect(
    bodyView({
      body: "a=1&b=two%20words&a=3",
      contentType: "application/x-www-form-urlencoded",
    }),
  ).toEqual({
    kind: "form",
    fields: [
      ["a", "1"],
      ["b", "two words"],
      ["a", "3"],
    ],
  })
})

test("XML is indented", () => {
  expect(bodyView({ body: '<?xml version="1.0"?><a><b>t</b><c/></a>' })).toEqual({
    kind: "xml",
    text: ['<?xml version="1.0"?>', "<a>", "  <b>", "    t", "  </b>", "  <c/>", "</a>"].join("\n"),
  })
})

test("HTML and plain text are shown as sent", () => {
  expect(bodyView({ body: "<!doctype html><p>hi</p>" })).toEqual({
    kind: "html",
    text: "<!doctype html><p>hi</p>",
  })
  expect(bodyView({ body: "hello", contentType: "text/plain" })).toEqual({
    kind: "text",
    text: "hello",
  })
})

test("base64 bodies are images", () => {
  expect(bodyView({ body: "AAAA", contentType: "image/png", encoding: "base64" })).toEqual({
    kind: "image",
    dataUrl: "data:image/png;base64,AAAA",
  })
})
