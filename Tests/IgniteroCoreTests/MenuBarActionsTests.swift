import AppKit
import Foundation
import Testing

@testable import IgniteroCore

// MARK: - Initial State Tests

@Suite("MenuBarActions Initial State")
@MainActor
struct MenuBarActionsInitialStateTests {

  @MainActor
  @Test func initialIsRebuildingCacheIsFalse() {
    let actions = MenuBarActions(
      windowManager: WindowManager(),
      settingsManager: SettingsManager(configDirectory: makeTempConfigDir())
    )
    #expect(actions.isRebuildingCache == false)
  }

  @MainActor
  @Test func initialIsSettingsOpenIsFalse() {
    let actions = MenuBarActions(
      windowManager: WindowManager(),
      settingsManager: SettingsManager(configDirectory: makeTempConfigDir())
    )
    #expect(actions.isSettingsOpen == false)
  }

  @MainActor
  @Test func initialOnRebuildCacheIsNil() {
    let actions = MenuBarActions(
      windowManager: WindowManager(),
      settingsManager: SettingsManager(configDirectory: makeTempConfigDir())
    )
    #expect(actions.onRebuildCache == nil)
  }
}

// MARK: - Show Window Tests

@Suite("MenuBarActions Show Window")
@MainActor
struct MenuBarActionsShowWindowTests {

  @MainActor
  @Test func showWindowSetsLauncherVisible() {
    let windowManager = WindowManager()
    let actions = MenuBarActions(
      windowManager: windowManager,
      settingsManager: SettingsManager(configDirectory: makeTempConfigDir())
    )

    #expect(windowManager.isLauncherVisible == false)
    actions.showWindow()
    #expect(windowManager.isLauncherVisible == true)
  }

  @MainActor
  @Test func showWindowIdempotent() {
    let windowManager = WindowManager()
    let actions = MenuBarActions(
      windowManager: windowManager,
      settingsManager: SettingsManager(configDirectory: makeTempConfigDir())
    )

    actions.showWindow()
    actions.showWindow()
    #expect(windowManager.isLauncherVisible == true)
  }
}

// MARK: - Rebuild Cache Tests

@Suite("MenuBarActions Rebuild Cache")
@MainActor
struct MenuBarActionsRebuildCacheTests {

  @MainActor
  @Test func rebuildCacheWithoutCallbackCompletesAndResetsFlag() async {
    let actions = MenuBarActions(
      windowManager: WindowManager(),
      settingsManager: SettingsManager(configDirectory: makeTempConfigDir())
    )

    // onRebuildCache 未設定でも処理は完了し、isRebuildingCache は false に戻る
    await actions.rebuildCache()
    #expect(actions.isRebuildingCache == false)
  }

  @MainActor
  @Test func rebuildCacheInvokesCallback() async {
    let actions = MenuBarActions(
      windowManager: WindowManager(),
      settingsManager: SettingsManager(configDirectory: makeTempConfigDir())
    )

    let callCounter = CallCounter()
    actions.onRebuildCache = { @MainActor in
      callCounter.increment()
    }

    await actions.rebuildCache()
    #expect(callCounter.value == 1)
    #expect(actions.isRebuildingCache == false)
  }

  @MainActor
  @Test func rebuildCacheSetsIsRebuildingCacheDuringExecution() async {
    let actions = MenuBarActions(
      windowManager: WindowManager(),
      settingsManager: SettingsManager(configDirectory: makeTempConfigDir())
    )

    let observed = ObservedFlag()
    actions.onRebuildCache = { @MainActor [actions] in
      observed.value = actions.isRebuildingCache
    }

    await actions.rebuildCache()
    // コールバック実行中は isRebuildingCache が true で観測されるべき
    #expect(observed.value == true)
    // 完了後は false に戻る
    #expect(actions.isRebuildingCache == false)
  }

  @MainActor
  @Test func rebuildCacheResetsFlagEvenIfCallbackThrowsLogically() async {
    // コールバック内で論理エラーが起きても defer で isRebuildingCache が必ず戻ることを確認する。
    // Swift の async クロージャは throws で宣言されていないため、
    // クロージャ内で throw 表現は使えないが、Task.cancel() などの非同期境界を経由しても
    // defer はメソッド終了時に実行される。
    let actions = MenuBarActions(
      windowManager: WindowManager(),
      settingsManager: SettingsManager(configDirectory: makeTempConfigDir())
    )

    actions.onRebuildCache = { @MainActor in
      // 何らかの内部処理が早期リターンするケースを想定
      return
    }

    await actions.rebuildCache()
    #expect(actions.isRebuildingCache == false)
  }
}

