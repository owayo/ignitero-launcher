import AppKit
import SwiftUI
import Testing

@testable import IgniteroCore

/// テスト用の SwiftUI ビュー
private struct TestView: View {
  var body: some View {
    Text("Hello")
  }
}

@Suite("LauncherPanel Tests")
struct LauncherPanelTests {

  // MARK: - スタイルマスク

  @Test @MainActor func styleMaskIncludesBorderless() {
    let panel = LauncherPanel()
    #expect(panel.styleMask.contains(.borderless))
  }

  @Test @MainActor func styleMaskIncludesNonactivatingPanel() {
    let panel = LauncherPanel()
    #expect(panel.styleMask.contains(.nonactivatingPanel))
  }

  @Test @MainActor func styleMaskIncludesTitled() {
    let panel = LauncherPanel()
    #expect(panel.styleMask.contains(.titled))
  }

  @Test @MainActor func styleMaskIncludesFullSizeContentView() {
    let panel = LauncherPanel()
    #expect(panel.styleMask.contains(.fullSizeContentView))
  }

  // MARK: - パネルのプロパティ

  @Test @MainActor func isFloatingPanelIsTrue() {
    let panel = LauncherPanel()
    #expect(panel.isFloatingPanel == true)
  }

  @Test @MainActor func levelIsStatusBar() {
    let panel = LauncherPanel()
    #expect(panel.level == .statusBar)
  }

  @Test @MainActor func hidesOnDeactivateIsFalse() {
    let panel = LauncherPanel()
    #expect(panel.hidesOnDeactivate == false)
  }

  @Test @MainActor func hasShadowIsTrue() {
    let panel = LauncherPanel()
    #expect(panel.hasShadow == true)
  }

  // MARK: - コレクション動作

  @Test @MainActor func collectionBehaviorIncludesCanJoinAllSpaces() {
    let panel = LauncherPanel()
    #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
  }

  @Test @MainActor func collectionBehaviorIncludesFullScreenAuxiliary() {
    let panel = LauncherPanel()
    #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
  }

  @Test @MainActor func collectionBehaviorIncludesTransient() {
    let panel = LauncherPanel()
    #expect(panel.collectionBehavior.contains(.transient))
  }

  @Test @MainActor func collectionBehaviorIncludesIgnoresCycle() {
    let panel = LauncherPanel()
    #expect(panel.collectionBehavior.contains(.ignoresCycle))
  }

  // MARK: - キー／メイン動作

  @Test @MainActor func canBecomeKeyReturnsTrue() {
    let panel = LauncherPanel()
    #expect(panel.canBecomeKey == true)
  }

  @Test @MainActor func canBecomeMainReturnsFalse() {
    let panel = LauncherPanel()
    #expect(panel.canBecomeMain == false)
  }

  // MARK: - タイトルバー設定

  @Test @MainActor func titlebarAppearsTransparentIsTrue() {
    let panel = LauncherPanel()
    #expect(panel.titlebarAppearsTransparent == true)
  }

  @Test @MainActor func titleVisibilityIsHidden() {
    let panel = LauncherPanel()
    #expect(panel.titleVisibility == .hidden)
  }

  // MARK: - 移動と外観

  @Test @MainActor func isMovableByWindowBackgroundIsTrue() {
    let panel = LauncherPanel()
    #expect(panel.isMovableByWindowBackground == true)
  }

  @Test @MainActor func backgroundColorIsClear() {
    let panel = LauncherPanel()
    #expect(panel.backgroundColor == .clear)
  }

  @Test @MainActor func isOpaqueIsFalse() {
    let panel = LauncherPanel()
    #expect(panel.isOpaque == false)
  }

  // MARK: - SwiftUIコンテンツ View

  @Test @MainActor func setContentViewWrapsSwiftUIInNSHostingView() {
    let panel = LauncherPanel()
    panel.setContentView(TestView())
    #expect(panel.contentView is NSHostingView<TestView>)
  }

  // MARK: - SafeHostingViewの再入レイアウトクラッシュ防止
  //
  // 過去に macOS 26 で発生した `-[NSWindow _postWindowNeedsUpdateConstraints]`
  // NSException (SIGABRT) を再発させないための回帰テスト群。
  // 発生経路: `NSHostingView.windowDidLayout` → `updateAnimatedWindowSize` →
  // 呼び出し経路: `_setFrameCommon` → `setFrameSize` KVO → `invalidateSafeAreaInsets` →
  // SwiftUI ViewGraph 再計算 → `setNeedsUpdateConstraints(true)` の再要求。
  // 対策: SafeHostingView から SwiftUI → AppKit のサイズフィードバックを完全に切る。

  @Test @MainActor func safeHostingViewDisablesSwiftUISizingFeedback() {
    let hostingView = SafeHostingView(rootView: TestView())

    #expect(hostingView.sizingOptions.isEmpty)
    #expect(hostingView.intrinsicContentSize.width == NSView.noIntrinsicMetric)
    #expect(hostingView.intrinsicContentSize.height == NSView.noIntrinsicMetric)
    #expect(hostingView.translatesAutoresizingMaskIntoConstraints)
    #expect(hostingView.autoresizingMask.contains(.width))
    #expect(hostingView.autoresizingMask.contains(.height))
  }

  @Test @MainActor func safeHostingViewContentSizeDoesNotResizePanel() {
    let panel = LauncherPanel()
    let hostingView = SafeHostingView(
      rootView: AnyView(Color.clear.frame(width: 100, height: 100))
    )
    panel.contentView = hostingView
    panel.setFrame(NSRect(x: 100, y: 100, width: 680, height: 300), display: false)
    panel.contentMinSize = NSSize(width: 50, height: 50)
    panel.contentMaxSize = NSSize(width: 2_000, height: 2_000)

    let expectedFrame = panel.frame
    let expectedMinSize = panel.contentMinSize
    let expectedMaxSize = panel.contentMaxSize

    hostingView.rootView = AnyView(Color.clear.frame(width: 1_500, height: 1_500))
    panel.layoutIfNeeded()

    #expect(panel.frame == expectedFrame)
    #expect(panel.contentMinSize == expectedMinSize)
    #expect(panel.contentMaxSize == expectedMaxSize)
  }

  @Test @MainActor func safeHostingViewSurvivesInterleavedContentAndFrameChanges() {
    let panel = LauncherPanel()
    let hostingView = SafeHostingView(rootView: AnyView(EmptyView()))
    panel.contentView = hostingView

    for index in 0..<120 {
      let contentHeight: CGFloat = index.isMultiple(of: 2) ? 80 : 900
      let panelHeight: CGFloat =
        WindowManager.minHeight + CGFloat(index % 8) * WindowManager.rowHeight

      hostingView.rootView = AnyView(
        Color.clear.frame(width: WindowManager.width, height: contentHeight)
      )
      panel.setFrame(
        NSRect(x: 100, y: 800 - panelHeight, width: WindowManager.width, height: panelHeight),
        display: true,
        animate: false
      )
      panel.layoutIfNeeded()
    }

    // NSException で SIGABRT する経路であればテストプロセスが abort する。
    // ここまで到達したこと自体が合格条件。frame は AppKit が維持しているはず。
    #expect(panel.frame.width == WindowManager.width)
  }
}
