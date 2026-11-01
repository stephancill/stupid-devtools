import Foundation
import Testing

@testable import DevToolsCore

private let base = RequestEntry(
  id: "1", method: "GET", url: "https://example.com/a?b=1", startTime: 0)

// The same cases as web/src/export.test.ts, so the app and popup copy identical text.
@Suite struct RequestExportTests {
  @Test func plainGet() {
    #expect(RequestExport.curl(base) == "curl 'https://example.com/a?b=1'")
    #expect(RequestExport.fetch(base) == #"await fetch("https://example.com/a?b=1")"#)
  }

  @Test func postWithHeadersQuotesAndCookies() {
    var request = base
    request.method = "POST"
    request.requestHeaders = ["content-type": "application/json", "content-length": "9"]
    request.requestBody = .text(#"{"a":"it's"}"#)
    request.cookies = "session=abc"
    #expect(
      RequestExport.curl(request)
        == [
          #"curl 'https://example.com/a?b=1' \"#,
          #"  -H 'content-type: application/json' \"#,
          #"  -b 'session=abc' \"#,
          #"  --data-raw '{"a":"it'\''s"}'"#,
        ].joined(separator: "\n"))
    #expect(
      RequestExport.fetch(request)
        == [
          #"await fetch("https://example.com/a?b=1", {"#,
          #"  method: "POST","#,
          "  headers: {",
          #"    "content-type": "application/json","#,
          "  },",
          #"  body: "{\"a\":\"it's\"}","#,
          #"  credentials: "include","#,
          "})",
        ].joined(separator: "\n"))
  }

  @Test func putWithForm() {
    var request = base
    request.method = "PUT"
    request.requestBody = .form([
      FormField(name: "a", value: "1"), FormField(name: "f", fileName: "x.png"),
    ])
    #expect(
      RequestExport.curl(request)
        == "curl 'https://example.com/a?b=1' \\\n  -X PUT \\\n  -F 'a=1' \\\n  -F 'f=@x.png'")
    #expect(
      RequestExport.fetch(request)
        == [
          "const body = new FormData()",
          #"body.append("a", "1")"#,
          #"// file field "f" (x.png) not captured"#,
          #"await fetch("https://example.com/a?b=1", {"#,
          #"  method: "PUT","#,
          "  body,",
          "})",
        ].joined(separator: "\n"))
  }

  @Test func binaryBodyIsNoted() {
    var request = base
    request.method = "POST"
    request.requestBody = .binary(byteLength: 4)
    #expect(
      RequestExport.curl(request)
        == "curl 'https://example.com/a?b=1' \\\n  -X POST\n# binary request body (4 bytes) not captured"
    )
  }
}

@Suite struct EntryStoreTests {
  private func makeStore() throws -> EntryStore {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("devtools-\(UUID().uuidString).sqlite")
    return try EntryStore(url: url)
  }

  private let limits = EntryStore.Limits(logsPerTab: 2, requestsPerTab: 10, retention: 3600)
  private let now = Date(timeIntervalSince1970: 10_000)
  private func log(_ id: String, at seconds: Double) -> Entry {
    .log(LogEntry(id: id, level: .log, message: id, time: seconds * 1000))
  }

