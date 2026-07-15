import AppKit
import SwiftUI

// MARK: - SafeHostingView関連

/// SwiftUI 内容を AppKit パネルへ埋め込む `NSHostingView` サブクラス。
///
/// SwiftUI 側からウィンドウ／AppKit へのサイズフィードバックを完全に切り、
/// ウィンドウフレームの所有権を `WindowManager` に一本化する。これにより
/// macOS 15/26 で発生する再入的レイアウトクラッシュを防ぐ。
///
/// 具体的な症状: `-[NSWindow layoutIfNeeded]` 実行中の `windowDidLayout` 通知で
/// `NSHostingView.updateAnimatedWindowSize(_:)` が発火し、
/// `setFrameSize` の KVO → `invalidateSafeAreaInsets` → SwiftUI ViewGraph 再計算 →
/// `setNeedsUpdateConstraints(true)` の再要求チェーンが起き、
/// `-[NSWindow _postWindowNeedsUpdateConstraints]` が NSException を投げて SIGABRT。
///
/// 対策 (Apple 公開 API のみ、Codex/OpenAI との相談で確定):
/// 1. `sizingOptions = []` — SwiftUI の min/ideal/max を AppKit/NSWindow に伝えない
/// 2. `intrinsicContentSize` は `NSView.noIntrinsicMetric` — Auto Layout に intrinsic size を渡さない
/// 3. 自動サイズ変更: `translatesAutoresizingMaskIntoConstraints = true` + `autoresizingMask = [.width, .height]` —
///    frame は AppKit の autoresizing で駆動し、Auto Layout 経路を回避
///
/// `.intrinsicContentSize` 単独では今回のクラッシュ経路 (`updateAnimatedWindowSize`) は塞げない。
@MainActor
final class SafeHostingView<Content: View>: NSHostingView<Content> {

  required init(rootView: Content) {
    super.init(rootView: rootView)
    sizingOptions = []
    translatesAutoresizingMaskIntoConstraints = true
    autoresizingMask = [.width, .height]
  }

  @available(*, unavailable)
  @MainActor required dynamic init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var intrinsicContentSize: NSSize {
    NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
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

  // MARK: - 初期化

  public convenience init() {
    self.init(
      contentRect: .zero,
      styleMask: [.borderless, .nonactivatingPanel, .titled, .fullSizeContentView],
      backing: .buffered,
      defer: true
    )
    configurePanel()
  }

  // MARK: - キー／メイン状態のオーバーライド

  /// パネルがキーウィンドウになれるようにする（キーボード入力受付のため）
  override public var canBecomeKey: Bool { true }

  /// パネルはメインウィンドウにならない（アクセサリパネルのため）
  override public var canBecomeMain: Bool { false }

  // MARK: - SwiftUIコンテンツ

  /// SwiftUI ビューをパネルの contentView に設定する。
  ///
  /// `SafeHostingView` でラップして AppKit パネルに埋め込む。
  /// 再帰的コンストレイント更新によるクラッシュを防止する。
  /// - Parameter view: 表示する SwiftUI ビュー
  public func setContentView<V: View>(_ view: V) {
    let hostingView = SafeHostingView(rootView: view)
    contentView = hostingView
  }

  // MARK: - 非公開

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
