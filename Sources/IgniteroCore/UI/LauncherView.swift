import AppKit
import SwiftUI

// MARK: - LauncherView

/// ランチャーのメイン SwiftUI ビュー。
///
/// 検索テキストフィールド、検索結果リスト、計算結果行、アップデートバナーを表示する。
/// ロジックはすべて `LauncherViewModel` に委譲し、ビューは表示のみを担当する。
public struct LauncherView: View {

  // MARK: - Dependencies

  @Bindable var viewModel: LauncherViewModel

  @FocusState private var isSearchFieldFocused: Bool
  @State private var scanRotation: Double = 0

  // MARK: - Callbacks

  /// 検索結果が選択・実行された際のコールバック
  var onExecute: ((SearchResult) -> Void)?

  /// ランチャーを非表示にする際のコールバック
  var onDismiss: (() -> Void)?

  /// エディタピッカーを表示する際のコールバック（ディレクトリパスを渡す）
  var onShowEditorPicker: ((String) -> Void)?

  /// ターミナルピッカーを表示する際のコールバック（ディレクトリパスを渡す）
  var onShowTerminalPicker: ((String) -> Void)?

  /// デフォルトターミナルでディレクトリを開く際のコールバック（ディレクトリパスを渡す）
  var onOpenInTerminal: ((String) -> Void)?

  /// 検索結果件数が変化した際のコールバック（ウィンドウリサイズ用）
  var onResultsCountChanged: ((Int) -> Void)?

  /// キャッシュ更新ボタンが押された際のコールバック
  var onRefreshCache: (() -> Void)?

  /// 設定ボタンが押された際のコールバック
  var onOpenSettings: (() -> Void)?

  // MARK: - Initialization

  /// LauncherView を初期化する。
  ///
  /// - Parameters:
  ///   - viewModel: ランチャービューモデル
  ///   - onExecute: 結果実行コールバック
  ///   - onDismiss: 非表示コールバック
  ///   - onShowEditorPicker: エディタピッカー表示コールバック
  ///   - onShowTerminalPicker: ターミナルピッカー表示コールバック
  ///   - onOpenInTerminal: ターミナル起動コールバック
  ///   - onRefreshCache: キャッシュ更新コールバック
  ///   - onOpenSettings: 設定画面表示コールバック
  public init(
    viewModel: LauncherViewModel,
    onExecute: ((SearchResult) -> Void)? = nil,
    onDismiss: (() -> Void)? = nil,
    onShowEditorPicker: ((String) -> Void)? = nil,
    onShowTerminalPicker: ((String) -> Void)? = nil,
    onOpenInTerminal: ((String) -> Void)? = nil,
    onResultsCountChanged: ((Int) -> Void)? = nil,
    onRefreshCache: (() -> Void)? = nil,
    onOpenSettings: (() -> Void)? = nil
  ) {
    self.viewModel = viewModel
    self.onExecute = onExecute
    self.onDismiss = onDismiss
    self.onShowEditorPicker = onShowEditorPicker
    self.onShowTerminalPicker = onShowTerminalPicker
    self.onOpenInTerminal = onOpenInTerminal
    self.onResultsCountChanged = onResultsCountChanged
    self.onRefreshCache = onRefreshCache
    self.onOpenSettings = onOpenSettings
  }

  // MARK: - Body

