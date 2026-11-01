import Foundation
import SQLite3

/// SQLite store in the App Group container. The extension writes, the app reads;
/// WAL mode and a busy timeout let both processes (and concurrent extension
/// requests) use it at once. Each entry is upserted by id as JSON.
public final class EntryStore {
  public struct Limits: Sendable {
    public var logsPerTab: Int
    public var requestsPerTab: Int
    public var retention: TimeInterval

    public init(logsPerTab: Int, requestsPerTab: Int, retention: TimeInterval) {
      self.logsPerTab = logsPerTab
      self.requestsPerTab = requestsPerTab
      self.retention = retention
    }
  }

  public struct TabSummary: Sendable, Identifiable, Hashable {
    public var id: Int { tabId }
    public var tabId: Int
    public var pageURL: String
    public var lastActivity: Double
  }

  public struct StoreError: Error, CustomStringConvertible {
    public var description: String

    public init(description: String) {
      self.description = description
    }
  }

  private let db: OpaquePointer

  public init(url: URL) throws {
    var handle: OpaquePointer?
    let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
    guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK, let handle else {
      let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
      sqlite3_close(handle)
      throw StoreError(description: "Cannot open \(url.lastPathComponent): \(message)")
    }
    db = handle
    sqlite3_busy_timeout(db, 3000)
    try exec(
      """
      PRAGMA journal_mode = WAL;
      CREATE TABLE IF NOT EXISTS entries (
        id TEXT PRIMARY KEY,
        tab_id INTEGER NOT NULL,
        page_url TEXT NOT NULL,
        kind TEXT NOT NULL,
        time REAL NOT NULL,
        json TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS entries_by_tab ON entries (tab_id, kind, time);
      """)
  }

  deinit {
    sqlite3_close(db)
  }

  /// The store shared by the app and the extension.
  public static func shared() throws -> EntryStore {
    guard
      let container = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: Settings.appGroup)
    else {
      throw StoreError(description: "App Group \(Settings.appGroup) is not available")
    }
    return try EntryStore(url: container.appendingPathComponent("devtools.sqlite"))
  }

  // MARK: Writes

  public func store(
    tabId: Int, pageURL: String, entries: [Entry], limits: Limits, now: Date = Date()
  ) throws {
    let encoder = JSONEncoder()
    try transaction {
      let upsert = try prepare(
        """
        INSERT INTO entries (id, tab_id, page_url, kind, time, json) VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT (id) DO UPDATE SET json = excluded.json, page_url = excluded.page_url
        """)
      for entry in entries {
        let json = String(decoding: try encoder.encode(entry), as: UTF8.self)
        try upsert.run(entry.id, tabId, pageURL, entry.kind, entry.time, json)
      }

      let prune = try prepare(
        """
        DELETE FROM entries WHERE tab_id = ?1 AND kind = ?2 AND id NOT IN (
          SELECT id FROM entries WHERE tab_id = ?1 AND kind = ?2 ORDER BY time DESC LIMIT ?3
        )
        """)
      try prune.run(tabId, "log", limits.logsPerTab)
      try prune.run(tabId, "request", limits.requestsPerTab)

      let cutoff = (now.timeIntervalSince1970 - limits.retention) * 1000
      try prepare("DELETE FROM entries WHERE time < ?").run(cutoff)
    }
  }

  public func deleteTab(_ tabId: Int) throws {
    try prepare("DELETE FROM entries WHERE tab_id = ?").run(tabId)
  }

  /// Deletes entries for every tab not in `tabIds`.
  public func keepTabs(_ tabIds: [Int]) throws {
    let list = tabIds.map(String.init).joined(separator: ",")
    try exec("DELETE FROM entries WHERE tab_id NOT IN (\(list))")
  }

  public func deleteAll() throws {
    try exec("DELETE FROM entries")
  }

  // MARK: Reads

  public func tabs() throws -> [TabSummary] {
    // SQLite returns page_url from the row holding MAX(time).
    let query = try prepare(
      """
      SELECT tab_id, page_url, MAX(time)
      FROM entries GROUP BY tab_id ORDER BY MAX(time) DESC
      """)
    var tabs: [TabSummary] = []
    while try query.step() {
      tabs.append(
        TabSummary(
          tabId: query.int(0), pageURL: query.text(1), lastActivity: query.double(2)))
    }
    return tabs
  }

  public func entries(tabId: Int) throws -> [Entry] {
    let query = try prepare("SELECT json FROM entries WHERE tab_id = ? ORDER BY time")
    try query.bind(tabId)
    let decoder = JSONDecoder()
    var entries: [Entry] = []
    while try query.step() {
      entries.append(try decoder.decode(Entry.self, from: Data(query.text(0).utf8)))
    }
    return entries
  }

  // MARK: SQLite helpers

  private func error(_ context: String) -> StoreError {
    StoreError(description: "\(context): \(String(cString: sqlite3_errmsg(db)))")
  }

  private func exec(_ sql: String) throws {
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw error("SQL failed") }
  }

  private func transaction(_ body: () throws -> Void) throws {
    try exec("BEGIN IMMEDIATE")
    do {
      try body()
      try exec("COMMIT")
    } catch {
      try? exec("ROLLBACK")
      throw error
    }
  }

  private func prepare(_ sql: String) throws -> Statement {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
      throw error("Prepare failed")
    }
    return Statement(db: db, handle: statement)
  }

  private final class Statement {
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    let db: OpaquePointer
    let handle: OpaquePointer

    init(db: OpaquePointer, handle: OpaquePointer) {
      self.db = db
      self.handle = handle
    }

    deinit {
      sqlite3_finalize(handle)
    }

    private func check(_ code: Int32) throws {
      guard code == SQLITE_OK else {
        throw StoreError(description: "Bind failed: \(String(cString: sqlite3_errmsg(db)))")
      }
    }

    func bind(_ values: Any...) throws {
      try bindAll(values)
    }

    private func bindAll(_ values: [Any]) throws {
      sqlite3_reset(handle)
      sqlite3_clear_bindings(handle)
      for (offset, value) in values.enumerated() {
        let index = Int32(offset + 1)
        switch value {
        case let value as Int: try check(sqlite3_bind_int64(handle, index, Int64(value)))
        case let value as Double: try check(sqlite3_bind_double(handle, index, value))
        case let value as String:
          try check(sqlite3_bind_text(handle, index, value, -1, Self.transient))
        default: preconditionFailure("Unsupported SQLite value \(type(of: value))")
        }
      }
    }

    /// Binds and steps a statement that returns no rows.
    func run(_ values: Any...) throws {
      try bindAll(values)
      guard sqlite3_step(handle) == SQLITE_DONE else {
        throw StoreError(description: "Step failed: \(String(cString: sqlite3_errmsg(db)))")
      }
    }

    func step() throws -> Bool {
      switch sqlite3_step(handle) {
      case SQLITE_ROW: return true
      case SQLITE_DONE: return false
      default: throw StoreError(description: "Step failed: \(String(cString: sqlite3_errmsg(db)))")
      }
    }

    func int(_ column: Int32) -> Int { Int(sqlite3_column_int64(handle, column)) }
    func double(_ column: Int32) -> Double { sqlite3_column_double(handle, column) }
    func text(_ column: Int32) -> String {
      sqlite3_column_text(handle, column).map { String(cString: $0) } ?? ""
    }
  }
}
