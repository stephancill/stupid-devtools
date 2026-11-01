import DevToolsCore
import SwiftUI

@main
struct DevToolsApp: App {
  init() {
    removeLegacyStore()
  }

  var body: some Scene {
    WindowGroup {
      TabsView()
    }
  }
}

/// 1.0 kept logs in a SwiftData store; 1.1 uses devtools.sqlite. The old logs are
/// short-lived debug data, so they are deleted rather than migrated.
private func removeLegacyStore() {
  guard
    let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: Settings.appGroup)
  else { return }
  for name in ["logs.store", "logs.store-shm", "logs.store-wal"] {
    try? FileManager.default.removeItem(at: container.appendingPathComponent(name))
  }
}
