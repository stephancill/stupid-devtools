import Foundation

/// Limits shared by the app (which edits them) and the extension (which enforces them)
/// through App Group defaults. Keys match the 1.0 app so existing settings carry over.
public enum Settings {
  public static let appGroup = "group.co.za.stephancill.devtools"

  public enum Key {
    public static let maxLogsPerTab = "maxLogsPerTab"
    public static let maxRequestsPerTab = "maxNetworkRequestsPerTab"
    public static let retentionHours = "logRetentionHours"
  }

  public enum Default {
    public static let maxLogsPerTab = 500
    public static let maxRequestsPerTab = 200
    public static let retentionHours = 24
  }

  public static var defaults: UserDefaults {
    guard let defaults = UserDefaults(suiteName: appGroup) else {
      preconditionFailure("App Group \(appGroup) is not configured")
    }
    return defaults
  }

  public static var limits: EntryStore.Limits {
    let defaults = defaults
    func value(_ key: String, _ fallback: Int) -> Int {
      let stored = defaults.integer(forKey: key)
      return stored > 0 ? stored : fallback
    }
    return EntryStore.Limits(
      logsPerTab: value(Key.maxLogsPerTab, Default.maxLogsPerTab),
      requestsPerTab: value(Key.maxRequestsPerTab, Default.maxRequestsPerTab),
      retention: TimeInterval(value(Key.retentionHours, Default.retentionHours) * 3600)
    )
  }
}
