import DevToolsCore
import SwiftUI

struct TabsView: View {
  @State private var tabs: [EntryStore.TabSummary] = []
  @State private var loadError: String?
  @State private var showSettings = false
  @State private var showSetup = false

  var body: some View {
    NavigationStack {
      List {
        if let loadError {
          Text(loadError).foregroundStyle(.red)
        }
        ForEach(tabs) { tab in
          NavigationLink(value: tab) {
            Text(host(of: tab.pageURL))
          }
        }
      }
      .overlay {
        if tabs.isEmpty && loadError == nil {
          ContentUnavailableView {
            Label("No Tabs", systemImage: "safari")
          } description: {
            Text(
              "Open a page in Safari with the extension enabled to see its console and network activity here."
            )
          } actions: {
            Button("Set Up Extension") { showSetup = true }
          }
        }
      }
      .navigationTitle("Tabs")
      .navigationDestination(for: EntryStore.TabSummary.self) { tab in
        TabDetailView(tab: tab)
      }
      .toolbar {
        Button("Settings", systemImage: "gear") { showSettings = true }
      }
      .refreshable { await reload() }
      .polling { await reload() }
      .sheet(isPresented: $showSettings) { SettingsView() }
      .sheet(isPresented: $showSetup) { NavigationStack { SetupView() } }
    }
  }

  @MainActor
  private func reload() async {
    switch await readStore({ try $0.tabs() }) {
    case .success(let tabs):
      self.tabs = tabs
      loadError = nil
    case .failure(let error):
      loadError = String(describing: error)
    }
  }
}