  public var body: some View {
    VStack(spacing: 0) {
      // アップデートバナー
      if viewModel.shouldShowUpdateBanner, let version = viewModel.updateBannerVersion {
        updateBanner(version: version)
      }

      // 検索フィールド
      searchField

      // 計算結果行
      if let result = viewModel.calculatorResult {
        calculatorRow(result: result)
      }

      // 検索結果リスト
      if !viewModel.searchResults.isEmpty {
        resultsList
      }
    }
    .frame(width: WindowManager.width)
    .background {
      ZStack {
        RoundedRectangle(cornerRadius: 12)
          .fill(.ultraThinMaterial)
        RoundedRectangle(cornerRadius: 12)
          .fill(warmGradient)
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .strokeBorder(.white.opacity(0.3), lineWidth: 1)
    }
    .onAppear {
      isSearchFieldFocused = true
    }
    .onChange(of: viewModel.focusTrigger) {
      isSearchFieldFocused = true
    }
    .onChange(of: viewModel.searchResults.count) { _, newCount in
      onResultsCountChanged?(newCount)
    }
  }

  // MARK: - Warm Gradient

  /// Tauri 版と同様のウォームグラデーション。
  /// マテリアル背景の上に重ねて暖色のティントを加える。
  private var warmGradient: LinearGradient {
    LinearGradient(
      stops: [
        .init(color: Color(red: 1.0, green: 0.98, blue: 0.96).opacity(0.5), location: 0.0),
        .init(color: Color(red: 1.0, green: 0.71, blue: 0.51).opacity(0.25), location: 0.55),
        .init(color: Color(red: 1.0, green: 0.39, blue: 0.31).opacity(0.25), location: 1.0),
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  // MARK: - Search Field

  private var searchField: some View {
    HStack(spacing: 12) {
      // アプリアイコン
      appLogo

      if viewModel.isScanning {
        // スキャン中: スピナー + テキスト
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text("インデックスを再構築中...")
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
      } else {
        // 検索入力（角丸ボーダー付き）
        searchInput

        // キャッシュ更新ボタン
        toolbarButton(symbol: "arrow.clockwise", tooltip: "キャッシュを更新") {
          onRefreshCache?()
        }

        // 設定ボタン
        toolbarButton(symbol: "gearshape", tooltip: "設定") {
          onOpenSettings?()
        }
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }

  /// アプリアイコン (44x44)。スキャン中はローディングアニメーションを表示。
  private var appLogo: some View {
    Group {
      if viewModel.isScanning {
        Image(systemName: "arrow.trianglehead.2.counterclockwise")
          .font(.system(size: 24))
          .foregroundStyle(Self.ember)
          .rotationEffect(.degrees(scanRotation))
      } else if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
        let nsImage = NSImage(contentsOf: url)
      {
        Image(nsImage: nsImage)
          .resizable()
          .interpolation(.high)
      } else {
        Image(nsImage: NSApp.applicationIconImage)
          .resizable()
          .interpolation(.high)
      }
    }
    .frame(width: 44, height: 44)
    .onChange(of: viewModel.isScanning) { _, isScanning in
      if isScanning {
        scanRotation = 0
        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
          scanRotation = 360
        }
      } else {
        withAnimation(.easeOut(duration: 0.3)) {
          scanRotation = 0
        }
      }
    }
  }

  /// 検索テキストフィールド（虫眼鏡付き）。スキャン中はインラインインジケーターを表示。
  private var searchInput: some View {
    HStack(spacing: 8) {
      if viewModel.isScanning {
        ProgressView()
          .controlSize(.small)
        Text("インデックスを再構築中...")
          .font(.system(size: 14))
          .foregroundStyle(Color(nsColor: .controlTextColor).opacity(0.85))
          .environment(\.colorScheme, .light)
      } else {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(Self.ember.opacity(0.7))
          .font(.system(size: 14))

        TextField(
          "Search apps and directories",
          text: $viewModel.searchQuery
        )
        .textFieldStyle(.plain)
        .font(.system(size: 16))
        .foregroundStyle(Color(nsColor: .controlTextColor).opacity(0.85))
        .environment(\.colorScheme, .light)
        .focused($isSearchFieldFocused)
        .onChange(of: viewModel.searchQuery) {
          viewModel.updateSearch()
        }
        .onSubmit {
          handleEnterKey()
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(.white.opacity(0.75))
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .strokeBorder(Self.ember.opacity(0.2), lineWidth: 1)
    }
  }

  /// ツールバーボタン（リロード・設定用）
  private func toolbarButton(symbol: String, tooltip: String, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 14))
        .foregroundStyle(Color(red: 0.76, green: 0.27, blue: 0.06))  // #c24410
        .frame(width: 36, height: 36)
        .background(.white.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
          RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Self.ember.opacity(0.45), lineWidth: 1.5)
        }
    }
    .buttonStyle(.plain)
    .help(tooltip)
  }

  // MARK: - Calculator Result Row

  private func calculatorRow(result: String) -> some View {
    HStack {
      Image(systemName: "equal")
        .foregroundStyle(Self.ember)
        .font(.system(size: 14))
      Text(result)
        .font(.system(size: 16, weight: .medium, design: .monospaced))
        .foregroundStyle(.primary)
      Spacer()
      Text("Enter to copy")
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(
      LinearGradient(
        colors: [Self.ember.opacity(0.12), Self.ember.opacity(0.06)],
        startPoint: .leading,
        endPoint: .trailing
      )
    )
    .overlay(alignment: .leading) {
      Rectangle()
        .fill(Self.ember.opacity(0.8))
        .frame(width: 3)
    }
  }

  // MARK: - Results List

  private var resultsList: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(Array(viewModel.searchResults.enumerated()), id: \.offset) { index, result in
            resultRow(result: result, index: index)
              .id(index)
          }
        }
      }
      .scrollBounceBehavior(.basedOnSize)
      .onChange(of: viewModel.selectedIndex) { _, newIndex in
        withAnimation(.easeInOut(duration: 0.1)) {
          proxy.scrollTo(newIndex, anchor: .center)
        }
      }
    }
  }

