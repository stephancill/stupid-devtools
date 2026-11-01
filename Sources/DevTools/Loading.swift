import DevToolsCore
import SwiftUI

/// Reads from the shared store off the main thread.
func readStore<T: Sendable>(_ read: @escaping @Sendable (EntryStore) throws -> T) async -> Result<
  T, Error
> {
  await Task.detached { Result { try read(try EntryStore.shared()) } }.value
}

extension View {
  /// Runs `reload` now and every two seconds while the view is visible, so entries
  /// the extension writes show up without a manual refresh.
  func polling(_ reload: @escaping @Sendable () async -> Void) -> some View {
    task {
      while !Task.isCancelled {
        await reload()
        try? await Task.sleep(for: .seconds(2))
      }
    }
  }
}

func host(of url: String) -> String {
  URL(string: url)?.host() ?? url
}

func formatDuration(_ request: RequestEntry) -> String {
  guard let ms = request.durationMilliseconds else { return "pending" }
  return ms < 1000 ? "\(Int(ms)) ms" : String(format: "%.2f s", ms / 1000)
}
