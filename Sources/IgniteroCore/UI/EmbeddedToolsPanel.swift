import AppKit
import SwiftUI

@MainActor
public final class EmbeddedToolsPanel: NSPanel, NSWindowDelegate {
  private let model: EmbeddedToolsModel
  private var presentedMode: EmbeddedToolsModel.Mode
  public var onDismiss: (() -> Void)?
  /// - Parameter logoStore: ブランドアイコンの読み込み元。nil なら `.app` に同梱したものを読む。
  public init(model: EmbeddedToolsModel, logoStore: ProviderLogoStore? = nil) {
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
      rootView: EmbeddedToolsView(model: model, onClose: { [weak self] in self?.close() })
        .environment(\.providerLogoStore, logoStore))
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
        if let snapshot = model.usage, let date = AIUsageDate.parse(snapshot.report.generated_at) {
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
        // 全行の残り時間と色を同じ時刻から計算する。行ごとに時計を持つと、しきい値の境界で
        // 行によって判定が食い違う (ai-usage の TUI も 1 回の描画で時刻を 1 度だけ取る)。
        TimelineView(.periodic(from: .now, by: 1)) { context in
          LazyVStack(alignment: .leading, spacing: 0) {
            if let snapshot = model.usage {
              if snapshot.report.accounts.isEmpty { Text("対象のアカウントがありません。ai-usageの設定を確認してください。") }
              ForEach(Array(snapshot.report.accounts.enumerated()), id: \.offset) { _, account in
                UsageAccountView(account: account, now: context.date)
                Divider()
              }
            } else if !model.isLoading {
              Text("利用枠を取得するには「更新」を押してください。").foregroundStyle(.secondary)
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
        }
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

// MARK: - AI利用枠の一覧
//
// 色の規則は ai-usage と同じ (しきい値は AIUsageStyle.swift、色の値は AIUsageColors.swift)。
// 各行は親の TimelineView が渡す同じ `now` で、残り時間の表記と色を計算する。

private struct UsageAccountView: View {
  let account: AIUsageAccount
  let now: Date
  @State private var showsDetails = false
  @Environment(\.colorScheme) private var scheme
  @Environment(\.colorSchemeContrast) private var contrast
  var body: some View {
    HStack(spacing: 12) {
      UsageAccountHeading(account: account)
        .frame(width: 154, alignment: .leading)
      if account.ok {
        UsageWindowView(
          window: account.five_hour, isShortSlot: true, provider: account.provider, now: now)
        UsageWindowView(
          window: account.weekly, isShortSlot: false, provider: account.provider, now: now)
      } else {
        // ai-usage と同じく、取得の失敗は ALERT (赤) で示す。
        Label("取得失敗", systemImage: "exclamationmark.triangle")
          .font(.caption)
          .foregroundStyle(AIUsageColors.level(.critical, scheme: scheme, contrast: contrast))
          .frame(maxWidth: .infinity, alignment: .leading)
        Text("詳細で確認").font(.caption).foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      UsageResetSummary(resets: account.ok ? account.manual_resets ?? [] : [], now: now)
        .frame(width: 90, alignment: .leading)
      Button {
        showsDetails.toggle()
      } label: {
        Image(systemName: "info.circle").frame(width: 24, height: 28)
      }.buttonStyle(.plain).foregroundStyle(.secondary)
        .accessibilityLabel(
          "\(AIUsageProvider.label(for: account.provider)) \(account.displayName)の詳細"
        )
        .popover(isPresented: $showsDetails) {
          UsageAccountDetails(account: account, now: now)
        }
    }.padding(.horizontal, 8).padding(.vertical, 7)
      .frame(minHeight: 54)
  }
}

/// アカウント列。ブランドアイコンと provider 名、その下に表示名。
private struct UsageAccountHeading: View {
  let account: AIUsageAccount
  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 5) {
        ProviderLogoView(provider: account.provider, size: 15)
        Text(AIUsageProvider.label(for: account.provider))
          .font(.system(size: 13, weight: .semibold)).lineLimit(1)
      }
      Text(account.displayName).font(.caption).foregroundStyle(.secondary)
        .lineLimit(1).truncationMode(.middle).help(account.displayName)
    }
    .accessibilityElement(children: .combine)
  }
}

/// プロバイダのブランドアイコン。ai-usage と同じ色 (Codex と Grok は前景色) で塗る。
/// 読めなければ何も描かない (provider 名の文字だけで識別できる)。
private struct ProviderLogoView: View {
  let provider: String
  let size: CGFloat
  @Environment(\.colorScheme) private var scheme
  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.providerLogoStore) private var store
  var body: some View {
    if let provider = AIUsageProvider(rawValue: provider),
      let image = (store ?? ProviderLogoStore.shared).image(for: provider)
    {
      Image(nsImage: image).renderingMode(.template).resizable().interpolation(.high)
        .aspectRatio(contentMode: .fit)
        .frame(width: size, height: size)
        .foregroundStyle(AIUsageColors.marker(provider, scheme: scheme, contrast: contrast))
        .accessibilityHidden(true)
    }
  }
}

private struct UsageWindowView: View {
  let window: AIUsageWindow?
  let isShortSlot: Bool
  let provider: String
  let now: Date
  @Environment(\.colorScheme) private var scheme
  @Environment(\.colorSchemeContrast) private var contrast

