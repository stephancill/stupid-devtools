import Foundation

// Mirrors web/src/entries.ts. Times are JavaScript milliseconds since 1970.

public enum LogLevel: String, Codable, Sendable {
  case log, info, warn, error, debug, command, result
}

public struct LogEntry: Codable, Sendable, Identifiable, Hashable {
  public var id: String
  public var level: LogLevel
  public var message: String
  public var time: Double

  public init(id: String, level: LogLevel, message: String, time: Double) {
    self.id = id
    self.level = level
    self.message = message
    self.time = time
  }
}

public struct FormField: Codable, Sendable, Hashable {
  public var name: String
  public var value: String?
  public var fileName: String?

  public init(name: String, value: String? = nil, fileName: String? = nil) {
    self.name = name
    self.value = value
    self.fileName = fileName
  }
}

public enum RequestBody: Codable, Sendable, Hashable {
  case text(String)
  case form([FormField])
  case binary(byteLength: Int?)

  private enum CodingKeys: String, CodingKey { case kind, text, fields, byteLength }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(String.self, forKey: .kind) {
    case "text": self = .text(try container.decode(String.self, forKey: .text))
    case "form": self = .form(try container.decode([FormField].self, forKey: .fields))
    case "binary":
      self = .binary(byteLength: try container.decodeIfPresent(Int.self, forKey: .byteLength))
    case let kind:
      throw DecodingError.dataCorruptedError(
        forKey: .kind, in: container, debugDescription: "Unknown body kind \(kind)")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .text(let text):
      try container.encode("text", forKey: .kind)
      try container.encode(text, forKey: .text)
    case .form(let fields):
      try container.encode("form", forKey: .kind)
      try container.encode(fields, forKey: .fields)
    case .binary(let byteLength):
      try container.encode("binary", forKey: .kind)
      try container.encodeIfPresent(byteLength, forKey: .byteLength)
    }
  }
}

public struct RequestEntry: Codable, Sendable, Identifiable, Hashable {
  public var id: String
  public var initiator: String
  public var method: String
  public var url: String
  public var requestHeaders: [String: String]
  public var requestBody: RequestBody?
  /// `document.cookie` at send time, same-origin requests only. Excludes HttpOnly cookies.
  public var cookies: String?
  public var status: Int?
  public var statusText: String?
  public var responseHeaders: [String: String]?
  public var responseBody: String?
  public var responseBodyTruncated: Bool?
  /// "base64" when `responseBody` holds image bytes rather than text.
  public var responseBodyEncoding: String?
  public var error: String?
  public var startTime: Double
  public var endTime: Double?

  public init(
    id: String, initiator: String = "fetch", method: String, url: String,
    requestHeaders: [String: String] = [:], requestBody: RequestBody? = nil, cookies: String? = nil,
    status: Int? = nil, statusText: String? = nil, responseHeaders: [String: String]? = nil,
    responseBody: String? = nil, responseBodyTruncated: Bool? = nil,
    responseBodyEncoding: String? = nil, error: String? = nil,
    startTime: Double, endTime: Double? = nil
  ) {
    self.id = id
    self.initiator = initiator
    self.method = method
    self.url = url
    self.requestHeaders = requestHeaders
    self.requestBody = requestBody
    self.cookies = cookies
    self.status = status
    self.statusText = statusText
    self.responseHeaders = responseHeaders
    self.responseBody = responseBody
    self.responseBodyTruncated = responseBodyTruncated
    self.responseBodyEncoding = responseBodyEncoding
    self.error = error
    self.startTime = startTime
    self.endTime = endTime
  }

  public var durationMilliseconds: Double? { endTime.map { $0 - startTime } }
  public var failed: Bool { error != nil || (status ?? 0) >= 400 }
}

public enum Entry: Codable, Sendable, Identifiable, Hashable {
  case log(LogEntry)
  case request(RequestEntry)

  private enum CodingKeys: String, CodingKey { case kind }

  public var id: String {
    switch self {
    case .log(let log): log.id
    case .request(let request): request.id
    }
  }

  public var kind: String {
    switch self {
    case .log: "log"
    case .request: "request"
    }
  }

  public var time: Double {
    switch self {
    case .log(let log): log.time
    case .request(let request): request.startTime
    }
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(String.self, forKey: .kind) {
    case "log": self = .log(try LogEntry(from: decoder))
    case "request": self = .request(try RequestEntry(from: decoder))
    case let kind:
      throw DecodingError.dataCorruptedError(
        forKey: .kind, in: container, debugDescription: "Unknown entry kind \(kind)")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(kind, forKey: .kind)
    switch self {
    case .log(let log): try log.encode(to: encoder)
    case .request(let request): try request.encode(to: encoder)
    }
  }
}
