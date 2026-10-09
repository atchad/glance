import AppKit
import SwiftUI

/// A shared geometry for settings panes; controls retain their native styles.
struct SettingsForm<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) { content }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }
    .font(.body)
    .controlSize(.small)
    .toggleStyle(.switch)
    .labeledContentStyle(SettingsRowStyle())
  }
}

struct SettingsRowStyle: LabeledContentStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 12) {
      configuration.label
      Spacer(minLength: 16)
      configuration.content
    }
    .accessibilityElement(children: .contain)
  }
}

struct SettingsGroup<Content: View, Header: View, Footer: View>: View {
  let content: Content
  let header: Header
  let footer: Footer
  var rowPadding: CGFloat = 10

  init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header,
       @ViewBuilder footer: () -> Footer) {
    self.content = content()
    self.header = header()
    self.footer = footer()
  }

  func compactRows() -> Self {
    var group = self
    group.rowPadding = 6
    return group
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if Header.self != EmptyView.self {
        header.font(.headline).padding(.horizontal, 10)
      }
      Group {
        if #available(macOS 15, *) {
          Group(subviews: content) { rows in
            VStack(spacing: 0) {
              ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                  Rectangle().fill(Color.primary.opacity(0.07))
                    .frame(height: 0.5).padding(.horizontal, 10)
                }
                row.frame(maxWidth: .infinity, alignment: .leading)
                  .padding(.horizontal, 10).padding(.vertical, rowPadding)
              }
            }
          }
        } else {
          VStack(alignment: .leading, spacing: 12) { content }.padding(10)
        }
      }
      .modifier(SettingsSurface())
      if Footer.self != EmptyView.self { footer.padding(.horizontal, 10) }
    }
  }
}

extension SettingsGroup where Footer == EmptyView {
  init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header) {
    self.init(content: content, header: header, footer: { EmptyView() })
  }
}

extension SettingsGroup where Header == Text, Footer == EmptyView {
  init(_ title: String, @ViewBuilder content: () -> Content) {
    self.init(content: content, header: { Text(title) }, footer: { EmptyView() })
  }
}

extension SettingsGroup where Header == EmptyView, Footer == EmptyView {
  init(@ViewBuilder content: () -> Content) {
    self.init(content: content, header: { EmptyView() }, footer: { EmptyView() })
  }
}

struct SettingsPicker<Selection: Hashable, Content: View>: View {
  let title: String
  @Binding var selection: Selection
  @ViewBuilder let content: Content

  init(_ title: String, selection: Binding<Selection>, @ViewBuilder content: () -> Content) {
    self.title = title
    _selection = selection
    self.content = content()
  }

  var body: some View {
    LabeledContent(title) {
      Picker(title, selection: $selection) { content }
        .labelsHidden().fixedSize()
        .pickerStyle(.menu)
        .buttonStyle(.borderless)
    }
  }
}

/// AppKit supplies the standard search icon, cancel button, and editing behavior.
struct SettingsSearchField: NSViewRepresentable {
  @Binding var text: String
  var prompt = "Search shortcuts"

  func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

  func makeNSView(context: Context) -> NSSearchField {
    let field = NSSearchField()
    field.placeholderString = prompt
    field.setAccessibilityLabel(prompt)
    field.sendsSearchStringImmediately = true
    field.sendsWholeSearchString = false
    field.delegate = context.coordinator
    return field
  }

  func updateNSView(_ field: NSSearchField, context: Context) {
    context.coordinator.text = $text
    if field.stringValue != text { field.stringValue = text }
  }

  func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSearchField, context: Context) -> CGSize? {
    CGSize(width: proposal.width ?? 220, height: nsView.intrinsicContentSize.height)
  }

  final class Coordinator: NSObject, NSSearchFieldDelegate {
    var text: Binding<String>
    init(text: Binding<String>) { self.text = text }
    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSSearchField else { return }
      text.wrappedValue = field.stringValue
    }
  }
}

/// Let AppKit draw the sidebar material and react to window activation and appearance.
struct SettingsSidebarMaterial: NSViewRepresentable {
  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = .sidebar
    view.blendingMode = .behindWindow
    view.state = .followsWindowActiveState
    return view
  }
  func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct SettingsSurface: ViewModifier {
  @Environment(\.colorScheme) private var colorScheme
  func body(content: Content) -> some View {
    content.background(
      colorScheme == .light ? Color(nsColor: .controlBackgroundColor) : Color.primary.opacity(0.035),
      in: RoundedRectangle(cornerRadius: 10, style: .continuous))
  }
}

struct SettingsSidebarSurface: View {
  var body: some View {
    if #available(macOS 26, *) {
      Color.clear.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    } else {
      SettingsSidebarMaterial()
    }
  }
}
