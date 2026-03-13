import AppKit
import Foundation
import Testing

@testable import IgniteroCore

// MARK: - WindowManager Initial State Tests

@Suite("WindowManager Initial State")
struct WindowManagerInitialStateTests {

  @MainActor
  @Test func initialLauncherVisibilityIsFalse() {
    let manager = WindowManager(userDefaults: .makeTempDefaults())
    #expect(manager.isLauncherVisible == false)
  }

  @MainActor
  @Test func initialPickerVisibilityIsFalse() {
    let manager = WindowManager(userDefaults: .makeTempDefaults())
    #expect(manager.isPickerVisible == false)
  }

  @MainActor
  @Test func initialPanelIsNil() {
    let manager = WindowManager(userDefaults: .makeTempDefaults())
    #expect(manager.launcherPanel == nil)
  }
}

// MARK: - WindowManager Toggle Tests

@Suite("WindowManager Toggle")
struct WindowManagerToggleTests {

  @MainActor
  @Test func toggleLauncherFromHiddenToVisible() {
    let manager = WindowManager(userDefaults: .makeTempDefaults())
    #expect(manager.isLauncherVisible == false)
    manager.toggleLauncher()
    #expect(manager.isLauncherVisible == true)
  }

  @MainActor
  @Test func toggleLauncherFromVisibleToHidden() {
    let manager = WindowManager(userDefaults: .makeTempDefaults())
    manager.toggleLauncher()  // show
    #expect(manager.isLauncherVisible == true)
    manager.toggleLauncher()  // hide
    #expect(manager.isLauncherVisible == false)
  }

  @MainActor
  @Test func toggleLauncherMultipleTimes() {
    let manager = WindowManager(userDefaults: .makeTempDefaults())
    for i in 0..<6 {
      manager.toggleLauncher()
      let expectedVisible = (i % 2 == 0)  // 0->true, 1->false, 2->true...
      #expect(manager.isLauncherVisible == expectedVisible)
    }
  }
}

// MARK: - WindowManager Show/Hide Tests

@Suite("WindowManager Show/Hide")
struct WindowManagerShowHideTests {

  @MainActor
  @Test func showLauncherSetsVisibleTrue() {
    let manager = WindowManager(userDefaults: .makeTempDefaults())
    manager.showLauncher()
    #expect(manager.isLauncherVisible == true)
  }

  @MainActor
  @Test func showLauncherIdempotent() {
    let manager = WindowManager(userDefaults: .makeTempDefaults())
    manager.showLauncher()
    manager.showLauncher()
    #expect(manager.isLauncherVisible == true)
  }

  @MainActor
  @Test func hideLauncherSetsVisibleFalse() {
    let manager = WindowManager(userDefaults: .makeTempDefaults())
    manager.showLauncher()
    #expect(manager.isLauncherVisible == true)
    manager.hideLauncher()
    #expect(manager.isLauncherVisible == false)
  }

  @MainActor
  @Test func hideLauncherWhenAlreadyHiddenStaysHidden() {
    let manager = WindowManager(userDefaults: .makeTempDefaults())
    manager.hideLauncher()
    #expect(manager.isLauncherVisible == false)
  }

  @MainActor
  @Test func hideLauncherWorksEvenWhenPickerVisible() {
    let manager = WindowManager(userDefaults: .makeTempDefaults())
    manager.showLauncher()
    manager.showPicker()
    #expect(manager.isPickerVisible == true)
    manager.hideLauncher()
    // ピッカー表示中でもランチャーは隠せる（Tauri と同じフロー）
    #expect(manager.isLauncherVisible == false)
  }

  @MainActor
  @Test func hideLauncherAfterPickerHidden() {
    let manager = WindowManager(userDefaults: .makeTempDefaults())
    manager.showLauncher()
    manager.showPicker()
    manager.hidePicker()
    manager.hideLauncher()
    #expect(manager.isLauncherVisible == false)
  }

