import AppKit
import SwiftUI

// MARK: - SafeHostingView

/// コンストレイント更新の再帰呼び出しを防ぐ `NSHostingView` サブクラス。
///
/// SwiftUI のビューグラフ更新が `updateConstraints()` 内で再帰的に
/// `setNeedsUpdateConstraints:` をトリガーし、AppKit の
/// `_postWindowNeedsUpdateConstraints` が NSException を投げるクラッシュを防止する。
///
/// 対策:
/// 1. `sizingOptions` から自動ウィンドウサイズ管理を除外し、再帰チェーンを断ち切る
/// 2. ウィンドウ非表示時のコンストレイント更新をスキップし、不要なレイアウト計算を回避
@MainActor
final class SafeHostingView<Content: View>: NSHostingView<Content> {

  required init(rootView: Content) {
    super.init(rootView: rootView)
    // ウィンドウサイズ極値の自動更新を無効化（WindowManager が手動管理するため不要）。
    // これにより updateConstraints → minSize → sizeThatFits → graphDidChange →
    // setNeedsUpdateConstraints の再帰チェーンが発生しなくなる。
    sizingOptions = [.intrinsicContentSize]
  }

  @available(*, unavailable)
  @MainActor required dynamic init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func updateConstraints() {
    // ウィンドウが非表示の場合、コンストレイント更新をスキップ。
    // orderOut 後の @Observable 状態変更による不要なレイアウト計算を回避する。
    guard window?.isVisible == true else {
      super.updateConstraints()
      return
    }
    super.updateConstraints()
  }
}

/// メニューバー常駐型ランチャーのフローティングパネル。
///
/// `NSPanel` サブクラスとして実装し、以下の特性を持つ:
/// - ボーダーレス・非アクティベーティングパネル
/// - ステータスバーレベルでフローティング
/// - 全 Spaces に表示・フルスクリーン補助対応
/// - macOS 26 Liquid Glass デザイン対応
@MainActor
public final class LauncherPanel: NSPanel {

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

  // MARK: - SwiftUI Content

  /// SwiftUI ビューをパネルの contentView に設定する。
  ///
  /// `SafeHostingView` でラップして AppKit パネルに埋め込む。
  /// 再帰的コンストレイント更新によるクラッシュを防止する。
  /// - Parameter view: 表示する SwiftUI ビュー
  public func setContentView<V: View>(_ view: V) {
    let hostingView = SafeHostingView(rootView: view)
    contentView = hostingView
  }

  // MARK: - Private

  private func configurePanel() {
    // フローティング設定
    isFloatingPanel = true
    level = .statusBar

    // コレクションビヘイビア
    collectionBehavior = [
      .canJoinAllSpaces,
      .fullScreenAuxiliary,
      .transient,
      .ignoresCycle,
    ]

    // タイトルバー設定
    titlebarAppearsTransparent = true
    titleVisibility = .hidden

    // 移動・外観
    isMovableByWindowBackground = true
    backgroundColor = .clear
    isOpaque = false
    hasShadow = true
  }
}
