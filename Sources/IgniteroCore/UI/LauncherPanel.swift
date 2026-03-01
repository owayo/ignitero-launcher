import AppKit
import SwiftUI

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
  /// `NSHostingView` でラップして AppKit パネルに埋め込む。
  /// - Parameter view: 表示する SwiftUI ビュー
  public func setContentView<V: View>(_ view: V) {
    let hostingView = NSHostingView(rootView: view)
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
