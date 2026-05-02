//
//  TabDetailView.swift
//  devtools
//

import SwiftUI
import SwiftData

// MARK: - Custom Search Bar (workaround for .searchable() crash in NavigationStack > TabView)

struct SearchBar: View {
    @Binding var text: String
    let prompt: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
            
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

struct TabDetailView: View {
    let tabId: Int
    let tabURL: String
    
    var displayURL: String {
        if let url = URL(string: tabURL) {
            return url.host ?? tabURL
        }
        return tabURL
    }
    
    var body: some View {
        TabView {
            ConsoleView(tabId: tabId)
                .tabItem {
                    Label("Console", systemImage: "terminal")
                }
            
            NetworkListView(tabId: tabId)
                .tabItem {
                    Label("Network", systemImage: "network")
                }
        }
        .navigationTitle(displayURL)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Console View

struct ConsoleView: View {
    let tabId: Int
    
    @Query var logs: [DebugLog]
    @State private var searchText = ""
    
    init(tabId: Int) {
        self.tabId = tabId
        let predicate = #Predicate<DebugLog> { $0.tabId == tabId }
        _logs = Query(filter: predicate, sort: \DebugLog.timestamp, order: .forward)
    }
    
    var filteredLogs: [DebugLog] {
        if searchText.isEmpty {
            return logs
        }
        return logs.filter { $0.args.joined().localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if !logs.isEmpty {
                SearchBar(text: $searchText, prompt: "Filter logs")
            }
            
            if logs.isEmpty {
                ContentUnavailableView(
                    "No Console Logs",
                    systemImage: "terminal",
                    description: Text("Console output will appear here.")
                )
            } else if filteredLogs.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ScrollViewReader { proxy in
                    List(filteredLogs) { log in
                        LogRow(log: log)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(log.rowBackgroundColor)
                            .id(log.id)
                    }
                    .listStyle(.plain)
                    .onChange(of: filteredLogs.count) {
                        if let lastLog = filteredLogs.last {
                            withAnimation {
                                proxy.scrollTo(lastLog.id, anchor: .bottom)
                            }
                        }
                    }
                    .onAppear {
                        if let lastLog = filteredLogs.last {
                            proxy.scrollTo(lastLog.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
}

struct LogRow: View {
    let log: DebugLog
    
    private var textColor: Color {
        switch log.type {
        case "error":
            return .red
        case "warn":
            return .orange
        case "info":
            return .blue
        default:
            return .primary
        }
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(log.timestamp, format: .dateTime.hour().minute().second())
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            
            Text(log.args.joined(separator: " "))
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(textColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
    }
}

extension DebugLog {
    var rowBackgroundColor: Color {
        switch type {
        case "error":
            return .red.opacity(0.1)
        case "warn":
            return .orange.opacity(0.1)
        default:
            return .clear
        }
    }
}

// MARK: - Network View

struct NetworkListView: View {
    let tabId: Int
    
    @Query var requests: [NetworkLog]
    @State private var searchText = ""
    @State private var selectedRequest: NetworkLog?
    
    init(tabId: Int) {
        self.tabId = tabId
        let predicate = #Predicate<NetworkLog> { $0.tabId == tabId }
        _requests = Query(filter: predicate, sort: \NetworkLog.startTime, order: .forward)
    }
    
    var filteredRequests: [NetworkLog] {
        if searchText.isEmpty {
            return requests
        }
        return requests.filter { $0.url.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if !requests.isEmpty {
                SearchBar(text: $searchText, prompt: "Filter by URL")
            }
            
            if requests.isEmpty {
                ContentUnavailableView(
                    "No Network Requests",
                    systemImage: "network",
                    description: Text("Network requests will appear here.")
                )
            } else if filteredRequests.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ScrollViewReader { proxy in
                    List(filteredRequests) { request in
                        Button {
                            selectedRequest = request
                        } label: {
                            NetworkRow(request: request)
                        }
                        .buttonStyle(.plain)
                        .id(request.id)
                    }
                    .listStyle(.plain)
                    .onChange(of: filteredRequests.count) {
                        if let lastRequest = filteredRequests.last {
                            withAnimation {
                                proxy.scrollTo(lastRequest.id, anchor: .bottom)
                            }
                        }
                    }
                    .onAppear {
                        if let lastRequest = filteredRequests.last {
                            proxy.scrollTo(lastRequest.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .sheet(item: $selectedRequest) { request in
            NetworkDetailView(request: request)
        }
    }
}

struct NetworkRow: View {
    let request: NetworkLog
    
    private var statusColor: Color {
        guard let status = request.status else {
            return request.error != nil ? .red : .secondary
        }
        switch status {
        case 200..<300:
            return .green
        case 300..<400:
            return .blue
        case 400..<500:
            return .orange
        case 500...:
            return .red
        default:
            return .secondary
        }
    }
    
    private var duration: String? {
        guard let endTime = request.endTime else { return nil }
        let ms = endTime.timeIntervalSince(request.startTime) * 1000
        return String(format: "%.0fms", ms)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(request.method)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                
                if let status = request.status {
                    Text("\(status)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(statusColor)
                } else if request.error != nil {
                    Text("Error")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.red)
                } else {
                    Text("Pending")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if let duration = duration {
                    Text(duration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            
            Text(request.url)
                .font(.footnote)
                .lineLimit(2)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 4)
    }
}

struct NetworkDetailView: View {
    let request: NetworkLog
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section("Request") {
                    LabeledContent("Method", value: request.method)
                    LabeledContent("URL", value: request.url)
                    
                    if let headers = request.requestHeaders, !headers.isEmpty {
                        DisclosureGroup("Headers") {
                            ForEach(Array(headers.keys.sorted()), id: \.self) { key in
                                LabeledContent(key, value: headers[key] ?? "")
                            }
                        }
                    }
                    
                    if let body = request.requestBody {
                        DisclosureGroup("Body") {
                            Text(body)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                    
                    if let cookies = request.requestCookies, !cookies.isEmpty {
                        DisclosureGroup("Cookies") {
                            ForEach(Array(cookies.keys.sorted()), id: \.self) { key in
                                LabeledContent(key, value: cookies[key] ?? "")
                            }
                        }
                    }
                }
                
                Section("Response") {
                    if let status = request.status {
                        LabeledContent("Status", value: "\(status) \(request.statusText ?? "")")
                    }
                    
                    if let error = request.error {
                        LabeledContent("Error", value: error)
                            .foregroundStyle(.red)
                    }
                    
                    if let headers = request.responseHeaders, !headers.isEmpty {
                        DisclosureGroup("Headers") {
                            ForEach(Array(headers.keys.sorted()), id: \.self) { key in
                                LabeledContent(key, value: headers[key] ?? "")
                            }
                        }
                    }
                    
                    if let body = request.responseBody {
                        DisclosureGroup("Body") {
                            Text(body)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                    
                    if let cookies = request.responseCookies, !cookies.isEmpty {
                        DisclosureGroup("Cookies") {
                            ForEach(Array(cookies.keys.sorted()), id: \.self) { key in
                                LabeledContent(key, value: cookies[key] ?? "")
                            }
                        }
                    }
                }
                
                if let endTime = request.endTime {
                    Section("Timing") {
                        let duration = endTime.timeIntervalSince(request.startTime) * 1000
                        LabeledContent("Duration", value: String(format: "%.0f ms", duration))
                    }
                }
            }
            .navigationTitle("Request Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    TabDetailView(tabId: 1, tabURL: "https://example.com")
}

