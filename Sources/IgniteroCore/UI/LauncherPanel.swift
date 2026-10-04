import AppKit
import SwiftUI

// MARK: - SafeHostingView関連

/// SwiftUI 内容を AppKit パネルへ埋め込む `NSHostingView` サブクラス。
///
/// SwiftUI 内容のサイズに基づく Auto Layout 制約を抑制する。
///
/// `NSWindow.contentView` への直接設定は避け、`makeContainer(rootView:in:)` で
/// AppKit コンテナの子ビューとして埋め込むこと。
/// macOS 27 では `sizingOptions = []` でも、contentView に直接置くと
/// `windowDidLayout` → `updateAnimatedWindowSize` がウィンドウをリサイズし、
/// ScrollView の KVO → `setNeedsLayout` が再入して SIGABRT することがある。
///
/// サイズ制約を抑制する設定:
/// 1. `sizingOptions = []` — SwiftUI の min/ideal/max を AppKit/NSWindow に伝えない
/// 2. `intrinsicContentSize` は `NSView.noIntrinsicMetric` — Auto Layout に intrinsic size を渡さない
/// 3. 自動サイズ変更: `translatesAutoresizingMaskIntoConstraints = true` + `autoresizingMask = [.width, .height]` —
///    frame は AppKit の autoresizing で駆動し、SwiftUI 内容に基づく制約を作らない
///
/// ウィンドウフレームは AppKit 側で管理し、hosting view はコンテナの bounds に追従する。
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

  /// ウィンドウの contentView に設定するための AppKit コンテナを作る。
  /// hosting view 自身を contentView にせず、SwiftUI とウィンドウのサイズ管理を分離する。
  static func makeContainer(rootView: Content, in container: NSView? = nil) -> NSView {
    let container = container ?? NSView(frame: .zero)
    container.autoresizesSubviews = true
    let hostingView = SafeHostingView(rootView: rootView)
    hostingView.frame = container.bounds
    container.addSubview(hostingView)
    return container
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
  /// AppKit コンテナの子として `SafeHostingView` を埋め込む。
  /// 再帰的コンストレイント更新によるクラッシュを防止する。
  /// - Parameter view: 表示する SwiftUI ビュー
  public func setContentView<V: View>(_ view: V) {
    contentView = SafeHostingView.makeContainer(rootView: view)
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
