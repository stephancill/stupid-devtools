import DevToolsCore
import SwiftUI

struct RequestDetailView: View {
  let request: RequestEntry
  @State private var showRaw = false

  /// Long bodies render slowly in a list row; the full body is still copied.
  private static let displayLimit = 5_000

  var body: some View {
    List {
      Section {
        ValueRow(label: "URL", value: request.url)
        ValueRow(label: "Status", value: statusText)
        ValueRow(label: "Duration", value: formatDuration(request))
      }
      Section {
        if let response {
          if showRaw, let raw = request.responseBody {
            bodyText(raw)
          } else {
            bodyContent(response)
          }
        } else {
          Text(request.endTime == nil ? "Waiting for response" : "None")
            .foregroundStyle(.secondary)
        }
      } header: {
        HStack {
          Text(response.map { "Response · \(showRaw ? "Raw" : $0.label)" } ?? "Response")
          Spacer()
          if response?.hasRawView == true {
            Button(showRaw ? "Formatted" : "Raw") { showRaw.toggle() }
              .font(.footnote)
          }
        }
      } footer: {
        if request.responseBodyTruncated == true {
          Text("Truncated to the first 100,000 characters.")
        }
      }
      headerSection("Request Headers", request.requestHeaders)
      if let cookies = request.cookies {
        Section("Cookies") { bodyText(cookies) }
      }
      if let body = request.requestBody {
        Section("Request Body") {
          switch body {
          case .text(let text):
            bodyContent(
              BodyFormat.view(
                body: text,
                contentType: BodyFormat.headerValue(request.requestHeaders, "content-type")))
          case .form(let fields):
            ForEach(fields, id: \.self) { field in
              ValueRow(
                label: field.name, value: field.value ?? "File: \(field.fileName ?? "unnamed")")
            }
          case .binary(let byteLength):
            Text(
              "Binary body (\(byteLength.map { "\($0) bytes" } ?? "unknown size")), not captured"
            )
            .foregroundStyle(.secondary)
          }
        }
      }
      if let headers = request.responseHeaders {
        headerSection("Response Headers", headers)
      }
    }
    .navigationTitle(request.method)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      Menu("Copy", systemImage: "doc.on.doc") { RequestCopyMenu(request: request) }
    }
  }

  private var response: BodyView? { BodyFormat.responseView(request) }

  private var statusText: String {
    if let error = request.error { return error }
    guard let status = request.status else { return "Pending" }
    return [String(status), request.statusText ?? ""].joined(separator: " ")
      .trimmingCharacters(in: .whitespaces)
  }

  @ViewBuilder
  private func headerSection(_ title: String, _ headers: [String: String]) -> some View {
    Section(title) {
      if headers.isEmpty {
        Text("None").foregroundStyle(.secondary)
      }
      ForEach(headers.sorted { $0.key < $1.key }, id: \.key) { name, value in
        ValueRow(label: name, value: value)
      }
    }
  }

  @ViewBuilder
  private func bodyContent(_ view: BodyView) -> some View {
    switch view {
    case .image(_, let data):
      if let image = UIImage(data: data) {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
          .frame(maxHeight: 300)
          .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.image = image }
          }
      } else {
        Text("Image could not be decoded").foregroundStyle(.secondary)
      }
    case .form(let pairs):
      ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
        ValueRow(label: pair.name, value: pair.value)
      }
    case .json(let text), .xml(let text), .html(let text), .text(let text):
      bodyText(text)
    }
  }

  private func bodyText(_ text: String) -> some View {
    let shown =
      text.count > Self.displayLimit ? String(text.prefix(Self.displayLimit)) + "…" : text
    return Text(shown)
      .font(.footnote)
      .contextMenu {
        Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
      }
  }
}
