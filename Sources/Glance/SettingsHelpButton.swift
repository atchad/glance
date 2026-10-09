import SwiftUI

/// Secondary explanations use the standard macOS information button and popover.
struct SettingsHelpButton: View {
  let title: String
  let message: String
  @State private var isPresented = false

  var body: some View {
    Button {
      isPresented.toggle()
    } label: {
      Image(systemName: "info.circle")
        .foregroundStyle(.secondary)
    }
    .buttonStyle(.borderless)
    .accessibilityLabel("About \(title)")
    .help("About \(title)")
    .popover(isPresented: $isPresented) {
      VStack(alignment: .leading, spacing: 8) {
        Text(title).font(.headline)
        Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
      }
      .padding(16)
      .frame(width: 300, alignment: .leading)
    }
  }
}

/// Match the small, leading-aligned secondary explanations in macOS settings.
struct SettingsDescription: View {
  let text: String
  init(_ text: String) { self.text = text }

  var body: some View {
    Text(text)
      .font(.subheadline)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}