  private var fallbackTitle: String { isShortSlot ? "短期枠" : "長期枠" }

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      if let window {
        let percent = window.used_percent.flatMap { $0.isFinite ? $0 : nil }
        let level = percent.map(AIUsageLevel.usage)
        HStack(spacing: 4) {
          Text(window.title(fallback: fallbackTitle)).foregroundStyle(.secondary)
          Spacer(minLength: 0)
          // 80% 以上は ai-usage と同じく太字にし、色以外でも目立たせる。
          Text(
            percent.map { "\($0.formatted(.number.precision(.fractionLength(0...1))))%" } ?? "不明"
          )
          .fontWeight(level?.isEmphasized == true ? .bold : .medium).monospacedDigit()
          .foregroundStyle(style(level))
        }.font(.caption)
        UsageBar(
          fraction: percent.map { min(1, max(0, $0 / 100)) },
          fill: level.map { AIUsageColors.level($0, scheme: scheme, contrast: contrast) })
        countdown(window)
      } else {
        Text("—").font(.caption).foregroundStyle(.secondary)
          .accessibilityLabel("\(fallbackTitle)の情報なし")
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private func countdown(_ window: AIUsageWindow) -> some View {
    if let date = AIUsageDate.parse(window.resets_at) {
      let seconds = AIUsageCountdown.remainingSeconds(until: date, now: now)
      let period = AIUsagePeriod.resolve(
        kind: window.kind, isShortSlot: isShortSlot, provider: provider)
      Text(AIUsageCountdown.text(remainingSeconds: seconds))
        .font(.system(size: 11)).monospacedDigit()
        .foregroundStyle(style(AIUsageCountdown.level(remainingSeconds: seconds, period: period)))
        .help("リセット: \(date.formatted(date: .abbreviated, time: .shortened))")
    } else {
      Text("リセット時刻不明").font(.system(size: 11)).foregroundStyle(.secondary)
    }
  }

  private func style(_ level: AIUsageLevel?) -> AnyShapeStyle {
    level.map { AnyShapeStyle(AIUsageColors.level($0, scheme: scheme, contrast: contrast)) }
      ?? AnyShapeStyle(.secondary)
  }
}

/// 使用率のバー。点灯部は段階色、未点灯部は控えめな塗り。使用率が不明なら点灯部を描かず、
/// 0% と区別できるよう文字は「不明」にする。100% を超えた分はバーでは満杯で止める。
private struct UsageBar: View {
  let fraction: Double?
  let fill: Color?
  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Rectangle().fill(.quaternary)
        if let fraction, fraction > 0, let fill {
          Rectangle().fill(fill).frame(width: proxy.size.width * fraction)
        }
      }
      .clipShape(Capsule())
    }
    .frame(height: 4)
    .accessibilityHidden(true)
  }
}

