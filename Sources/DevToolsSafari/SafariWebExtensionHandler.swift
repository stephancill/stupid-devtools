import DevToolsCore
import Foundation
import SafariServices
import os

/// Receives native messages from background.js and writes them to the shared store.
public final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
  private static let logger = Logger(subsystem: "co.za.stephancill.devtools", category: "extension")

  /// Mirrors `NativeMessage` in web/src/background.ts.
  private enum Message: Decodable {
    case store(tabId: Int, pageURL: String, entries: [Entry])
    case tabClosed(tabId: Int)
    case syncTabs(tabIds: [Int])

    private enum CodingKeys: String, CodingKey { case type, tabId, pageUrl, entries, tabIds }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      switch try container.decode(String.self, forKey: .type) {
      case "store":
        self = .store(
          tabId: try container.decode(Int.self, forKey: .tabId),
          pageURL: try container.decode(String.self, forKey: .pageUrl),
          entries: try container.decode([Entry].self, forKey: .entries))
      case "tabClosed":
        self = .tabClosed(tabId: try container.decode(Int.self, forKey: .tabId))
      case "syncTabs":
        self = .syncTabs(tabIds: try container.decode([Int].self, forKey: .tabIds))
      case let type:
        throw DecodingError.dataCorruptedError(
          forKey: .type, in: container, debugDescription: "Unknown message type \(type)")
      }
    }
  }

  public func beginRequest(with context: NSExtensionContext) {
    let item = context.inputItems.first as? NSExtensionItem
    let response: [String: Any]
    do {
      guard let payload = item?.userInfo?[SFExtensionMessageKey] else {
        throw EntryStore.StoreError(description: "Missing message")
      }
      let data = try JSONSerialization.data(withJSONObject: payload)
      try handle(try JSONDecoder().decode(Message.self, from: data))
      response = ["ok": true]
    } catch {
      Self.logger.error("Native message failed: \(String(describing: error), privacy: .public)")
      response = ["error": String(describing: error)]
    }
    let reply = NSExtensionItem()
    reply.userInfo = [SFExtensionMessageKey: response]
    context.completeRequest(returningItems: [reply], completionHandler: nil)
  }

  private func handle(_ message: Message) throws {
    let store = try EntryStore.shared()
    switch message {
    case .store(let tabId, let pageURL, let entries):
      try store.store(tabId: tabId, pageURL: pageURL, entries: entries, limits: Settings.limits)
    case .tabClosed(let tabId):
      try store.deleteTab(tabId)
    case .syncTabs(let tabIds):
      try store.keepTabs(tabIds)
    }
  }
}