  @Test func decodesJavaScriptJSON() throws {
    let json = #"""
      {"kind":"request","id":"r","initiator":"xhr","method":"POST","url":"https://x.test",
       "requestHeaders":{"a":"b"},"requestBody":{"kind":"form","fields":[{"name":"f","fileName":"y"}]},
       "status":201,"startTime":1,"endTime":2.5}
      """#
    let entry = try JSONDecoder().decode(Entry.self, from: Data(json.utf8))
    guard case .request(let request) = entry else {
      Issue.record("not a request")
      return
    }
    #expect(request.requestBody == .form([FormField(name: "f", fileName: "y")]))
    #expect(request.durationMilliseconds == 1.5)
  }

  @Test func upsertsAndPrunesPerTab() throws {
    let store = try makeStore()
    try store.store(
      tabId: 1, pageURL: "https://a.test/", entries: [log("1", at: 9_997), log("2", at: 9_998)],
      limits: limits, now: now)
    try store.store(
      tabId: 1, pageURL: "https://a.test/next", entries: [log("3", at: 9_999)], limits: limits,
      now: now)
    try store.store(
      tabId: 2, pageURL: "https://b.test/", entries: [log("4", at: 9_999)], limits: limits, now: now
    )
    #expect(try store.entries(tabId: 1).map(\.id) == ["2", "3"])
    let tabs = try store.tabs()
    #expect(tabs.map(\.tabId).sorted() == [1, 2])
    #expect(tabs.first { $0.tabId == 1 }?.pageURL == "https://a.test/next")

    var request = RequestEntry(
      id: "r", method: "GET", url: "https://a.test/x", startTime: 9_999_000)
    try store.store(
      tabId: 1, pageURL: "https://a.test/", entries: [.request(request)], limits: limits, now: now)
    request.status = 200
    try store.store(
      tabId: 1, pageURL: "https://a.test/", entries: [.request(request)], limits: limits, now: now)
    #expect(try store.entries(tabId: 1).filter { $0.kind == "request" } == [.request(request)])

    try store.keepTabs([2])
    #expect(try store.entries(tabId: 1).isEmpty)
    #expect(try store.tabs().map(\.tabId) == [2])
  }

  @Test func dropsEntriesPastRetention() throws {
    let store = try makeStore()
    try store.store(
      tabId: 1, pageURL: "https://a.test/", entries: [log("old", at: 1), log("new", at: 9_999)],
      limits: limits, now: now)
    #expect(try store.entries(tabId: 1).map(\.id) == ["new"])
  }
}

// The same cases as web/src/body.test.ts.
@Suite struct BodyFormatTests {
  @Test func jsonKeepsKeyOrderAndStringContents() {
    #expect(
      BodyFormat.view(
        body: #"{"b":1,"a":[1,{"c":"x,y"}],"e":{},"s":"q\"}"}"#,
        contentType: "application/json; charset=utf-8")
        == .json(
          [
            "{",
            #"  "b": 1,"#,
            #"  "a": ["#,
            "    1,",
            "    {",
            #"      "c": "x,y""#,
            "    }",
            "  ],",
            #"  "e": {},"#,
            #"  "s": "q\"}""#,
            "}",
          ].joined(separator: "\n")))
  }

  @Test func jsonIsSniffedWithoutContentType() {
    #expect(BodyFormat.view(body: " [1, 2]", contentType: nil) == .json("[\n  1,\n  2\n]"))
  }

  @Test func jsonIsSniffedInTextPlain() {
    #expect(
      BodyFormat.view(body: #"{"a":1}"#, contentType: "text/plain;charset=utf-8")
        == .json("{\n  \"a\": 1\n}"))
  }

  @Test func invalidJSONFallsBackToText() {
    #expect(BodyFormat.view(body: "{nope", contentType: "application/json") == .text("{nope"))
  }

  @Test func formBodiesBecomeFields() {
    #expect(
      BodyFormat.view(
        body: "a=1&b=two%20words&a=3", contentType: "application/x-www-form-urlencoded")
        == .form([.init("a", "1"), .init("b", "two words"), .init("a", "3")]))
  }

  @Test func xmlIsIndented() {
    #expect(
      BodyFormat.view(body: #"<?xml version="1.0"?><a><b>t</b><c/></a>"#, contentType: nil)
        == .xml(
          [#"<?xml version="1.0"?>"#, "<a>", "  <b>", "    t", "  </b>", "  <c/>", "</a>"]
            .joined(separator: "\n")))
  }

  @Test func htmlAndTextAreShownAsSent() {
    #expect(
      BodyFormat.view(body: "<!doctype html><p>hi</p>", contentType: nil)
        == .html("<!doctype html><p>hi</p>"))
    #expect(BodyFormat.view(body: "hello", contentType: "text/plain") == .text("hello"))
  }

  @Test func base64BodiesAreImages() {
    guard
      case .image(let dataURL, let data) = BodyFormat.view(
        body: "AAAA", contentType: "image/png", encoding: "base64")
    else {
      Issue.record("not an image")
      return
    }
    #expect(dataURL == "data:image/png;base64,AAAA")
    #expect(data == Data([0, 0, 0]))
  }
}
