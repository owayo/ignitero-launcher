import AppKit
import Foundation
import Testing

@testable import IgniteroCore

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
