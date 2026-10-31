import AppKit
import SwiftUI

@MainActor
public final class EmbeddedToolsPanel: NSPanel, NSWindowDelegate {
  private let model: EmbeddedToolsModel
  public var onDismiss: (() -> Void)?
  public init(model: EmbeddedToolsModel) {
    self.model = model
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: true)
    minSize = NSSize(width: 560, height: 380)
    isReleasedWhenClosed = false
    isFloatingPanel = true
    level = .floating
    delegate = self
    contentView = SafeHostingView.makeContainer(
      rootView: EmbeddedToolsView(model: model, onClose: { [weak self] in self?.close() }))
  }
  public override var canBecomeKey: Bool { true }
  public override func cancelOperation(_ sender: Any?) { close() }
  public func windowWillClose(_ notification: Notification) { onDismiss?() }
  public func present() {
    title = model.mode == .usage ? "AI利用枠" : "WebページをMarkdownでコピー"
    let screen =
      NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
    if let visible = screen?.visibleFrame {
      let width = min(frame.width, max(1, visible.width - 32))
      let height = min(frame.height, max(1, visible.height - 32))
      setFrame(
        NSRect(
          x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height),
        display: false)
    } else {
      center()
    }
    NSApp.activate()
    makeKeyAndOrderFront(nil)
  }
}

