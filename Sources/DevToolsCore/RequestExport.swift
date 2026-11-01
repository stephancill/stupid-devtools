import Foundation

/// Rebuilds a captured request as a cURL command or a fetch() call. Mirrors
/// web/src/export.ts; keep the output of the two identical.
public enum RequestExport {
  /// Headers the browser sets itself; copying them would only add noise.
  private static let skippedHeaders: Set<String> = ["content-length", "host"]

  private static func headers(_ request: RequestEntry) -> [(String, String)] {
    request.requestHeaders
      .filter { !skippedHeaders.contains($0.key.lowercased()) }
      .sorted { $0.key < $1.key }
      .map { ($0.key, $0.value) }
  }

  private static func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
  }

  private static func jsString(_ value: String) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .withoutEscapingSlashes
    // Encoding a String cannot fail.
    return String(decoding: try! encoder.encode(value), as: UTF8.self)
  }

  private static func byteLabel(_ byteLength: Int?) -> String {
    byteLength.map { "\($0) bytes" } ?? "unknown size"
  }

  public static func curl(_ request: RequestEntry) -> String {
    var parts = ["curl \(shellQuote(request.url))"]
    let body = request.requestBody
    let impliedMethod: String
    switch body {
    case .text, .form: impliedMethod = "POST"
    case .binary, nil: impliedMethod = "GET"
    }
    if request.method != impliedMethod { parts.append("-X \(request.method)") }
    for (name, value) in headers(request) { parts.append("-H \(shellQuote("\(name): \(value)"))") }
    let hasCookieHeader = request.requestHeaders.keys.contains { $0.lowercased() == "cookie" }
    if let cookies = request.cookies, !hasCookieHeader { parts.append("-b \(shellQuote(cookies))") }
    var notes: [String] = []
    switch body {
    case .text(let text): parts.append("--data-raw \(shellQuote(text))")
    case .form(let fields):
      for field in fields {
        if let value = field.value {
          parts.append("-F \(shellQuote("\(field.name)=\(value)"))")
        } else {
          parts.append("-F \(shellQuote("\(field.name)=@\(field.fileName ?? "file")"))")
        }
      }
    case .binary(let byteLength):
      notes.append("# binary request body (\(byteLabel(byteLength))) not captured")
    case nil: break
    }
    return ([parts.joined(separator: " \\\n  ")] + notes).joined(separator: "\n")
  }

  public static func fetch(_ request: RequestEntry) -> String {
    var lines: [String] = []
    var options: [String] = []
    if request.method != "GET" { options.append("method: \(jsString(request.method))") }
    let headers = headers(request)
    if !headers.isEmpty {
      let fields = headers.map { "    \(jsString($0.0)): \(jsString($0.1))," }
      options.append("headers: {\n\(fields.joined(separator: "\n"))\n  }")
    }
    switch request.requestBody {
    case .text(let text): options.append("body: \(jsString(text))")
    case .form(let fields):
      lines.append("const body = new FormData()")
      for field in fields {
        if let value = field.value {
          lines.append("body.append(\(jsString(field.name)), \(jsString(value)))")
        } else {
          lines.append(
            "// file field \(jsString(field.name)) (\(field.fileName ?? "file")) not captured")
        }
      }
      options.append("body")
    case .binary(let byteLength):
      lines.append("// binary request body (\(byteLabel(byteLength))) not captured")
    case nil: break
    }
    if request.cookies != nil { options.append(#"credentials: "include""#) }
    let initializer =
      options.isEmpty
      ? "" : ", {\n" + options.map { "  \($0)," }.joined(separator: "\n") + "\n}"
    lines.append("await fetch(\(jsString(request.url))\(initializer))")
    return lines.joined(separator: "\n")
  }
}
