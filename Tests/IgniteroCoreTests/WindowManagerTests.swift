import AppKit
import Foundation
import Testing

@testable import IgniteroCore

// MARK: - SwiftUI 更新中の同期リサイズ防止

@Suite("WindowManager Deferred Resize", .serialized)
@MainActor
struct WindowManagerDeferredResizeTests {
  @MainActor
  private final class ManualScheduler {
    var operations: [@MainActor @Sendable () -> Void] = []

    func schedule(_ operation: @escaping @MainActor @Sendable () -> Void) {
      operations.append(operation)
    }

    func run() {
      let pending = operations
      operations.removeAll()
      for operation in pending { operation() }
    }
  }

  private final class RecordingPanel: NSPanel {
    var frameRequests: [(frame: NSRect, display: Bool, animate: Bool)] = []

    init() {
      super.init(
        contentRect: NSRect(x: 100, y: 100, width: 680, height: WindowManager.minHeight),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: true
      )
      frameRequests.removeAll()
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool, animate animateFlag: Bool) {
      frameRequests.append((frameRect, flag, animateFlag))
      super.setFrame(frameRect, display: flag, animate: animateFlag)
    }
  }

  @Test func consecutiveRequestsDeferAndApplyOnlyLatestHeight() {
    let scheduler = ManualScheduler()
    let manager = WindowManager(scheduleResize: scheduler.schedule)
    let panel = RecordingPanel()
    manager.launcherPanel = panel
    defer { panel.close() }
    let originalFrame = panel.frame

    manager.resizeForResults(count: 1)
    manager.resizeForResults(count: 0)
    manager.resizeForResults(count: 80)

    #expect(manager.currentHeight == WindowManager.maxHeight)
    #expect(panel.frame == originalFrame)
    #expect(panel.frameRequests.isEmpty)
    #expect(scheduler.operations.count == 1)

    scheduler.run()
    #expect(panel.frame.height == WindowManager.maxHeight)
    #expect(panel.frameRequests.count == 1)
    #expect(panel.frameRequests.allSatisfy { !$0.display && !$0.animate })
  }

  @Test func unchangedHeightSkipsResizeButRepairsAnOutdatedFrame() {
    let scheduler = ManualScheduler()
    let manager = WindowManager(scheduleResize: scheduler.schedule)
    let panel = RecordingPanel()
    manager.launcherPanel = panel
    defer { panel.close() }

    manager.resizeForResults(count: 0)
    scheduler.run()
    #expect(panel.frameRequests.isEmpty)

    panel.setFrame(NSRect(x: 100, y: 100, width: 680, height: 500), display: false, animate: false)
    panel.frameRequests.removeAll()
    manager.resizeForResults(count: 0)
    scheduler.run()
    #expect(panel.frame.height == WindowManager.minHeight)
    #expect(panel.frameRequests.count == 1)
  }

  @Test func resizeKeepsUpperEdgeAtThePositionUsedWhenApplying() {
    let scheduler = ManualScheduler()
    let manager = WindowManager(scheduleResize: scheduler.schedule)
    let panel = RecordingPanel()
    manager.launcherPanel = panel
    defer { panel.close() }

    manager.resizeForResults(count: 80)
    panel.setFrameOrigin(NSPoint(x: 250, y: 400))
    let movedFrame = panel.frame
    scheduler.run()

    #expect(panel.frame.maxY == movedFrame.maxY)
    #expect(panel.frame.minX == movedFrame.minX)
    #expect(panel.frame.width == movedFrame.width)
    #expect(panel.frame.height == WindowManager.maxHeight)
  }

  @Test func showAppliesLatestHeightBeforeCenteringAndQueuedResizeDoesNothing() {
    let scheduler = ManualScheduler()
    let manager = WindowManager(scheduleResize: scheduler.schedule)
    let panel = RecordingPanel()
    manager.launcherPanel = panel
    manager.onShowLauncher = { [weak manager] in manager?.resizeForResults(count: 2) }
    defer {
      manager.hideLauncher()
      panel.close()
    }

    manager.resizeForResults(count: 80)
    manager.showLauncher()
    #expect(panel.frame.height == manager.heightForResults(count: 2))
    if let screen =
      NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
      ?? NSScreen.main
    {
      let visible = screen.visibleFrame
      #expect(abs(panel.frame.midY - (visible.maxY - visible.height * 0.25)) < 1)
    }

    let shownFrame = panel.frame
    let requestCount = panel.frameRequests.count
    scheduler.run()
    #expect(panel.frame == shownFrame)
    #expect(panel.frameRequests.count == requestCount)
  }

