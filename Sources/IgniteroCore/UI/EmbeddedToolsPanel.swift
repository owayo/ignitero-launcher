import AppKit
import SwiftUI

@MainActor
public final class EmbeddedToolsPanel: NSPanel, NSWindowDelegate {
  private let model: EmbeddedToolsModel
  private var presentedMode: EmbeddedToolsModel.Mode
  public var onDismiss: (() -> Void)?
  public init(model: EmbeddedToolsModel) {
    self.model = model
    presentedMode = model.mode
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 760, height: model.mode == .usage ? 440 : 560),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: true)
    minSize = NSSize(
      width: model.mode == .usage ? 680 : 560, height: model.mode == .usage ? 340 : 380)
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
    if presentedMode != model.mode {
      minSize = NSSize(
        width: model.mode == .usage ? 680 : 560, height: model.mode == .usage ? 340 : 380)
      setContentSize(NSSize(width: 760, height: model.mode == .usage ? 440 : 560))
      presentedMode = model.mode
    }
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
  @State private var showsHelp = false
  @State private var showsWarnings = false
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
          Button("ヘルプ") { showsHelp.toggle() }
            .popover(isPresented: $showsHelp) {
              VStack(alignment: .leading, spacing: 12) {
                Text("AI利用枠の取得").font(.headline)
                Text("ai-usageの設定と認証情報を使います。Chromeのアカウントが表示されない場合は、macOSのアクセス許可を確認し、アプリを再起動してください。")
                Button("アクセス設定…") {
                  if let url = URL(
                    string:
                      "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
                  {
                    NSWorkspace.shared.open(url)
                  }
                }
              }.padding(16).frame(width: 320)
            }
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
    }.padding(model.mode == .usage ? 16 : 20).frame(maxWidth: .infinity, maxHeight: .infinity)
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
        if let warnings = model.usage?.warnings, !warnings.isEmpty {
          Button {
            showsWarnings.toggle()
          } label: {
            Label("警告 \(warnings.count)件", systemImage: "exclamationmark.triangle")
          }.controlSize(.small)
            .popover(isPresented: $showsWarnings) {
              ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                  ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                    Text(warning).textSelection(.enabled)
                  }
                }.padding(16)
              }.frame(width: 380, height: 240)
            }
        }
      }
      HStack(spacing: 12) {
        Text("アカウント").frame(width: 154, alignment: .leading)
        Text("短期枠").frame(maxWidth: .infinity, alignment: .leading)
        Text("長期枠").frame(maxWidth: .infinity, alignment: .leading)
        Text("手動リセット").frame(width: 90, alignment: .leading)
        Color.clear.frame(width: 24, height: 1)
      }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          if let snapshot = model.usage {
            if snapshot.report.accounts.isEmpty { Text("対象のアカウントがありません。ai-usageの設定を確認してください。") }
            ForEach(Array(snapshot.report.accounts.enumerated()), id: \.offset) { _, account in
              UsageAccountView(account: account)
              Divider()
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
  @State private var showsDetails = false
  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(account.provider.capitalized).font(.system(size: 13, weight: .semibold))
        Text(account.displayName).font(.caption).foregroundStyle(.secondary)
          .lineLimit(1).truncationMode(.middle).help(account.displayName)
      }.frame(width: 154, alignment: .leading)
      if account.ok {
        UsageWindowView(window: account.five_hour, fallbackTitle: "短期枠")
        UsageWindowView(window: account.weekly, fallbackTitle: "長期枠")
      } else {
        Label("取得失敗", systemImage: "exclamationmark.triangle")
          .font(.caption).foregroundStyle(.orange)
          .frame(maxWidth: .infinity, alignment: .leading)
        Text("詳細で確認").font(.caption).foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      UsageResetSummary(resets: account.ok ? account.manual_resets ?? [] : [])
        .frame(width: 90, alignment: .leading)
      Button {
        showsDetails.toggle()
      } label: {
        Image(systemName: "info.circle").frame(width: 24, height: 28)
      }.buttonStyle(.plain).foregroundStyle(.secondary)
        .accessibilityLabel("\(account.provider) \(account.displayName)の詳細")
        .popover(isPresented: $showsDetails) { UsageAccountDetails(account: account) }
    }.padding(.horizontal, 8).padding(.vertical, 7)
      .frame(minHeight: 54)
  }
}
private struct UsageWindowView: View {
  let window: AIUsageWindow?
  let fallbackTitle: String
  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      if let window {
        HStack(spacing: 4) {
          Text(window.title(fallback: fallbackTitle)).foregroundStyle(.secondary)
          Spacer(minLength: 0)
          Text(
            window.used_percent.map {
              "\($0.formatted(.number.precision(.fractionLength(0...1))))%"
            } ?? "不明"
          )
          .fontWeight(.medium).monospacedDigit()
        }.font(.caption)
        if let value = window.used_percent, value.isFinite {
          ProgressView(value: min(100, max(0, value)), total: 100)
            .tint(value >= 100 ? .red : value >= 90 ? .orange : .accentColor)
            .controlSize(.mini).frame(height: 3)
        }
        if let date = parseDate(window.resets_at) {
          TimelineView(.periodic(from: .now, by: 1)) { context in
            let minutes = max(0, Int(ceil(date.timeIntervalSince(context.date) / 60)))
            Text(minutes == 0 ? "リセット待ち" : "あと\(minutes / 60)時間\(minutes % 60)分")
              .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
          }
        }
      } else {
        Text("—").font(.caption).foregroundStyle(.secondary)
          .accessibilityLabel("\(fallbackTitle)の情報なし")
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)
  }
}
private struct UsageResetSummary: View {
  let resets: [AIUsageReset]
  var body: some View {
    TimelineView(.periodic(from: .now, by: 60)) { context in
      VStack(alignment: .leading, spacing: 2) {
        if resets.isEmpty { Text("—").foregroundStyle(.secondary) }
        ForEach(Array(resets.enumerated()), id: \.offset) { index, reset in
          let title = resetTitle(reset.kind, fallback: "枠\(index + 1)")
          if reset.paused == true {
            Text("\(title) 停止中").foregroundStyle(.secondary)
          } else if let expiry = parseDate(reset.expires_at), expiry <= context.date {
            Text("\(title) 期限切れ").foregroundStyle(.secondary)
          } else {
            Text("\(title) \(reset.remaining.map { "\($0)回" } ?? "不明")")
          }
        }
      }.font(.system(size: 11)).monospacedDigit().lineLimit(1)
    }
  }
}
private struct UsageAccountDetails: View {
  let account: AIUsageAccount
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        Text("\(account.provider.capitalized) · \(account.displayName)").font(.headline)
        if let group = account.group_label { Text(group) }
        if let plan = account.plan { Text("プラン: \(plan)") }
        if let email = account.email ?? account.profile_email { Text(email) }
        if account.ok {
          ForEach(Array([account.five_hour, account.weekly].enumerated()), id: \.offset) {
            index, window in
            if let window {
              let title = window.title(fallback: index == 0 ? "短期枠" : "長期枠")
              if let date = parseDate(window.resets_at) {
                Text("\(title) リセット: \(date.formatted(date: .abbreviated, time: .shortened))")
              }
            }
          }
          UsageResetSummary(resets: account.manual_resets ?? [])
          ForEach(Array((account.manual_resets ?? []).enumerated()), id: \.offset) { index, reset in
            if let date = parseDate(reset.expires_at) {
              Text(
                "\(resetTitle(reset.kind, fallback: "枠\(index + 1)"))の手動リセット期限: \(date.formatted(date: .abbreviated, time: .shortened))"
              )
            }
          }
        } else {
          Text(account.error ?? "利用枠を取得できませんでした。").foregroundStyle(.orange)
        }
      }.frame(maxWidth: .infinity, alignment: .leading).padding(16).textSelection(.enabled)
    }.frame(width: 380, height: 250)
  }
}
private func resetTitle(_ kind: String?, fallback: String) -> String {
  switch kind {
  case "full": "全枠"
  case "five_hour": "5時間"
  case "daily": "1日"
  case "weekly": "1週間"
  case "monthly": "1か月"
  default: fallback
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