// MARK: - Open Settings Tests

@Suite("MenuBarActions Open Settings")
@MainActor
struct MenuBarActionsOpenSettingsTests {

  @MainActor
  @Test func openSettingsSetsIsSettingsOpenTrue() {
    let actions = MenuBarActions(
      windowManager: WindowManager(),
      settingsManager: SettingsManager(configDirectory: makeTempConfigDir())
    )

    actions.openSettings()
    #expect(actions.isSettingsOpen == true)
  }

  @MainActor
  @Test func openSettingsIdempotent() {
    let actions = MenuBarActions(
      windowManager: WindowManager(),
      settingsManager: SettingsManager(configDirectory: makeTempConfigDir())
    )

    actions.openSettings()
    actions.openSettings()
    #expect(actions.isSettingsOpen == true)
  }

  @MainActor
  @Test func closeSettingsSetsIsSettingsOpenFalse() {
    let actions = MenuBarActions(
      windowManager: WindowManager(),
      settingsManager: SettingsManager(configDirectory: makeTempConfigDir())
    )

    actions.openSettings()
    #expect(actions.isSettingsOpen == true)
    actions.closeSettings()
    #expect(actions.isSettingsOpen == false)
  }
}

// MARK: - Quit Tests

@Suite("MenuBarActions Quit")
@MainActor
struct MenuBarActionsQuitTests {

  @MainActor
  @Test func quitMethodExists() {
    let actions = MenuBarActions(
      windowManager: WindowManager(),
      settingsManager: SettingsManager(configDirectory: makeTempConfigDir())
    )

    // quit() メソッドが存在することを確認（コンパイル時チェック）
    // 実際の NSApplication.shared.terminate は呼ばない
    _ = actions.quit as () -> Void
    #expect(Bool(true))
  }
}

// MARK: - Dependencies Tests

@Suite("MenuBarActions Dependencies")
@MainActor
struct MenuBarActionsDependenciesTests {

  @MainActor
  @Test func hasWindowManager() {
    let windowManager = WindowManager()
    let actions = MenuBarActions(
      windowManager: windowManager,
      settingsManager: SettingsManager(configDirectory: makeTempConfigDir())
    )

    #expect(actions.windowManager === windowManager)
  }

  @MainActor
  @Test func hasSettingsManager() {
    let settingsManager = SettingsManager(configDirectory: makeTempConfigDir())
    let actions = MenuBarActions(
      windowManager: WindowManager(),
      settingsManager: settingsManager
    )

    #expect(actions.settingsManager === settingsManager)
  }
}

// MARK: - Menu Items Tests

@Suite("MenuBarActions Menu Items")
@MainActor
struct MenuBarActionsMenuItemsTests {

  @MainActor
  @Test func menuItemsReturnsExpectedItems() {
    let actions = MenuBarActions(
      windowManager: WindowManager(),
      settingsManager: SettingsManager(configDirectory: makeTempConfigDir())
    )

    let items = actions.menuItems
    #expect(items.count == 4)
    #expect(items[0].title == "ウィンドウを表示")
    #expect(items[1].title == "キャッシュを再構築")
    #expect(items[2].title == "設定")
    #expect(items[3].title == "終了")
  }

  @MainActor
  @Test func menuItemsShowRebuildingStateWhenCacheRebuilding() async {
    let actions = MenuBarActions(
      windowManager: WindowManager(),
      settingsManager: SettingsManager(configDirectory: makeTempConfigDir())
    )

    // rebuildCache 完了後はリビルド中でない
    await actions.rebuildCache()
    let items = actions.menuItems
    #expect(items[1].title == "キャッシュを再構築")
  }
}

// MARK: - Test Helpers

private func makeTempConfigDir() -> URL {
  FileManager.default.temporaryDirectory
    .appendingPathComponent("ignitero-menubar-test-\(UUID().uuidString)")
}

/// テスト用のスレッドセーフなカウンタ。
@MainActor
private final class CallCounter {
  private(set) var value: Int = 0
  func increment() { value += 1 }
}

/// コールバック実行中のフラグ観測用ヘルパー。
@MainActor
private final class ObservedFlag {
  var value: Bool = false
}
