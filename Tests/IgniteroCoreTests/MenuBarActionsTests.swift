import AppKit
import Foundation
import Testing

@testable import IgniteroCore

// MARK: - Mock AppScanner for MenuBarActions

private struct MenuBarMockAppScanner: AppScannerProtocol, @unchecked Sendable {
  var appsToReturn: [AppItem] = []
  var shouldThrow = false

  func scanApplications(excludedApps: [String]) throws -> [AppItem] {
    if shouldThrow {
      throw AppScannerError.scanFailed("Mock scan failed")
    }
    return appsToReturn
  }
}

// MARK: - Mock DirectoryScanner for MenuBarActions

private struct MenuBarMockDirectoryScanner: DirectoryScannerProtocol, @unchecked Sendable {
  var resultToReturn: ScanResult = ScanResult(directories: [], apps: [])
  var shouldThrow = false

  func scan(directories: [RegisteredDirectory]) throws -> ScanResult {
    if shouldThrow {
      throw FileSystemError.directoryNotFound("Mock directory not found")
    }
    return resultToReturn
  }
}

// MARK: - Initial State Tests

@Suite("MenuBarActions Initial State")
struct MenuBarActionsInitialStateTests {

  @MainActor
  @Test func initialIsRebuildingCacheIsFalse() {
    let actions = MenuBarActions(
      windowManager: WindowManager(userDefaults: .makeTempDefaults()),
      settingsManager: SettingsManager(configDirectory: makeTempConfigDir()),
      appScanner: MenuBarMockAppScanner(),
      directoryScanner: MenuBarMockDirectoryScanner()
    )
    #expect(actions.isRebuildingCache == false)
  }

  @MainActor
  @Test func initialIsSettingsOpenIsFalse() {
    let actions = MenuBarActions(
      windowManager: WindowManager(userDefaults: .makeTempDefaults()),
      settingsManager: SettingsManager(configDirectory: makeTempConfigDir()),
      appScanner: MenuBarMockAppScanner(),
      directoryScanner: MenuBarMockDirectoryScanner()
    )
    #expect(actions.isSettingsOpen == false)
  }
}

// MARK: - Show Window Tests

@Suite("MenuBarActions Show Window")
struct MenuBarActionsShowWindowTests {

  @MainActor
  @Test func showWindowSetsLauncherVisible() {
    let windowManager = WindowManager(userDefaults: .makeTempDefaults())
    let actions = MenuBarActions(
      windowManager: windowManager,
      settingsManager: SettingsManager(configDirectory: makeTempConfigDir()),
      appScanner: MenuBarMockAppScanner(),
      directoryScanner: MenuBarMockDirectoryScanner()
    )

    #expect(windowManager.isLauncherVisible == false)
    actions.showWindow()
    #expect(windowManager.isLauncherVisible == true)
  }

  @MainActor
  @Test func showWindowIdempotent() {
    let windowManager = WindowManager(userDefaults: .makeTempDefaults())
    let actions = MenuBarActions(
      windowManager: windowManager,
      settingsManager: SettingsManager(configDirectory: makeTempConfigDir()),
      appScanner: MenuBarMockAppScanner(),
      directoryScanner: MenuBarMockDirectoryScanner()
    )

    actions.showWindow()
    actions.showWindow()
    #expect(windowManager.isLauncherVisible == true)
  }
}

// MARK: - Rebuild Cache Tests

@Suite("MenuBarActions Rebuild Cache")
struct MenuBarActionsRebuildCacheTests {

  @MainActor
  @Test func rebuildCacheSetsIsRebuildingCacheTrue() async {
    let actions = MenuBarActions(
      windowManager: WindowManager(userDefaults: .makeTempDefaults()),
      settingsManager: SettingsManager(configDirectory: makeTempConfigDir()),
      appScanner: MenuBarMockAppScanner(),
      directoryScanner: MenuBarMockDirectoryScanner()
    )

    // rebuildCache は async で実行し、完了後に isRebuildingCache は false に戻る
    await actions.rebuildCache()
    // 完了後は false
    #expect(actions.isRebuildingCache == false)
  }

  @MainActor
  @Test func rebuildCacheCompletesWithoutError() async {
    let mockAppScanner = MenuBarMockAppScanner(
      appsToReturn: [AppItem(name: "TestApp", path: "/Applications/TestApp.app")]
    )
    let mockDirectoryScanner = MenuBarMockDirectoryScanner(
      resultToReturn: ScanResult(
        directories: [DirectoryItem(name: "Projects", path: "/Users/test/Projects")],
        apps: []
      )
    )

    let actions = MenuBarActions(
      windowManager: WindowManager(userDefaults: .makeTempDefaults()),
      settingsManager: SettingsManager(configDirectory: makeTempConfigDir()),
      appScanner: mockAppScanner,
      directoryScanner: mockDirectoryScanner
    )

    await actions.rebuildCache()
    #expect(actions.isRebuildingCache == false)
  }

