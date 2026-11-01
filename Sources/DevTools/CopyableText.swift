import SwiftUI
import UIKit

/// A middle-truncated single-line value that copies its full value from the native
/// long-press edit menu.
struct CopyableText: UIViewRepresentable {
  let value: String
  var alignment: NSTextAlignment = .right

  func makeCoordinator() -> Coordinator { Coordinator(value: value) }

  func makeUIView(context: Context) -> UILabel {
    let label = UILabel()
    label.textColor = .secondaryLabel
    label.font = .preferredFont(forTextStyle: .body)
    label.adjustsFontForContentSizeCategory = true
    label.lineBreakMode = .byTruncatingMiddle
    label.numberOfLines = 1
    label.isUserInteractionEnabled = true
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let interaction = UIEditMenuInteraction(delegate: context.coordinator)
    label.addInteraction(interaction)
    label.addGestureRecognizer(
      UILongPressGestureRecognizer(
        target: context.coordinator, action: #selector(Coordinator.showMenu(_:))))
    context.coordinator.label = label
    context.coordinator.interaction = interaction
    return label
  }

  func updateUIView(_ label: UILabel, context: Context) {
    label.text = value
    label.textAlignment = alignment
    context.coordinator.value = value
  }

  @MainActor
  final class Coordinator: NSObject, @preconcurrency UIEditMenuInteractionDelegate {
    var value: String
    weak var label: UILabel?
    var interaction: UIEditMenuInteraction?

    init(value: String) { self.value = value }

    @objc func showMenu(_ recognizer: UILongPressGestureRecognizer) {
      guard recognizer.state == .began, let label, let interaction else { return }
      interaction.presentEditMenu(
        with: UIEditMenuConfiguration(identifier: nil, sourcePoint: recognizer.location(in: label)))
    }

    func editMenuInteraction(
      _ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration,
      suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
      UIMenu(children: [
        UIAction(title: "Copy") { [value] _ in UIPasteboard.general.string = value }
      ])
    }

    func editMenuInteraction(
      _ interaction: UIEditMenuInteraction, targetRectFor configuration: UIEditMenuConfiguration
    ) -> CGRect {
      label?.bounds ?? .null
    }
  }
}

/// A label and value row whose value copies on long press.
struct ValueRow: View {
  let label: String
  let value: String

  var body: some View {
    HStack {
      Text(label)
      CopyableText(value: value)
        .frame(maxWidth: .infinity)
    }
  }
}
