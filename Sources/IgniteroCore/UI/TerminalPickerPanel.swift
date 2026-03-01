import AppKit
import SwiftUI

// MARK: - TerminalPickerState

/// ターミナルピッカーの選択状態を管理する。
///
/// `@Observable` で SwiftUI バインディングに対応し、
/// キーボードナビゲーションによるターミナル選択ロジックを提供する。
@Observable
public final class TerminalPickerState {

  /// 表示中のターミナル一覧
  public var terminals: [TerminalInfo] = []

  /// 現在ハイライトされているインデックス
  public var highlightedIndex: Int = 0

  /// 確定されたターミナル（Enter 押下後に設定）
  public var selectedTerminal: TerminalType?

  public init() {}

  /// 状態をリセットし、ターミナル一覧を設定する。
  ///
  /// ハイライトを先頭に戻し、選択をクリアする。
  /// - Parameter terminals: 表示するターミナル一覧
  public func reset(terminals: [TerminalInfo]) {
    self.terminals = terminals
    self.highlightedIndex = 0
    self.selectedTerminal = nil
  }

  /// ハイライトを下に移動する（末尾で先頭にラップ）。
  public func moveDown() {
    guard !terminals.isEmpty else { return }
    highlightedIndex = (highlightedIndex + 1) % terminals.count
  }

  /// ハイライトを上に移動する（先頭で末尾にラップ）。
  public func moveUp() {
    guard !terminals.isEmpty else { return }
    highlightedIndex = (highlightedIndex - 1 + terminals.count) % terminals.count
  }

  /// 現在ハイライトされているターミナルを選択確定する。
  public func confirmSelection() {
    guard !terminals.isEmpty, highlightedIndex < terminals.count else { return }
    selectedTerminal = terminals[highlightedIndex].id
  }
}

// MARK: - TerminalPickerContentView

/// ターミナルピッカーのコンテンツラッパービュー。
///
/// `@Observable` な `TerminalPickerState` を監視し、
/// 選択状態の変化に応じて `RadialPickerView` を再描画する。
private struct TerminalPickerContentView: View {
  let state: TerminalPickerState

  var body: some View {
    RadialPickerView(
      items: RadialPickerItemFactory.terminalItems(from: state.terminals),
      mode: .terminal,
      highlightedIndex: state.highlightedIndex
    )
  }
}

// MARK: - TerminalPickerPanel

/// ターミナル選択用のフローティングパネル。
///
/// `NSPanel` サブクラスとして実装し、メインランチャーの手前にフローティング表示する。
/// 矢印キーと Enter キーによる選択、Escape キーによる閉じるをサポートする。
@MainActor
public final class TerminalPickerPanel: NSPanel {

  /// ターミナル選択の状態管理
  public let state = TerminalPickerState()

  /// ターミナル選択確定時のコールバック
  public var onSelect: ((TerminalType) -> Void)?

  /// パネル閉じた時のコールバック
  public var onDismiss: (() -> Void)?

  // MARK: - Initialization

  public convenience init() {
    self.init(
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

  // MARK: - Key Handling

  override public func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 125, 124:  // Down / Right arrow
      state.moveDown()
      HapticService.selectionChanged()
    case 126, 123:  // Up / Left arrow
      state.moveUp()
      HapticService.selectionChanged()
    case 36:  // Enter / Return
      state.confirmSelection()
      if let terminal = state.selectedTerminal {
        HapticService.confirmed()
        onSelect?(terminal)
      }
      dismiss()
    case 53:  // Escape
      dismiss()
    default:
      super.keyDown(with: event)
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

  /// パネルを指定された矩形の近くに表示する。
  ///
  /// ターミナル一覧を読み込み、パネルを最前面に配置する。
  /// - Parameters:
  ///   - rect: 基準となる矩形（ランチャーウィンドウのフレームなど）
  ///   - terminals: 表示するターミナル一覧
  public func show(relativeTo rect: NSRect, terminals: [TerminalInfo] = [], defaultIndex: Int = 0) {
    state.reset(terminals: terminals)
    state.highlightedIndex = defaultIndex

    // RadialPickerView をコンテンツとして設定
    let view = TerminalPickerContentView(state: state)
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

  /// パネルを閉じる。
  ///
  /// 選択が確定されていない場合、`onDismiss` コールバックを呼び出す。
  public func dismiss() {
    orderOut(nil)
    onDismiss?()
  }

  // MARK: - Private

  private func configurePanel() {
    // フローティング設定（ランチャーより上のレベル）
    isFloatingPanel = true
    level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)

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