  @Test func hideDiscardsPendingResizeAndNextShowUsesDesiredHeight() {
    let scheduler = ManualScheduler()
    let manager = WindowManager(scheduleResize: scheduler.schedule)
    let panel = RecordingPanel()
    manager.launcherPanel = panel
    defer {
      manager.hideLauncher()
      panel.close()
    }

    manager.resizeForResults(count: 80)
    manager.hideLauncher()
    scheduler.run()
    #expect(panel.frameRequests.isEmpty)
    #expect(manager.currentHeight == WindowManager.maxHeight)

    manager.showLauncher()
    #expect(panel.frame.height == WindowManager.maxHeight)
  }

  @Test func newRequestAfterShowUsesTheAlreadyScheduledOperation() {
    let scheduler = ManualScheduler()
    let manager = WindowManager(scheduleResize: scheduler.schedule)
    let panel = RecordingPanel()
    manager.launcherPanel = panel
    defer {
      manager.hideLauncher()
      panel.close()
    }

    manager.resizeForResults(count: 80)
    manager.showLauncher()
    manager.resizeForResults(count: 0)
    #expect(scheduler.operations.count == 1)
    #expect(panel.frame.height == WindowManager.maxHeight)
    scheduler.run()
    #expect(panel.frame.height == WindowManager.minHeight)
  }

  @Test func queuedResizeDoesNotRetainTheManager() {
    let scheduler = ManualScheduler()
    let panel = RecordingPanel()
    defer { panel.close() }
    var manager: WindowManager? = WindowManager(scheduleResize: scheduler.schedule)
    manager?.launcherPanel = panel
    manager?.resizeForResults(count: 80)
    weak var releasedManager: WindowManager?
    releasedManager = manager
    manager = nil

    #expect(releasedManager == nil)
    scheduler.run()
    #expect(panel.frameRequests.isEmpty)
  }
}

// MARK: - WindowManager 初期状態 テスト

@Suite("WindowManager Initial State")
struct WindowManagerInitialStateTests {

  @MainActor
  @Test func initialLauncherVisibilityIsFalse() {
    let manager = WindowManager()
    #expect(manager.isLauncherVisible == false)
  }

  @MainActor
  @Test func initialPickerVisibilityIsFalse() {
    let manager = WindowManager()
    #expect(manager.isPickerVisible == false)
  }

  @MainActor
  @Test func initialPanelIsNil() {
    let manager = WindowManager()
    #expect(manager.launcherPanel == nil)
  }
}

// MARK: - WindowManager Toggle テスト

@Suite("WindowManager Toggle")
struct WindowManagerToggleTests {

  @MainActor
  @Test func toggleLauncherFromHiddenToVisible() {
    let manager = WindowManager()
    #expect(manager.isLauncherVisible == false)
    manager.toggleLauncher()
    #expect(manager.isLauncherVisible == true)
  }

  @MainActor
  @Test func toggleLauncherFromVisibleToHidden() {
    let manager = WindowManager()
    manager.toggleLauncher()  // 表示
    #expect(manager.isLauncherVisible == true)
    manager.toggleLauncher()  // 非表示
    #expect(manager.isLauncherVisible == false)
  }

  @MainActor
  @Test func toggleLauncherMultipleTimes() {
    let manager = WindowManager()
    for i in 0..<6 {
      manager.toggleLauncher()
      let expectedVisible = (i % 2 == 0)  // 0ならtrue、1ならfalse、2ならtrue…
      #expect(manager.isLauncherVisible == expectedVisible)
    }
  }
}

// MARK: - WindowManager表示／非表示のテスト

@Suite("WindowManager Show/Hide")
struct WindowManagerShowHideTests {

  @MainActor
  @Test func showLauncherSetsVisibleTrue() {
    let manager = WindowManager()
    manager.showLauncher()
    #expect(manager.isLauncherVisible == true)
  }