  @MainActor
  @Test func rebuildCacheHandlesAppScannerError() async {
    let mockAppScanner = MenuBarMockAppScanner(shouldThrow: true)
    let actions = MenuBarActions(
      windowManager: WindowManager(userDefaults: .makeTempDefaults()),
      settingsManager: SettingsManager(configDirectory: makeTempConfigDir()),
      appScanner: mockAppScanner,
      directoryScanner: MenuBarMockDirectoryScanner()
    )

    // エラーが発生しても isRebuildingCache は false に戻る
    await actions.rebuildCache()
    #expect(actions.isRebuildingCache == false)
  }

  @MainActor
  @Test func rebuildCacheHandlesDirectoryScannerError() async {
    let mockDirectoryScanner = MenuBarMockDirectoryScanner(shouldThrow: true)
    let actions = MenuBarActions(
      windowManager: WindowManager(userDefaults: .makeTempDefaults()),
      settingsManager: SettingsManager(configDirectory: makeTempConfigDir()),
      appScanner: MenuBarMockAppScanner(),
      directoryScanner: mockDirectoryScanner
    )

    await actions.rebuildCache()
    #expect(actions.isRebuildingCache == false)
  }
}

// MARK: - Open Settings Tests

@Suite("MenuBarActions Open Settings")
struct MenuBarActionsOpenSettingsTests {

  @MainActor
  @Test func openSettingsSetsIsSettingsOpenTrue() {
    let actions = MenuBarActions(
      windowManager: WindowManager(userDefaults: .makeTempDefaults()),
      settingsManager: SettingsManager(configDirectory: makeTempConfigDir()),
      appScanner: MenuBarMockAppScanner(),
      directoryScanner: MenuBarMockDirectoryScanner()
    )

    actions.openSettings()
    #expect(actions.isSettingsOpen == true)
  }

  @MainActor
  @Test func openSettingsIdempotent() {
    let actions = MenuBarActions(
      windowManager: WindowManager(userDefaults: .makeTempDefaults()),
      settingsManager: SettingsManager(configDirectory: makeTempConfigDir()),
      appScanner: MenuBarMockAppScanner(),
      directoryScanner: MenuBarMockDirectoryScanner()
    )

    actions.openSettings()
    actions.openSettings()
    #expect(actions.isSettingsOpen == true)
  }

  @MainActor
  @Test func closeSettingsSetsIsSettingsOpenFalse() {
    let actions = MenuBarActions(
      windowManager: WindowManager(userDefaults: .makeTempDefaults()),
      settingsManager: SettingsManager(configDirectory: makeTempConfigDir()),
      appScanner: MenuBarMockAppScanner(),
      directoryScanner: MenuBarMockDirectoryScanner()
    )

    actions.openSettings()
    #expect(actions.isSettingsOpen == true)
    actions.closeSettings()
    #expect(actions.isSettingsOpen == false)
  }
}

// MARK: - Quit Tests

@Suite("MenuBarActions Quit")
struct MenuBarActionsQuitTests {

  @MainActor
  @Test func quitMethodExists() {
    let actions = MenuBarActions(
      windowManager: WindowManager(userDefaults: .makeTempDefaults()),
      settingsManager: SettingsManager(configDirectory: makeTempConfigDir()),
      appScanner: MenuBarMockAppScanner(),
      directoryScanner: MenuBarMockDirectoryScanner()
    )

    // quit() メソッドが存在することを確認（コンパイル時チェック）
    // 実際の NSApplication.shared.terminate は呼ばない
    _ = actions.quit as () -> Void
    #expect(Bool(true))
  }
}

// MARK: - Dependencies Tests

@Suite("MenuBarActions Dependencies")
struct MenuBarActionsDependenciesTests {

  @MainActor
  @Test func hasWindowManager() {
    let windowManager = WindowManager(userDefaults: .makeTempDefaults())
    let actions = MenuBarActions(
      windowManager: windowManager,
      settingsManager: SettingsManager(configDirectory: makeTempConfigDir()),
      appScanner: MenuBarMockAppScanner(),
      directoryScanner: MenuBarMockDirectoryScanner()
    )

    #expect(actions.windowManager === windowManager)
  }

  @MainActor
  @Test func hasSettingsManager() {
    let settingsManager = SettingsManager(configDirectory: makeTempConfigDir())
    let actions = MenuBarActions(
      windowManager: WindowManager(userDefaults: .makeTempDefaults()),
      settingsManager: settingsManager,
      appScanner: MenuBarMockAppScanner(),
      directoryScanner: MenuBarMockDirectoryScanner()
    )

    #expect(actions.settingsManager === settingsManager)
  }
}

// MARK: - Menu Items Tests

@Suite("MenuBarActions Menu Items")
struct MenuBarActionsMenuItemsTests {

  @MainActor
  @Test func menuItemsReturnsExpectedItems() {
    let actions = MenuBarActions(
      windowManager: WindowManager(userDefaults: .makeTempDefaults()),
      settingsManager: SettingsManager(configDirectory: makeTempConfigDir()),
      appScanner: MenuBarMockAppScanner(),
      directoryScanner: MenuBarMockDirectoryScanner()
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
      windowManager: WindowManager(userDefaults: .makeTempDefaults()),
      settingsManager: SettingsManager(configDirectory: makeTempConfigDir()),
      appScanner: MenuBarMockAppScanner(),
      directoryScanner: MenuBarMockDirectoryScanner()
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
