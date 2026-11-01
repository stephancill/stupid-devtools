import Foundation

/// Decides how to display a request or response body from its content type, sniffing
/// the text when the type is missing. Mirrors web/src/body.ts; keep the two identical.
public enum BodyView: Equatable, Sendable {
  case json(String)
  case form([FormPair])
  case xml(String)
  case html(String)
  case text(String)
  case image(dataURL: String, data: Data)

  public struct FormPair: Equatable, Sendable, Hashable {
    public var name: String
    public var value: String

    public init(_ name: String, _ value: String) {
      self.name = name
      self.value = value
    }
  }

  /// Formatted views that differ from the raw text get a Raw/Formatted switch.
  public var hasRawView: Bool {
    switch self {
    case .json, .xml, .form: true
    case .html, .text, .image: false
    }
  }

  public var label: String {
    switch self {
    case .json: "JSON"
    case .form: "Form"
    case .xml: "XML"
    case .html: "HTML"
    case .text: "Text"
    case .image: "Image"
    }
  }
}

public enum BodyFormat {
  public static func headerValue(_ headers: [String: String]?, _ name: String) -> String? {
    headers?.first { $0.key.lowercased() == name }?.value
  }

  public static func view(body: String, contentType: String?, encoding: String? = nil) -> BodyView {
    let type = (contentType ?? "").lowercased()
    if encoding == "base64" {
      let mime = type.split(separator: ";").first.map(String.init) ?? ""
      return .image(
        dataURL: "data:\(mime.isEmpty ? "image/*" : mime);base64,\(body)",
        data: Data(base64Encoded: body) ?? Data())
    }
    let trimmed = body.drop { $0.isWhitespace }
    // Many APIs send JSON as text/plain, so sniff it there too.
    let sniff = type.isEmpty || type.hasPrefix("text/plain")
    if type.contains("json") || (sniff && (trimmed.first == "{" || trimmed.first == "[")) {
      if isJSON(body) { return .json(indentJSON(body)) }
    }
    if type.contains("x-www-form-urlencoded") {
      return .form(formPairs(body))
    }
    if type.contains("xml") || (type.isEmpty && trimmed.hasPrefix("<?xml")) {
      return .xml(indentXML(body))
    }
    let lowered = trimmed.lowercased()
    if type.contains("html")
      || (type.isEmpty && (lowered.hasPrefix("<!doctype html") || lowered.hasPrefix("<html")))
    {
      return .html(body)
    }
    return .text(body)
  }

  public static func responseView(_ request: RequestEntry) -> BodyView? {
    request.responseBody.map {
      view(
        body: $0, contentType: headerValue(request.responseHeaders, "content-type"),
        encoding: request.responseBodyEncoding)
    }
  }

  /// What "Copy Response" copies: the text as captured, or a data URL for an image.
  public static func responseCopyText(_ request: RequestEntry) -> String {
    if case .image(let dataURL, _) = responseView(request) { return dataURL }
    return request.responseBody ?? ""
  }

  private static func isJSON(_ text: String) -> Bool {
    (try? JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed)) != nil
  }

  /// Matches URLSearchParams: `+` is a space, names without `=` get an empty value.
  private static func formPairs(_ body: String) -> [BodyView.FormPair] {
    body.split(separator: "&").map { part in
      let pieces = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      func decode(_ value: Substring?) -> String {
        let raw = String(value ?? "").replacingOccurrences(of: "+", with: " ")
        return raw.removingPercentEncoding ?? raw
      }
      return BodyView.FormPair(decode(pieces.first), decode(pieces.count > 1 ? pieces[1] : nil))
    }
  }

  /// Re-indents valid JSON without parsing it, so key order and number formatting stay
  /// exactly as sent.
  public static func indentJSON(_ json: String) -> String {
    let chars = Array(json)
    var out = ""
    var depth = 0
    var inString = false
    var i = 0
    func newline() -> String { "\n" + String(repeating: "  ", count: depth) }
    while i < chars.count {
      let char = chars[i]
      defer { i += 1 }
      if inString {
        out.append(char)
        if char == "\\", i + 1 < chars.count {
          i += 1
          out.append(chars[i])
        } else if char == "\"" {
          inString = false
        }
        continue
      }
      if char.isWhitespace { continue }
      switch char {
      case "\"":
        inString = true
        out.append(char)
      case "{", "[":
        let close: Character = char == "{" ? "}" : "]"
        let next = chars[(i + 1)...].first { !$0.isWhitespace }
        if next == close {
          out += "\(char)\(close)"
          i = chars[(i + 1)...].firstIndex(of: close) ?? i
        } else {
          depth += 1
          out += "\(char)" + newline()
        }
      case "}", "]":
        depth -= 1
        out += newline() + "\(char)"
      case ",":
        out += "," + newline()
      case ":":
        out += ": "
      default:
        out.append(char)
      }
    }
    return out
  }

  /// Puts each tag on its own line, indented by nesting. Text between tags keeps its
  /// own line; whitespace-only text is dropped.
  public static func indentXML(_ xml: String) -> String {
    var tokens: [String] = []
    var current = ""
    for char in xml {
      if char == "<" {
        tokens.append(current)
        current = "<"
      } else if char == ">" && current.hasPrefix("<") {
        tokens.append(current + ">")
        current = ""
      } else {
        current.append(char)
      }
    }
    tokens.append(current)

    var lines: [String] = []
    var depth = 0
    for token in tokens {
      let text = token.trimmingCharacters(in: .whitespacesAndNewlines)
      if text.isEmpty { continue }
      if text.hasPrefix("</") { depth = max(0, depth - 1) }
      lines.append(String(repeating: "  ", count: depth) + text)
      let opens =
        text.hasPrefix("<") && !text.hasPrefix("</") && !text.hasPrefix("<?")
        && !text.hasPrefix("<!") && !text.hasSuffix("/>")
      if opens { depth += 1 }
    }
    return lines.joined(separator: "\n")
  }
}
