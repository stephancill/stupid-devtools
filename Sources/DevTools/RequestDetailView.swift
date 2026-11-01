import DevToolsCore
import SwiftUI

struct RequestDetailView: View {
  let request: RequestEntry

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
        if let responseBody = request.responseBody {
          bodyText(responseBody)
        } else {
          Text(request.endTime == nil ? "Waiting for response" : "None")
            .foregroundStyle(.secondary)
        }
      } header: {
        Text("Response Body")
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
          case .text(let text): bodyText(text)
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

  private func bodyText(_ text: String) -> some View {
    let pretty = prettyJSON(text) ?? text
    let shown =
      pretty.count > Self.displayLimit ? String(pretty.prefix(Self.displayLimit)) + "…" : pretty
    return Text(shown)
      .font(.footnote)
      .contextMenu {
        Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = pretty }
      }
  }

  private func prettyJSON(_ text: String) -> String? {
    guard
      let object = try? JSONSerialization.jsonObject(
        with: Data(text.utf8), options: .fragmentsAllowed),
      object is [Any] || object is [String: Any],
      let data = try? JSONSerialization.data(
        withJSONObject: object, options: [.prettyPrinted, .withoutEscapingSlashes])
    else { return nil }
    return String(decoding: data, as: UTF8.self)
  }
}