  @MainActor
  @Test func toggleLauncherClosesPickerAndShowsLauncher() {
    let manager = WindowManager(userDefaults: .makeTempDefaults())
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

// MARK: - WindowManager Sync Hidden State Tests

@Suite("WindowManager Sync Hidden State")
struct WindowManagerSyncHiddenStateTests {

  @MainActor
  @Test func syncHiddenStateSetsVisibleFalse() {
    let manager = WindowManager(userDefaults: .makeTempDefaults())
    manager.showLauncher()
    #expect(manager.isLauncherVisible == true)
    manager.syncHiddenState()
    #expect(manager.isLauncherVisible == false)
  }

  @MainActor
  @Test func syncHiddenStateNoOpWhenAlreadyHidden() {
    let manager = WindowManager(userDefaults: .makeTempDefaults())
    #expect(manager.isLauncherVisible == false)
    manager.syncHiddenState()
    #expect(manager.isLauncherVisible == false)
  }

  @MainActor
  @Test func syncHiddenStateAfterToggle() {
    let manager = WindowManager(userDefaults: .makeTempDefaults())
    manager.toggleLauncher()  // show
    #expect(manager.isLauncherVisible == true)
    manager.syncHiddenState()
    #expect(manager.isLauncherVisible == false)
    // Next toggle should show again
    manager.toggleLauncher()
    #expect(manager.isLauncherVisible == true)
  }
}

// MARK: - WindowManager Picker Tests

@Suite("WindowManager Picker Control")
struct WindowManagerPickerTests {

  @MainActor
  @Test func showPickerSetsVisibleTrue() {
    let manager = WindowManager(userDefaults: .makeTempDefaults())
    manager.showPicker()
    #expect(manager.isPickerVisible == true)
  }

  @MainActor
  @Test func hidePickerSetsVisibleFalse() {
    let manager = WindowManager(userDefaults: .makeTempDefaults())
    manager.showPicker()
    manager.hidePicker()
    #expect(manager.isPickerVisible == false)
  }

  @MainActor
  @Test func showPickerIdempotent() {
    let manager = WindowManager(userDefaults: .makeTempDefaults())
    manager.showPicker()
    manager.showPicker()
    #expect(manager.isPickerVisible == true)
  }

  @MainActor
  @Test func hidePickerIdempotent() {
    let manager = WindowManager(userDefaults: .makeTempDefaults())
    manager.showPicker()
    manager.hidePicker()
    manager.hidePicker()
    #expect(manager.isPickerVisible == false)
  }
}

// MARK: - WindowManager Resize Tests

@Suite("WindowManager Resize for Results")
struct WindowManagerResizeTests {

  @MainActor
  @Test func resizeForZeroResultsReturnsMinHeight() {
    let manager = WindowManager(userDefaults: .makeTempDefaults())
    let height = manager.heightForResults(count: 0)
    #expect(height == WindowManager.minHeight)
  }

  @MainActor
  @Test func resizeForOneResult() {
    let manager = WindowManager(userDefaults: .makeTempDefaults())
    let height = manager.heightForResults(count: 1)
    let expected = WindowManager.minHeight + WindowManager.rowHeight
    #expect(height == expected)
  }

  @MainActor
  @Test func resizeForFiveResults() {
    let manager = WindowManager(userDefaults: .makeTempDefaults())
    let height = manager.heightForResults(count: 5)
    let expected = WindowManager.minHeight + 5 * WindowManager.rowHeight
    #expect(height == expected)
  }

  @MainActor
  @Test func resizeForSevenResultsNotClamped() {
    let manager = WindowManager(userDefaults: .makeTempDefaults())
    let height = manager.heightForResults(count: 7)
    // 108 + 7*52 = 472, under 500 max
    let expected = WindowManager.minHeight + 7 * WindowManager.rowHeight
    #expect(height == expected)
    #expect(height < WindowManager.maxHeight)
  }

  @MainActor
  @Test func resizeForEightResultsClamps() {
    let manager = WindowManager(userDefaults: .makeTempDefaults())
    let height = manager.heightForResults(count: 8)
    // 108 + 8*52 = 524, clamped to 500
    #expect(height == WindowManager.maxHeight)
  }

  @MainActor
  @Test func resizeForTenResults() {
    let manager = WindowManager(userDefaults: .makeTempDefaults())
    let height = manager.heightForResults(count: 10)
    // 108 + 10*52 = 628, clamped to 500 max
    #expect(height == WindowManager.maxHeight)
  }

  @MainActor
  @Test func resizeForElevenResultsClampsToMaxHeight() {
    let manager = WindowManager(userDefaults: .makeTempDefaults())
    let height = manager.heightForResults(count: 11)
    // 108 + 11*52 = 680, clamped to 500
    #expect(height == WindowManager.maxHeight)
  }

  @MainActor
  @Test func resizeForTwentyResultsClampsToMaxHeight() {
    let manager = WindowManager(userDefaults: .makeTempDefaults())
    let height = manager.heightForResults(count: 20)
    #expect(height == WindowManager.maxHeight)
  }

  @MainActor
  @Test func resizeForNegativeCountTreatedAsZero() {
    let manager = WindowManager(userDefaults: .makeTempDefaults())
    let height = manager.heightForResults(count: -1)
    #expect(height == WindowManager.minHeight)
  }

  @MainActor
  @Test func resizeForResultsUpdatesCurrentHeight() {
    let manager = WindowManager(userDefaults: .makeTempDefaults())
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

// MARK: - WindowManager Position Persistence Tests

@Suite("WindowManager Position Persistence")
struct WindowManagerPositionTests {

  @MainActor
  @Test func savePositionPersistsToUserDefaults() {
    let defaults = UserDefaults.makeTempDefaults()
    let manager = WindowManager(userDefaults: defaults)
    manager.savePosition(x: 100, y: 200)

    let x = defaults.double(forKey: "ignitero.launcher.position.x")
    let y = defaults.double(forKey: "ignitero.launcher.position.y")
    let saved = defaults.bool(forKey: "ignitero.launcher.position.saved")

    #expect(x == 100)
    #expect(y == 200)
    #expect(saved == true)
  }

  @MainActor
  @Test func restorePositionReturnsNilWhenNoSavedData() {
    let defaults = UserDefaults.makeTempDefaults()
    let manager = WindowManager(userDefaults: defaults)
    let position = manager.restorePosition()
    #expect(position == nil)
  }

  @MainActor
  @Test func restorePositionReturnsValueWhenSaved() {
    let defaults = UserDefaults.makeTempDefaults()
    let manager = WindowManager(userDefaults: defaults)
    manager.savePosition(x: 300, y: 150)

    let position = manager.restorePosition()
    #expect(position != nil)
    #expect(position?.x == 300)
    #expect(position?.y == 150)
  }

  @MainActor
  @Test func saveAndRestoreRoundTrip() {
    let defaults = UserDefaults.makeTempDefaults()
    let manager = WindowManager(userDefaults: defaults)
    manager.savePosition(x: 42.5, y: 99.7)

    // Simulate restart with new manager using same defaults
    let manager2 = WindowManager(userDefaults: defaults)
    let position = manager2.restorePosition()
    #expect(position != nil)
    #expect(position?.x == 42.5)
    #expect(position?.y == 99.7)
  }

  @MainActor
  @Test func savePositionOverwritesPrevious() {
    let defaults = UserDefaults.makeTempDefaults()
    let manager = WindowManager(userDefaults: defaults)
    manager.savePosition(x: 10, y: 20)
    manager.savePosition(x: 500, y: 600)

    let position = manager.restorePosition()
    #expect(position?.x == 500)
    #expect(position?.y == 600)
  }
}

// MARK: - WindowManager Resize Edge Cases

@Suite("WindowManager Resize Edge Cases")
struct WindowManagerResizeEdgeCaseTests {

  @MainActor
  @Test func resizeForVeryLargeCountClampsToMax() {
    let manager = WindowManager(userDefaults: .makeTempDefaults())
    let height = manager.heightForResults(count: 10000)
    #expect(height == WindowManager.maxHeight)
  }

  @MainActor
  @Test func resizeForZeroUpdatesCurrentHeight() {
    let manager = WindowManager(userDefaults: .makeTempDefaults())
    manager.resizeForResults(count: 5)
    #expect(manager.currentHeight > WindowManager.minHeight)
    manager.resizeForResults(count: 0)
    #expect(manager.currentHeight == WindowManager.minHeight)
  }
}

// MARK: - WindowManager Position Edge Cases

@Suite("WindowManager Position Edge Cases")
struct WindowManagerPositionEdgeCaseTests {

  @MainActor
  @Test func saveAndRestoreNegativeCoordinates() {
    let defaults = UserDefaults.makeTempDefaults()
    let manager = WindowManager(userDefaults: defaults)
    manager.savePosition(x: -500, y: -200)
    let position = manager.restorePosition()
    #expect(position?.x == -500)
    #expect(position?.y == -200)
  }

  @MainActor
  @Test func saveAndRestoreZeroCoordinates() {
    let defaults = UserDefaults.makeTempDefaults()
    let manager = WindowManager(userDefaults: defaults)
    manager.savePosition(x: 0, y: 0)
    let position = manager.restorePosition()
    #expect(position?.x == 0)
    #expect(position?.y == 0)
  }
}

// MARK: - WindowManager Callbacks

@Suite("WindowManager Callbacks")
struct WindowManagerCallbackTests {

  @MainActor
  @Test func onShowLauncherCalledWhenShowing() {
    let manager = WindowManager(userDefaults: .makeTempDefaults())
    var called = false
    manager.onShowLauncher = { called = true }
    manager.showLauncher()
    #expect(called)
  }

  @MainActor
  @Test func onAutoDismissNotCalledWhenHidden() {
    let manager = WindowManager(userDefaults: .makeTempDefaults())
    var called = false
    manager.onAutoDismiss = { called = true }
    // ランチャーが非表示状態では autoDismiss は呼ばれない
    manager.hideLauncher()
    #expect(!called)
  }
}

// MARK: - UserDefaults Test Helper

extension UserDefaults {
  /// Creates a temporary UserDefaults suite for isolated testing.
  static func makeTempDefaults() -> UserDefaults {
    let suiteName = "ignitero-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    return defaults
  }
}