/// 手動リセットの列。種類ごとの残回数と、最も近い有効期限 (残り 7 日未満は赤)。
private struct UsageResetSummary: View {
  let resets: [AIUsageReset]
  let now: Date
  @Environment(\.colorScheme) private var scheme
  @Environment(\.colorSchemeContrast) private var contrast
  var body: some View {
    let groups = AIUsageManualResets.summarize(resets, now: now)
    VStack(alignment: .leading, spacing: 2) {
      if groups.isEmpty { Text("—").foregroundStyle(.secondary) }
      ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
        Text(group.countText)
          .foregroundStyle(group.paused ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
      }
      if let nearest = AIUsageManualResets.nearestDeadline(in: groups) {
        if let expiry = nearest.expiry {
          // ai-usage と同じく、色を変えるのは期限の日付だけ。
          let date = Text(AIUsageManualResets.shortDateText(expiry, now: now))
            .foregroundStyle(
              deadlineStyle(urgent: AIUsageManualResets.isDeadlineUrgent(expiry, now: now)))
          Text("期限 \(date)").foregroundStyle(.secondary)
            .help("手動リセットの期限: \(expiry.formatted(date: .abbreviated, time: .shortened))")
        } else {
          Text("期限 不明").foregroundStyle(.secondary)
        }
      }
    }.font(.system(size: 11)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.85)
  }

  private func deadlineStyle(urgent: Bool) -> AnyShapeStyle {
    urgent
      ? AnyShapeStyle(AIUsageColors.level(.critical, scheme: scheme, contrast: contrast))
      : AnyShapeStyle(.secondary)
  }
}

private struct UsageAccountDetails: View {
  let account: AIUsageAccount
  let now: Date
  @Environment(\.colorScheme) private var scheme
  @Environment(\.colorSchemeContrast) private var contrast
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 6) {
          ProviderLogoView(provider: account.provider, size: 17)
          Text("\(AIUsageProvider.label(for: account.provider)) · \(account.displayName)")
            .font(.headline)
        }
        if let group = account.group_label { Text(group) }
        if let plan = account.plan { Text("プラン: \(plan)") }
        if let email = account.email ?? account.profile_email { Text(email) }
        if account.ok {
          ForEach(Array([account.five_hour, account.weekly].enumerated()), id: \.offset) {
            index, window in
            if let window, let date = AIUsageDate.parse(window.resets_at) {
              let title = window.title(fallback: index == 0 ? "短期枠" : "長期枠")
              Text("\(title) リセット: \(date.formatted(date: .abbreviated, time: .shortened))")
            }
          }
          let groups = AIUsageManualResets.summarize(account.manual_resets ?? [], now: now)
          ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
            VStack(alignment: .leading, spacing: 2) {
              Text("手動リセット \(group.countText)")
              ForEach(Array(group.deadlines.enumerated()), id: \.offset) { _, deadline in
                deadlineRow(deadline)
              }
            }
          }
        } else {
          Text(account.error ?? "利用枠を取得できませんでした。")
            .foregroundStyle(AIUsageColors.level(.critical, scheme: scheme, contrast: contrast))
        }
      }.frame(maxWidth: .infinity, alignment: .leading).padding(16).textSelection(.enabled)
    }.frame(width: 380, height: 250)
  }

  /// 付与分ごとの期限。ai-usage の TUI と同じく、期限の日時だけを残り 7 日未満で赤にする。
  private func deadlineRow(_ deadline: AIUsageResetGroup.Deadline) -> some View {
    HStack(spacing: 4) {
      Text("\(deadline.count)回").foregroundStyle(.secondary)
      if let expiry = deadline.expiry {
        Text("\(expiry.formatted(date: .abbreviated, time: .shortened))まで")
          .foregroundStyle(
            AIUsageManualResets.isDeadlineUrgent(expiry, now: now)
              ? AnyShapeStyle(AIUsageColors.level(.critical, scheme: scheme, contrast: contrast))
              : AnyShapeStyle(.secondary))
      } else {
        Text("期限不明").foregroundStyle(.secondary)
      }
    }.padding(.leading, 12).font(.callout).monospacedDigit()
  }
}