  @MainActor
  @Test func showLauncherIdempotent() {
    let manager = WindowManager()
    manager.showLauncher()
    manager.showLauncher()
    #expect(manager.isLauncherVisible == true)
  }

  @MainActor
  @Test func hideLauncherSetsVisibleFalse() {
    let manager = WindowManager()
    manager.showLauncher()
    #expect(manager.isLauncherVisible == true)
    manager.hideLauncher()
    #expect(manager.isLauncherVisible == false)
  }

  @MainActor
  @Test func hideLauncherWhenAlreadyHiddenStaysHidden() {
    let manager = WindowManager()
    manager.hideLauncher()
    #expect(manager.isLauncherVisible == false)
  }

  @MainActor
  @Test func hideLauncherWorksEvenWhenPickerVisible() {
    let manager = WindowManager()
    manager.showLauncher()
    manager.showPicker()
    #expect(manager.isPickerVisible == true)
    manager.hideLauncher()
    // ピッカー表示中でもランチャーは隠せる（Tauri と同じフロー）
    #expect(manager.isLauncherVisible == false)
  }

  @MainActor
  @Test func hideLauncherAfterPickerHidden() {
    let manager = WindowManager()
    manager.showLauncher()
    manager.showPicker()
    manager.hidePicker()
    manager.hideLauncher()
    #expect(manager.isLauncherVisible == false)
  }

  @MainActor
  @Test func toggleLauncherClosesPickerAndShowsLauncher() {
    let manager = WindowManager()
    var pickersClosed = false
    manager.onCloseAllPickers = { pickersClosed = true }
    manager.showLauncher()
    manager.showPicker()
    manager.toggleLauncher()
    // ピッカー表示中のトグルでピッカーを閉じてランチャーを表示
    #expect(pickersClosed == true)
    #expect(manager.isPickerVisible == false)
    #expect(manager.isLauncherVisible == true)
  }
}

// MARK: - WindowManager Picker テスト

@Suite("WindowManager Picker Control")
struct WindowManagerPickerTests {

  @MainActor
  @Test func showPickerSetsVisibleTrue() {
    let manager = WindowManager()
    manager.showPicker()
    #expect(manager.isPickerVisible == true)
  }

  @MainActor
  @Test func hidePickerSetsVisibleFalse() {
    let manager = WindowManager()
    manager.showPicker()
    manager.hidePicker()
    #expect(manager.isPickerVisible == false)
  }

  @MainActor
  @Test func showPickerIdempotent() {
    let manager = WindowManager()
    manager.showPicker()
    manager.showPicker()
    #expect(manager.isPickerVisible == true)
  }

  @MainActor
  @Test func hidePickerIdempotent() {
    let manager = WindowManager()
    manager.showPicker()
    manager.hidePicker()
    manager.hidePicker()
    #expect(manager.isPickerVisible == false)
  }
}

// MARK: - WindowManager Resize テスト

@Suite("WindowManager Resize for Results")
struct WindowManagerResizeTests {

  @MainActor
  @Test func resizeForZeroResultsReturnsMinHeight() {
    let manager = WindowManager()
    let height = manager.heightForResults(count: 0)
    #expect(height == WindowManager.minHeight)
  }

  @MainActor
  @Test func resizeForOneResult() {
    let manager = WindowManager()
    let height = manager.heightForResults(count: 1)
    let expected = WindowManager.minHeight + WindowManager.rowHeight
    #expect(height == expected)
  }

  @MainActor
  @Test func resizeForFiveResults() {
    let manager = WindowManager()
    let height = manager.heightForResults(count: 5)
    let expected = WindowManager.minHeight + 5 * WindowManager.rowHeight
    #expect(height == expected)
  }

  @MainActor
  @Test func resizeForSevenResultsNotClamped() {
    let manager = WindowManager()
    let height = manager.heightForResults(count: 7)
    // 108 + 7*52 = 472で上限500未満
    let expected = WindowManager.minHeight + 7 * WindowManager.rowHeight
    #expect(height == expected)
    #expect(height < WindowManager.maxHeight)
  }

