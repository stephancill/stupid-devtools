import DevToolsCore
import SwiftUI

struct TabDetailView: View {
  enum Panel: String, CaseIterable {
    case console = "Console"
    case network = "Network"
  }

  let tab: EntryStore.TabSummary
  @State private var panel = Panel.console
  @State private var entries: [Entry] = []
  @State private var loadError: String?
  @State private var search = ""

  private var logs: [LogEntry] {
    entries.compactMap { entry in
      guard case .log(let log) = entry else { return nil }
      return search.isEmpty || log.message.localizedCaseInsensitiveContains(search) ? log : nil
    }
  }

  private var requests: [RequestEntry] {
    entries.compactMap { entry in
      guard case .request(let request) = entry else { return nil }
      return search.isEmpty || request.url.localizedCaseInsensitiveContains(search) ? request : nil
    }
  }

  var body: some View {
    List {
      if let loadError {
        Text(loadError).foregroundStyle(.red)
      }
      switch panel {
      case .console:
        ForEach(logs.reversed()) { LogRow(log: $0) }
      case .network:
        ForEach(requests.reversed()) { request in
          NavigationLink(value: request) { RequestRow(request: request) }
            .contextMenu { RequestCopyMenu(request: request) }
        }
      }
    }
    .listStyle(.plain)
    .overlay {
      if loadError == nil && (panel == .console ? logs.isEmpty : requests.isEmpty) {
        ContentUnavailableView(
          search.isEmpty ? "Nothing Yet" : "No Results",
          systemImage: panel == .console ? "terminal" : "network")
      }
    }
    .safeAreaInset(edge: .top) {
      Picker("Panel", selection: $panel) {
        ForEach(Panel.allCases, id: \.self) { Text($0.rawValue) }
      }
      .pickerStyle(.segmented)
      .padding(.horizontal)
      .padding(.bottom, 8)
      .background(.bar)
    }
    .searchable(text: $search, prompt: panel == .console ? "Filter messages" : "Filter URLs")
    .navigationTitle(host(of: tab.pageURL))
    .navigationBarTitleDisplayMode(.inline)
    .navigationDestination(for: RequestEntry.self) { RequestDetailView(request: $0) }
    .refreshable { await reload() }
    .polling { await reload() }
  }

  @MainActor
  private func reload() async {
    let tabId = tab.tabId
    switch await readStore({ try $0.entries(tabId: tabId) }) {
    case .success(let entries):
      self.entries = entries
      loadError = nil
    case .failure(let error):
      loadError = String(describing: error)
    }
  }
}

struct LogRow: View {
  let log: LogEntry

  private var color: Color {
    switch log.level {
    case .error: .red
    case .warn: .orange
    case .info: .blue
    case .debug, .result: .secondary
    case .log, .command: .primary
    }
  }

  private var prefix: String {
    switch log.level {
    case .command: "› "
    case .result: "‹ "
    default: ""
    }
  }

  var body: some View {
    Text(prefix + log.message)
      .foregroundStyle(color)
      .lineLimit(20)
      .contextMenu {
        Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = log.message }
      }
  }
}

struct RequestRow: View {
  let request: RequestEntry

  private var path: String {
    guard let components = URLComponents(string: request.url) else { return request.url }
    return components.path + (components.query.map { "?\($0)" } ?? "")
  }

  private var status: String {
    if request.error != nil { return "failed" }
    return request.status.map(String.init) ?? "pending"
  }

  var body: some View {
    HStack {
      Text("\(request.method) \(path)")
        .lineLimit(1)
        .truncationMode(.middle)
      Spacer()
      Text(status)
        .foregroundStyle(.secondary)
    }
    .foregroundStyle(request.failed ? .red : .primary)
  }
}

/// Long-press actions for a request, used by list rows and the detail screen.
struct RequestCopyMenu: View {
  let request: RequestEntry

  var body: some View {
    Button("Copy as cURL", systemImage: "terminal") {
      UIPasteboard.general.string = RequestExport.curl(request)
    }
    Button("Copy as fetch", systemImage: "curlybraces") {
      UIPasteboard.general.string = RequestExport.fetch(request)
    }
    Button("Copy URL", systemImage: "link") { UIPasteboard.general.string = request.url }
    if request.responseBody != nil {
      Button("Copy Response", systemImage: "arrow.down.doc") {
        UIPasteboard.general.string = BodyFormat.responseCopyText(request)
      }
    }
  }
}