  // MARK: - Theme Colors

  private static let ember = Color(red: 1.0, green: 0.47, blue: 0.28)  // #ff7847
  private static let plasma = Color(red: 1.0, green: 0.70, blue: 0.28)  // #ffb347

  // MARK: - Result Row

  private func resultRow(result: SearchResult, index: Int) -> some View {
    let isSelected = index == viewModel.selectedIndex

    return HStack(spacing: 12) {
      resultIcon(for: result, isSelected: isSelected)

      VStack(alignment: .leading, spacing: 2) {
        Text(result.name)
          .font(.system(size: isSelected ? 17 : 14, weight: isSelected ? .semibold : .medium))
          .lineLimit(1)
          .animation(.easeInOut(duration: 0.14), value: isSelected)

        Text(resultSubtitle(for: result))
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .lineLimit(1)

        if result.kind == .directory {
          let editor = result.editor ?? viewModel.defaultEditorRawValue
          Text("\(editorDisplayName(editor))で開く")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .italic()
        }
      }

      Spacer()

      // ディレクトリの場合、選択時のみキーヒントを表示
      if result.kind == .directory, isSelected {
        directoryKeyHints
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 6)
    .frame(height: WindowManager.rowHeight)
    .background {
      if isSelected {
        selectedRowBackground
      }
    }
    .contentShape(Rectangle())
    .onTapGesture {
      viewModel.selectedIndex = index
      if let selected = viewModel.confirmSelection() {
        onExecute?(selected)
      }
    }
  }

  /// 選択行の背景: 左ボーダー + オレンジグラデーション
  private var selectedRowBackground: some View {
    HStack(spacing: 0) {
      Rectangle()
        .fill(Self.ember.opacity(0.9))
        .frame(width: 3)
      Rectangle()
        .fill(
          LinearGradient(
            colors: [
              Self.ember.opacity(0.25),
              Self.plasma.opacity(0.18),
            ],
            startPoint: .leading,
            endPoint: .trailing
          )
        )
    }
  }

  // MARK: - Result Icon

  private func resultIcon(for result: SearchResult, isSelected: Bool) -> some View {
    Group {
      switch result.kind {
      case .app:
        if let iconPath = result.iconPath,
          let nsImage = NSImage(contentsOfFile: iconPath)
        {
          Image(nsImage: nsImage)
            .resizable()
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
          Image(systemName: "app.fill")
            .font(.system(size: 26))
            .foregroundStyle(.secondary)
        }
      case .directory:
        directoryIcon(editor: result.editor ?? viewModel.defaultEditorRawValue)
      case .command:
        Image(systemName: "terminal.fill")
          .font(.system(size: 26))
          .foregroundStyle(Self.plasma)
      case .webSearch:
        Image(systemName: "globe")
          .font(.system(size: 26))
          .foregroundStyle(.blue)
      case .colorPicker:
        Image(systemName: "eyedropper")
          .font(.system(size: 26))
          .foregroundStyle(.purple)
      case .emoji:
        Image(systemName: "face.smiling")
          .font(.system(size: 26))
          .foregroundStyle(.orange)
      }
    }
    .frame(width: 36, height: 36)
    .scaleEffect(isSelected ? 1.25 : 1.0)
    .shadow(
      color: isSelected ? Self.ember.opacity(0.18) : .clear,
      radius: isSelected ? 6 : 0, y: isSelected ? 2 : 0
    )
    .animation(.easeInOut(duration: 0.14), value: isSelected)
  }

  /// ディレクトリアイコン: フォルダ + エディタオーバーレイ
  private func directoryIcon(editor: String?) -> some View {
    ZStack {
      Image(systemName: "folder.fill")
        .font(.system(size: 26))
        .foregroundStyle(Color(red: 0.37, green: 0.70, blue: 0.96))  // #5EB3F4

      if let editor, let iconPath = viewModel.editorIconPaths[editor],
        let nsImage = NSImage(contentsOfFile: iconPath)
      {
        Image(nsImage: nsImage)
          .resizable()
          .frame(width: 16, height: 16)
          .clipShape(RoundedRectangle(cornerRadius: 2))
          .offset(y: 2)
      }
    }
  }

  /// エディタ rawValue から表示名を取得
  private func editorDisplayName(_ rawValue: String) -> String {
    EditorType(rawValue: rawValue)?.displayName ?? rawValue
  }

  // MARK: - Result Subtitle

  private func resultSubtitle(for result: SearchResult) -> String {
    switch result.kind {
    case .app:
      result.path
    case .directory:
      result.path
    case .command:
      result.command ?? ""
    case .webSearch:
      "ブラウザで検索を開く"
    case .colorPicker:
      "画面上の色を選択してクリップボードにコピー"
    case .emoji:
      "絵文字ピッカーを開く"
    }
  }

  // MARK: - Directory Key Hints

  private var directoryKeyHints: some View {
    let terminalName = viewModel.defaultTerminalName
    return VStack(alignment: .trailing, spacing: 4) {
      keyHintPill(symbol: "arrow.right", label: terminalName)
      HStack(spacing: 4) {
        keyHintPill(symbol: "arrow.left", label: "エディタ選択")
        keyHintPill(symbol: "command", secondSymbol: "arrow.right", label: "ターミナル選択")
      }
    }
  }

  private func keyHintPill(symbol: String, secondSymbol: String? = nil, label: String) -> some View
  {
    HStack(spacing: 3) {
      Image(systemName: symbol)
        .font(.system(size: 9))
      if let secondSymbol {
        Image(systemName: secondSymbol)
          .font(.system(size: 9))
      }
      Text(label)
        .font(.system(size: 10))
    }
    .foregroundStyle(Color(red: 0.24, green: 0.24, blue: 0.27).opacity(0.8))
    .padding(.horizontal, 8)
    .padding(.vertical, 2)
    .background(.white.opacity(0.8))
    .clipShape(RoundedRectangle(cornerRadius: 4))
    .overlay {
      RoundedRectangle(cornerRadius: 4)
        .strokeBorder(Self.ember.opacity(0.4), lineWidth: 1)
    }
  }

  // MARK: - Update Banner

  private func updateBanner(version: String) -> some View {
    HStack {
      Image(systemName: "arrow.up.circle.fill")
        .foregroundStyle(.blue)
      Text("v\(version) available")
        .font(.system(size: 12))
      Spacer()
      Button {
        viewModel.dismissUpdateBanner(version: version)
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(Color.blue.opacity(0.08))
  }

  // MARK: - Key Event Handling

  /// Enter キーが押された際の処理。
  private func handleEnterKey() {
    if let action = viewModel.handleSpecialKey(.enter, modifiers: []) {
      performAction(action)
    }
  }

  /// 特殊キーアクションを実行する。
  private func performAction(_ action: SpecialKeyAction) {
    switch action {
    case .dismiss:
      viewModel.clearSearch()
      onDismiss?()

    case .execute:
      if let result = viewModel.confirmSelection() {
        onExecute?(result)
      }

    case .copyCalculator:
      viewModel.copyCalculatorResult()

    case .openInTerminal:
      if let result = viewModel.confirmSelection() {
        onOpenInTerminal?(result.path)
      }

    case .showEditorPicker:
      if let result = viewModel.confirmSelection() {
        onShowEditorPicker?(result.path)
      }

    case .showTerminalPicker:
      if let result = viewModel.confirmSelection() {
        onShowTerminalPicker?(result.path)
      }
    }
  }
}

// MARK: - LauncherKeyEventHandler

/// ランチャーのキーイベントをハンドリングするための NSView ラッパー。
///
/// SwiftUI の `onKeyPress` では処理できない矢印キーやモディファイアキーの組み合わせを
/// `keyDown(with:)` オーバーライドで処理する。
public final class LauncherKeyEventHandler: NSView {

  /// キーイベント処理のコールバック
  public var onKeyEvent: ((NSEvent) -> Bool)?

  override public var acceptsFirstResponder: Bool { true }

  override public func keyDown(with event: NSEvent) {
    if let handler = onKeyEvent, handler(event) {
      return
    }
    super.keyDown(with: event)
  }
}

// MARK: - LauncherKeyEventModifier

/// キーイベントハンドラーを SwiftUI ビューに統合する ViewModifier。
struct LauncherKeyEventModifier: ViewModifier {
  let viewModel: LauncherViewModel
  let onAction: (SpecialKeyAction) -> Void

  func body(content: Content) -> some View {
    content.background(
      LauncherKeyEventRepresentable(viewModel: viewModel, onAction: onAction)
        .frame(width: 0, height: 0)
    )
  }
}

/// NSViewRepresentable でキーイベントハンドラーを SwiftUI に橋渡しする。
struct LauncherKeyEventRepresentable: NSViewRepresentable {
  let viewModel: LauncherViewModel
  let onAction: (SpecialKeyAction) -> Void

  func makeNSView(context: Context) -> LauncherKeyEventHandler {
    let view = LauncherKeyEventHandler()
    view.onKeyEvent = { event in
      handleKeyEvent(event)
    }
    return view
  }

  func updateNSView(_ nsView: LauncherKeyEventHandler, context: Context) {
    nsView.onKeyEvent = { event in
      handleKeyEvent(event)
    }
  }

  @MainActor
  private func handleKeyEvent(_ event: NSEvent) -> Bool {
    switch event.keyCode {
    case 126:  // Up arrow
      viewModel.moveSelectionUp()
      HapticService.selectionChanged()
      return true
    case 125:  // Down arrow
      viewModel.moveSelectionDown()
      HapticService.selectionChanged()
      return true
    case 53:  // Escape
      if let action = viewModel.handleSpecialKey(.escape, modifiers: event.modifierFlags) {
        onAction(action)
      }
      return true
    case 124:  // Right arrow
      if let action = viewModel.handleSpecialKey(.right, modifiers: event.modifierFlags) {
        onAction(action)
        return true
      }
      return false
    case 123:  // Left arrow
      if let action = viewModel.handleSpecialKey(.left, modifiers: event.modifierFlags) {
        onAction(action)
        return true
      }
      return false
    default:
      return false
    }
  }
}
