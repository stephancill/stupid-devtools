import DevToolsCore
import SwiftUI

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @AppStorage(Settings.Key.maxLogsPerTab, store: Settings.defaults)
  private var maxLogs = Settings.Default.maxLogsPerTab
  @AppStorage(Settings.Key.maxRequestsPerTab, store: Settings.defaults)
  private var maxRequests = Settings.Default.maxRequestsPerTab
  @AppStorage(Settings.Key.retentionHours, store: Settings.defaults)
  private var retentionHours = Settings.Default.retentionHours
  @State private var confirmClear = false
  @State private var clearError: String?

  var body: some View {
    NavigationStack {
      Form {
        Section {
          NavigationLink("Set Up Extension") { SetupView() }
        }
        Section {
          Picker("Console logs", selection: $maxLogs) {
            ForEach([100, 250, 500, 1000, 2000], id: \.self) { Text("\($0)") }
          }
          Picker("Network requests", selection: $maxRequests) {
            ForEach([50, 100, 200, 500, 1000], id: \.self) { Text("\($0)") }
          }
        } header: {
          Text("Kept per Tab")
        } footer: {
          Text("The oldest entries are removed once a tab goes over the limit.")
        }
        Section {
          Picker("Keep for", selection: $retentionHours) {
            Text("1 hour").tag(1)
            Text("6 hours").tag(6)
            Text("24 hours").tag(24)
            Text("3 days").tag(72)
            Text("7 days").tag(168)
          }
        } header: {
          Text("Retention")
        } footer: {
          Text("Entries are also removed when their Safari tab closes.")
        }
        Section {
          Button("Clear All Data", role: .destructive) { confirmClear = true }
          if let clearError {
            Text(clearError).foregroundStyle(.red)
          }
        }
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        Button("Done") { dismiss() }
      }
      .alert("Clear All Data?", isPresented: $confirmClear) {
        Button("Cancel", role: .cancel) {}
        Button("Clear All Data", role: .destructive) { clear() }
      } message: {
        Text("This deletes the console logs and network requests stored for every tab.")
      }
    }
  }

  private func clear() {
    Task {
      if case .failure(let error) = await readStore({ try $0.deleteAll() }) {
        clearError = String(describing: error)
      } else {
        clearError = nil
      }
    }
  }
}

struct SetupView: View {
  @Environment(\.openURL) private var openURL

  var body: some View {
    List {
      Section {
        Text("1. Open Settings, then Apps › Safari › Extensions.")
        Text("2. Tap stupid devtools and turn it on.")
        Text("3. Allow it on All Websites, or on the sites you want to debug.")
        Text("4. Reload the page, then tap the extension in Safari's address bar menu.")
      } footer: {
        Text("Pages show up here once they log something or make a request.")
      }
      Section {
        Button("Open Settings") {
          if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        }
      }
    }
    .navigationTitle("Set Up Extension")
    .navigationBarTitleDisplayMode(.inline)
  }
}
