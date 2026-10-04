import AppKit
import QuartzCore
import SwiftUI
import Testing

@testable import IgniteroCore

/// テスト用の SwiftUI ビュー
private struct TestView: View {
  var body: some View {
    Text("Hello")
  }
}

/// 同期 layoutIfNeeded だけでは NSHostingView の windowDidLayout 経路を検証できない。
/// 表示した実際の LauncherView を更新し、非同期の表示サイクルまで通す。
@Suite("LauncherPanel Display Cycle", .serialized)
struct LauncherPanelDisplayCycleTests {
  @MainActor
  private final class ResizeRecorder: NSObject, NSWindowDelegate {
    var heights: [CGFloat] = []

    func windowDidResize(_ notification: Notification) {
      if let window = notification.object as? NSWindow {
        heights.append(window.frame.height)
      }
    }
  }

  @Test @MainActor func animatedSearchChangesKeepWindowFrameUnderAppKitControl() async throws {
    let panel = LauncherPanel()
    let recorder = ResizeRecorder()
    panel.delegate = recorder
    let manager = WindowManager()
    manager.launcherPanel = panel
    let model = LauncherViewModel()
    model.apps = (0..<80).map { index in
      AppItem(name: "Example \(index)", path: "/Applications/Example\(index).app")
    }
    panel.setContentView(
      LauncherView(
        viewModel: model,
        onResultsCountChanged: { [weak manager] in manager?.resizeForResults(count: $0) }
      )
    )
    panel.setFrame(
      NSRect(x: 100, y: 100, width: WindowManager.width, height: WindowManager.minHeight),
      display: false
    )
    panel.orderFront(nil)
    defer {
      panel.orderOut(nil)
      panel.close()
    }

    for index in 0..<40 {
      model.searchQuery = "Example"
      model.updateSearch()
      manager.resizeForResults(count: model.searchResults.count)
      try await flushDisplayCycle(panel)

      model.selectedIndex = min(20, model.searchResults.count - 1)
      try await flushDisplayCycle(panel)

      // scrollTo のアニメーション中に結果数とウィンドウの高さを変える。
      withAnimation(.easeInOut(duration: 0.1)) {
        model.searchQuery = index.isMultiple(of: 2) ? "no-matching-application" : "Example 1"
        model.isScanning = index.isMultiple(of: 3)
        model.updateBannerVersion = index.isMultiple(of: 4) ? "99.0.0" : nil
        model.updateSearch()
      }
      manager.resizeForResults(count: model.searchResults.count)
      try await flushDisplayCycle(panel)

      #expect(panel.frame.width == WindowManager.width)
      #expect(panel.frame.height == manager.currentHeight)
    }

    try await Task.sleep(for: .milliseconds(200))
    #expect(panel.frame.height == manager.currentHeight)
    #expect(!recorder.heights.isEmpty)
    #expect(recorder.heights.allSatisfy { $0 <= WindowManager.maxHeight })
  }

  @MainActor
  private func flushDisplayCycle(_ panel: NSPanel) async throws {
    panel.layoutIfNeeded()
    CATransaction.flush()
    try await Task.sleep(for: .milliseconds(20))
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

  @Test @MainActor func setContentViewEmbedsSwiftUIInAppKitContainer() throws {
    let panel = LauncherPanel()
    panel.setContentView(TestView())
    let container = try #require(panel.contentView)
    let hostingView = try #require(container.subviews.first as? SafeHostingView<TestView>)
    #expect(hostingView.window === panel)
    #expect(hostingView.sizingOptions.isEmpty)
  }

  // MARK: - SafeHostingViewの再入レイアウトクラッシュ防止
  //
  // 過去に macOS 26 で発生した `-[NSWindow _postWindowNeedsUpdateConstraints]`
  // NSException (SIGABRT) を再発させないための回帰テスト群。
  // 発生経路: `NSHostingView.windowDidLayout` → `updateAnimatedWindowSize` →
  // 呼び出し経路: `_setFrameCommon` → `setFrameSize` KVO → `invalidateSafeAreaInsets` →
  // SwiftUI ViewGraph 再計算 → `setNeedsUpdateConstraints(true)` の再要求。
  // 対策: サイズ制約を抑制し、AppKit コンテナの子として hosting view を配置する。

  @Test @MainActor func safeHostingViewDisablesSwiftUISizingFeedback() {
    let hostingView = SafeHostingView(rootView: TestView())

    #expect(hostingView.sizingOptions.isEmpty)
    #expect(hostingView.intrinsicContentSize.width == NSView.noIntrinsicMetric)
    #expect(hostingView.intrinsicContentSize.height == NSView.noIntrinsicMetric)
    #expect(hostingView.translatesAutoresizingMaskIntoConstraints)
    #expect(hostingView.autoresizingMask.contains(.width))
    #expect(hostingView.autoresizingMask.contains(.height))
  }

  @Test @MainActor func safeHostingViewContentSizeDoesNotResizePanel() throws {
    let panel = LauncherPanel()
    let container = SafeHostingView.makeContainer(
      rootView: AnyView(Color.clear.frame(width: 100, height: 100))
    )
    let hostingView = try #require(container.subviews.first as? SafeHostingView<AnyView>)
    panel.contentView = container
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

  @Test @MainActor func visualEffectContainerUsesAutoresizing() throws {
    let panel = LauncherPanel()
    let visualEffect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 380, height: 480))
    visualEffect.autoresizesSubviews = false
    let container = SafeHostingView.makeContainer(rootView: TestView(), in: visualEffect)
    let hostingView = try #require(container.subviews.first as? SafeHostingView<TestView>)
    panel.contentView = container
    defer { panel.close() }

    #expect(container === visualEffect)
    #expect(container.autoresizesSubviews)
    #expect(hostingView.translatesAutoresizingMaskIntoConstraints)
    #expect(hostingView.autoresizingMask == [.width, .height])
    for height: CGFloat in [108, 480, 300] {
      panel.setFrame(NSRect(x: 100, y: 100, width: 680, height: height), display: false)
      panel.layoutIfNeeded()
      #expect(hostingView.frame == container.bounds)
      #expect(hostingView.window === panel)
    }
  }

  @Test @MainActor func safeHostingViewSurvivesInterleavedContentAndFrameChanges() throws {
    let panel = LauncherPanel()
    let container = SafeHostingView.makeContainer(rootView: AnyView(EmptyView()))
    let hostingView = try #require(container.subviews.first as? SafeHostingView<AnyView>)
    panel.contentView = container

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
      #expect(hostingView.frame == container.bounds)
    }

    // NSException で SIGABRT する経路であればテストプロセスが abort する。
    // ここまで到達したこと自体が合格条件。frame は AppKit が維持しているはず。
    #expect(panel.frame.width == WindowManager.width)
  }
}