  @MainActor
  @Test func resizeForEightResultsClamps() {
    let manager = WindowManager()
    let height = manager.heightForResults(count: 8)
    // 108 + 8*52 = 524を500へ制限
    #expect(height == WindowManager.maxHeight)
  }

  @MainActor
  @Test func resizeForTenResults() {
    let manager = WindowManager()
    let height = manager.heightForResults(count: 10)
    // 108 + 10*52 = 628を上限500へ制限
    #expect(height == WindowManager.maxHeight)
  }

  @MainActor
  @Test func resizeForElevenResultsClampsToMaxHeight() {
    let manager = WindowManager()
    let height = manager.heightForResults(count: 11)
    // 108 + 11*52 = 680を500へ制限
    #expect(height == WindowManager.maxHeight)
  }

  @MainActor
  @Test func resizeForTwentyResultsClampsToMaxHeight() {
    let manager = WindowManager()
    let height = manager.heightForResults(count: 20)
    #expect(height == WindowManager.maxHeight)
  }

  @MainActor
  @Test func resizeForNegativeCountTreatedAsZero() {
    let manager = WindowManager()
    let height = manager.heightForResults(count: -1)
    #expect(height == WindowManager.minHeight)
  }

  @MainActor
  @Test func resizeForResultsUpdatesCurrentHeight() {
    let manager = WindowManager()
    manager.resizeForResults(count: 5)
    let expected = WindowManager.minHeight + 5 * WindowManager.rowHeight
    #expect(manager.currentHeight == expected)
  }

  @MainActor
  @Test func constantValues() {
    #expect(WindowManager.minHeight == 108)
    #expect(WindowManager.maxHeight == 500)
    #expect(WindowManager.rowHeight == 52)
    #expect(WindowManager.width == 680)
  }
}

// MARK: - WindowManagerサイズ変更の境界値テスト

@Suite("WindowManager Resize Edge Cases")
struct WindowManagerResizeEdgeCaseTests {

  @MainActor
  @Test func resizeForVeryLargeCountClampsToMax() {
    let manager = WindowManager()
    let height = manager.heightForResults(count: 10000)
    #expect(height == WindowManager.maxHeight)
  }

  @MainActor
  @Test func resizeForZeroUpdatesCurrentHeight() {
    let manager = WindowManager()
    manager.resizeForResults(count: 5)
    #expect(manager.currentHeight > WindowManager.minHeight)
    manager.resizeForResults(count: 0)
    #expect(manager.currentHeight == WindowManager.minHeight)
  }
}

// MARK: - WindowManager コールバック

@Suite("WindowManager Callbacks")
struct WindowManagerCallbackTests {

  @MainActor
  @Test func onShowLauncherCalledWhenShowing() {
    let manager = WindowManager()
    var called = false
    manager.onShowLauncher = { called = true }
    manager.showLauncher()
    #expect(called)
  }

  @MainActor
  @Test func onAutoDismissNotCalledWhenHidden() {
    let manager = WindowManager()
    var called = false
    manager.onAutoDismiss = { called = true }
    // ランチャーが非表示状態では autoDismiss は呼ばれない
    manager.hideLauncher()
    #expect(!called)
  }

  @MainActor
  @Test("showLauncher で isLauncherVisible が true になる")
  func showLauncherSetsIsLauncherVisibleToTrue() {
    let manager = WindowManager()
    #expect(manager.isLauncherVisible == false)
    manager.showLauncher()
    #expect(manager.isLauncherVisible == true)
  }

  @MainActor
  @Test("hideLauncher で isLauncherVisible が false になる")
  func hideLauncherSetsIsLauncherVisibleToFalse() {
    let manager = WindowManager()
    manager.showLauncher()
    #expect(manager.isLauncherVisible == true)
    manager.hideLauncher()
    #expect(manager.isLauncherVisible == false)
  }

  @MainActor
  @Test("toggleLauncher で表示状態が切り替わる")
  func toggleLauncherTogglesVisibility() {
    let manager = WindowManager()
    #expect(manager.isLauncherVisible == false)
    manager.toggleLauncher()
    #expect(manager.isLauncherVisible == true)
    manager.toggleLauncher()
    #expect(manager.isLauncherVisible == false)
  }
}