private struct EmbeddedToolsView: View {
  @Bindable var model: EmbeddedToolsModel
  let onClose: () -> Void
  @State private var copied = false
  @FocusState private var urlFocused: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if model.mode == .usage { usageView } else { markdownView }
      if !model.errorMessage.isEmpty {
        Text(model.errorMessage).font(.callout).foregroundStyle(.red).textSelection(.enabled)
          .lineLimit(5).accessibilityLabel("取得エラー")
      }
      HStack {
        Button("閉じる", action: onClose).keyboardShortcut(.cancelAction)
        if model.isLoading {
          ProgressView().controlSize(.small)
          Text(model.mode == .usage ? "利用枠を取得中…" : "ページを取得中…").foregroundStyle(.secondary)
          Button("中止") { model.cancelRequest() }
        }
        Spacer()
        if model.mode == .usage {
          Button("更新") { model.refreshUsage() }.keyboardShortcut("r", modifiers: .command).disabled(
            model.isLoading)
        } else {
          Button(copied ? "コピーしました" : "Markdownをコピー") {
            guard model.canCopyMarkdown else { return }
            NSPasteboard.general.clearContents()
            copied = NSPasteboard.general.setString(model.markdownText, forType: .string)
          }.keyboardShortcut("c", modifiers: [.command, .shift]).disabled(!model.canCopyMarkdown)
        }
      }
    }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
      .onChange(of: model.isActive) { _, active in urlFocused = active && model.mode == .markdown }
      .onChange(of: model.mode) { _, mode in urlFocused = mode == .markdown }
      .onAppear { urlFocused = model.mode == .markdown }
      .onChange(of: model.markdownText) { _, _ in copied = false }
      .onChange(of: model.isLoading) { _, _ in copied = false }
  }
  private var usageView: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("AI利用枠").font(.title2.bold())
        Spacer()
        if let snapshot = model.usage, let date = parseDate(snapshot.report.generated_at) {
          Text("表示更新: \(date.formatted(date: .omitted, time: .shortened))").font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Text("各サービスの使用率とリセット予定を確認できます。更新に失敗した場合は、前回の表示を残します。")
        .font(.caption).foregroundStyle(.secondary)
      HStack(alignment: .top) {
        Text("Chromeのアカウントが表示されない場合は、macOSのアクセス許可を確認し、アプリを再起動してください。")
          .font(.caption).foregroundStyle(.secondary)
        Button("アクセス設定…") {
          if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
          {
            NSWorkspace.shared.open(url)
          }
        }.controlSize(.small)
      }
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          if let snapshot = model.usage {
            if snapshot.report.accounts.isEmpty { Text("対象のアカウントがありません。ai-usageの設定を確認してください。") }
            ForEach(Array(snapshot.report.accounts.enumerated()), id: \.offset) { _, account in
              UsageAccountView(account: account)
            }
            ForEach(Array(snapshot.warnings.enumerated()), id: \.offset) { _, warning in
              Text(warning).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
          } else if !model.isLoading {
            Text("利用枠を取得するには「更新」を押してください。").foregroundStyle(.secondary)
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
  private var markdownView: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        TextField("https://example.com/article", text: $model.urlInput)
          .textFieldStyle(.roundedBorder).accessibilityLabel("変換するページのURL").focused($urlFocused)
          .disabled(model.isLoading).onSubmit { if !model.isLoading { model.fetchMarkdown() } }
        Button("取得") { model.fetchMarkdown() }.disabled(model.isLoading)
      }
      if let document = model.document {
        Text(document.title ?? "取得したMarkdown").font(.headline).lineLimit(1)
        Text(document.final_url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
          .textSelection(.enabled)
      } else {
        Text("ChromeまたはChromiumでページを読み込み、Markdownに変換します。")
          .font(.caption).foregroundStyle(.secondary)
      }
      TextEditor(text: $model.markdownText).font(.system(.body, design: .monospaced))
        .accessibilityLabel("Markdownのプレビュー")
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
        .disabled(model.document == nil || model.isLoading)
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct UsageAccountView: View {
  let account: AIUsageAccount
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(account.provider.capitalized).font(.headline)
        if let group = account.group_label {
          Text(group).font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        if let plan = account.plan { Text(plan).font(.caption).foregroundStyle(.secondary) }
      }
      Text(account.displayName).font(.subheadline).textSelection(.enabled)
      if account.ok {
        if let window = account.five_hour { UsageWindowView(window: window, fallbackTitle: "短期枠") }
        if let window = account.weekly { UsageWindowView(window: window, fallbackTitle: "長期枠") }
        if account.five_hour == nil && account.weekly == nil {
          Text("利用枠の詳細がありません。").font(.caption).foregroundStyle(.secondary)
        }
        if let resets = account.manual_resets {
          ForEach(Array(resets.enumerated()), id: \.offset) { _, reset in
            TimelineView(.periodic(from: .now, by: 60)) { context in
              HStack {
                if reset.paused == true {
                  Text("手動リセット: 一時停止中")
                } else if let expiry = parseDate(reset.expires_at), expiry <= context.date {
                  Text("手動リセット: 期限切れ")
                } else {
                  Text(reset.remaining.map { "手動リセット: \($0)回" } ?? "手動リセット: 不明")
                }
                if let date = parseDate(reset.expires_at) {
                  Text("期限 \(date.formatted(date: .abbreviated, time: .shortened))")
                }
              }.font(.caption).foregroundStyle(.secondary)
            }
          }
        }
      } else {
        Text(account.error ?? "利用枠を取得できませんでした。").font(.caption).foregroundStyle(.secondary)
          .textSelection(.enabled)
      }
    }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
      .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
  }
}
private struct UsageWindowView: View {
  let window: AIUsageWindow
  let fallbackTitle: String
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(window.title(fallback: fallbackTitle))
        Spacer()
        Text(
          window.used_percent.map {
            "\($0.formatted(.number.precision(.fractionLength(0...1))))% 使用"
          } ?? "使用率不明")
      }.font(.caption)
      if let value = window.used_percent, value.isFinite {
        ProgressView(value: min(100, max(0, value)), total: 100).tint(
          value >= 90 ? .orange : .accentColor)
      }
      if let date = parseDate(window.resets_at) {
        TimelineView(.periodic(from: .now, by: 1)) { context in
          let seconds = max(0, Int(date.timeIntervalSince(context.date)))
          Text(
            seconds == 0
              ? "リセット予定を過ぎています。更新してください。"
              : "リセットまで \((seconds + 59) / 3600)時間\(((seconds + 59) % 3600) / 60)分"
          )
          .font(.caption).foregroundStyle(.secondary)
        }
      }
    }
  }
}
private func parseDate(_ text: String?) -> Date? {
  guard let text else { return nil }
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  if let date = formatter.date(from: text) { return date }
  formatter.formatOptions = [.withInternetDateTime]
  return formatter.date(from: text)
}
