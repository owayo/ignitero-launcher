import AppKit
import SwiftUI

// MARK: - EditorPickerState

/// エディタピッカーの選択状態を管理する Observable モデル。
///
/// ショートカットキー・矢印キーによる選択操作と、
/// Enter/Escape による確定・キャンセルのロジックを提供する。
@MainActor
@Observable
public final class EditorPickerState {

  // MARK: - Shortcut Key Mapping

  /// エディタに対応するショートカットキーを返す。
  public static func shortcutKey(for editor: EditorType) -> String {
    switch editor {
    case .windsurf: "w"
    case .cursor: "c"
    case .vscode: "v"
    case .antigravity: "a"
    case .zed: "z"
    }
  }

  /// ショートカットキーに対応するエディタを返す。
  ///
  /// - Parameter key: ショートカットキー文字列
  /// - Returns: 対応する `EditorType`、未知のキーの場合は `nil`
  public static func editor(forShortcutKey key: String) -> EditorType? {
    switch key {
    case "w": .windsurf
    case "c": .cursor
    case "v": .vscode
    case "a": .antigravity
    case "z": .zed
    default: nil
    }
  }

  // MARK: - State

  /// 選択可能なエディタ一覧
  public var availableEditors: [EditorType]

  /// 現在選択中のインデックス（未選択時は `nil`）
  public var selectedIndex: Int?

  /// 確定されたエディタ（Enter で確定後にセットされる）
  public var confirmedEditor: EditorType?

  /// パネルが Escape で閉じられたかどうか
  public var isDismissed: Bool = false

  /// 現在選択中のエディタを返す。
  public var selectedEditor: EditorType? {
    guard let index = selectedIndex,
      availableEditors.indices.contains(index)
    else {
      return nil
    }
    return availableEditors[index]
  }

  // MARK: - Initialization

  /// EditorPickerState を初期化する。
  ///
  /// - Parameter availableEditors: 選択可能なエディタの一覧
  public init(availableEditors: [EditorType]) {
    self.availableEditors = availableEditors
  }

  // MARK: - Key Handling

  /// ショートカットキーを処理する。
  ///
  /// 対応するエディタが `availableEditors` に含まれている場合のみ選択状態を更新する。
  /// - Parameter key: 押されたキー文字列
  /// - Returns: キーが処理された場合は `true`
  @discardableResult
  public func handleKey(_ key: String) -> Bool {
    guard let editor = Self.editor(forShortcutKey: key),
      let index = availableEditors.firstIndex(of: editor)
    else {
      return false
    }
    selectedIndex = index
    return true
  }

  // MARK: - Arrow Key Navigation

  /// 選択を下方向に移動する（リストの末尾で先頭に戻る）。
  public func moveDown() {
    guard !availableEditors.isEmpty else { return }
    if let current = selectedIndex {
      selectedIndex = (current + 1) % availableEditors.count
    } else {
      selectedIndex = 0
    }
  }

  /// 選択を上方向に移動する（リストの先頭で末尾に戻る）。
  public func moveUp() {
    guard !availableEditors.isEmpty else { return }
    if let current = selectedIndex {
      selectedIndex = (current - 1 + availableEditors.count) % availableEditors.count
    } else {
      selectedIndex = availableEditors.count - 1
    }
  }

  // MARK: - Confirm / Dismiss

  /// 現在の選択を確定する。
  ///
  /// 選択されているエディタがある場合のみ `confirmedEditor` をセットする。
  public func confirm() {
    confirmedEditor = selectedEditor
  }

  /// パネルを閉じる（Escape キー操作）。
  ///
  /// 確定せずにパネルを非表示にする。
  public func dismiss() {
    isDismissed = true
  }

  // MARK: - Reset

  /// 状態をリセットして再利用可能にする。
  public func reset() {
    selectedIndex = nil
    confirmedEditor = nil
    isDismissed = false
  }

  /// エディタ一覧を更新してリセットする。
  public func reset(editors: [EditorType]) {
    availableEditors = editors
    reset()
  }
}

// MARK: - EditorPickerContentView

/// エディタピッカーのコンテンツラッパービュー。
///
/// `@Observable` な `EditorPickerState` を監視し、
/// 選択状態の変化に応じて `RadialPickerView` を再描画する。
private struct EditorPickerContentView: View {
  let state: EditorPickerState
  let editors: [EditorInfo]
  let path: String

  var body: some View {
    VStack(spacing: 4) {
      Text(path)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
        .padding(.horizontal, 12)
        .padding(.top, 8)

      RadialPickerView(
        items: RadialPickerItemFactory.editorItems(from: editors),
        mode: .editor,
        highlightedIndex: state.selectedIndex
      )
    }
  }
}

// MARK: - EditorPickerPanel

/// エディタ選択用のフローティングパネル。
///
/// `NSPanel` サブクラスとして実装し、`LauncherPanel` と同様のフローティング設定を持つ。
/// メインランチャーの手前（`statusBar + 1`）に表示され、
/// キーボードショートカットと矢印キーによるエディタ選択を受け付ける。
@MainActor
public final class EditorPickerPanel: NSPanel {

  // MARK: - State

  /// ピッカーの選択状態
  public let pickerState: EditorPickerState

  /// パネルが閉じた時のコールバック
  public var onDismiss: (() -> Void)?

  // MARK: - Initialization

  /// デフォルトの EditorPickerPanel を初期化する。
  ///
  /// 全 `EditorType` を選択候補として使用する。
  public convenience init() {
    self.init(availableEditors: EditorType.allCases)
  }

  /// 指定されたエディタ一覧で EditorPickerPanel を初期化する。
  ///
  /// - Parameter availableEditors: 選択可能なエディタの一覧
  public init(availableEditors: [EditorType]) {
    self.pickerState = EditorPickerState(availableEditors: availableEditors)
    super.init(
      contentRect: .zero,
      styleMask: [.borderless, .nonactivatingPanel, .titled, .fullSizeContentView],
      backing: .buffered,
      defer: true
    )
    configurePanel()
  }

  // MARK: - Key / Main Overrides

  /// パネルがキーウィンドウになれるようにする（キーボード入力受付のため）
  override public var canBecomeKey: Bool { true }

  /// パネルはメインウィンドウにならない（アクセサリパネルのため）
  override public var canBecomeMain: Bool { false }

  // MARK: - Key Event Handling

  /// キーダウンイベントを処理する。
  ///
  /// ショートカットキー、矢印キー、Enter、Escape を処理し、
  /// 対応するアクションを `pickerState` に委譲する。
  override public func keyDown(with event: NSEvent) {
    guard let characters = event.charactersIgnoringModifiers else {
      super.keyDown(with: event)
      return
    }

    switch event.keyCode {
    case 125, 124:  // Down / Right arrow
      pickerState.moveDown()
      HapticService.selectionChanged()
    case 126, 123:  // Up / Left arrow
      pickerState.moveUp()
      HapticService.selectionChanged()
    case 36:  // Enter / Return
      pickerState.confirm()
      if pickerState.confirmedEditor != nil {
        HapticService.confirmed()
        dismissPanel()
      }
    case 53:  // Escape
      pickerState.dismiss()
      dismissPanel()
    default:
      if !pickerState.handleKey(characters) {
        super.keyDown(with: event)
      }
    }
  }

  // MARK: - SwiftUI Content

  /// SwiftUI ビューをパネルの contentView に設定する。
  ///
  /// - Parameter view: 表示する SwiftUI ビュー
  public func setContentView<V: View>(_ view: V) {
    let hostingView = NSHostingView(rootView: view)
    contentView = hostingView
  }

  // MARK: - Show / Dismiss

  /// 指定された矩形の近くにパネルを表示する。
  ///
  /// パネルをランチャーパネルの位置を基準にして配置し、最前面に表示する。
  /// - Parameters:
  ///   - rect: 基準となる矩形（通常はランチャーパネルのフレーム）
  ///   - editors: 利用可能なエディタ情報
  ///   - directoryPath: 開くディレクトリのパス
  public func show(
    relativeTo rect: NSRect, editors: [EditorInfo] = [], directoryPath: String = "",
    defaultIndex: Int? = nil
  ) {
    pickerState.reset(editors: editors.map { $0.id })
    pickerState.selectedIndex = defaultIndex

    // RadialPickerView をコンテンツとして設定
    let view = EditorPickerContentView(
      state: pickerState,
      editors: editors,
      path: directoryPath
    )
    setContentView(view)

    // カーソルがあるスクリーンの中央に配置
    let panelSize: CGFloat = 380
    let mouseLocation = NSEvent.mouseLocation
    let screen =
      NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
      ?? NSScreen.main
    let visibleFrame = screen?.visibleFrame ?? .zero
    let x = visibleFrame.midX - panelSize / 2
    let y = visibleFrame.midY - panelSize / 2

    setFrame(
      NSRect(x: x, y: y, width: panelSize, height: panelSize),
      display: true
    )

    // アプリをアクティブにしてからパネルを最前面に表示
    NSApp.activate(ignoringOtherApps: true)
    makeKeyAndOrderFront(nil)
  }

  /// パネルを非表示にする。
  public func dismissPanel() {
    orderOut(nil)
    onDismiss?()
  }

  // MARK: - Private

  private func configurePanel() {
    // フローティング設定（ランチャーの手前に表示）
    isFloatingPanel = true
    level = NSWindow.Level(NSWindow.Level.statusBar.rawValue + 1)

    // コレクションビヘイビア
    collectionBehavior = [
      .canJoinAllSpaces,
      .fullScreenAuxiliary,
      .transient,
      .ignoresCycle,
    ]

    // ピッカーは明示的に dismiss するため hidesOnDeactivate は無効
    hidesOnDeactivate = false

    // タイトルバー設定
    titlebarAppearsTransparent = true
    titleVisibility = .hidden

    // 移動・外観
    isMovableByWindowBackground = true
    backgroundColor = .clear
    isOpaque = false
  }
}
