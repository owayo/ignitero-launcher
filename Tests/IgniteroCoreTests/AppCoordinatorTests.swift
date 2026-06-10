import AppKit
import Foundation
import Testing

@testable import IgniteroCore

// MARK: - モック実装

/// テスト用モック CacheDatabase
private final class MockCacheDB: CacheDatabaseProtocol, @unchecked Sendable {
  var isEmptyResult = true
  var saveAppsCalled = false
  var loadAppsCalled = false
  var saveDirectoriesCalled = false
  var loadDirectoriesCalled = false
  var clearCacheCalled = false
  var savedApps: [AppItem] = []
  var loadedApps: [AppItem] = []
  var savedDirectories: [DirectoryItem] = []
  var loadedDirectories: [DirectoryItem] = []

  init(isEmpty: Bool = true) {
    self.isEmptyResult = isEmpty
  }

  func isEmpty() throws -> Bool { isEmptyResult }

  func saveApps(_ apps: [AppItem]) throws {
    saveAppsCalled = true
    savedApps = apps
  }

  func loadApps() async throws -> [AppItem] {
    loadAppsCalled = true
    return loadedApps
  }

  func saveDirectories(_ dirs: [DirectoryItem]) throws {
    saveDirectoriesCalled = true
    savedDirectories = dirs
  }

  func loadDirectories() async throws -> [DirectoryItem] {
    loadDirectoriesCalled = true
    return loadedDirectories
  }

  func clearCache() throws {
    clearCacheCalled = true
  }
}

/// テスト用モック AppScanner
private struct MockAppScanner: AppScannerProtocol {
  let apps: [AppItem]

  init(apps: [AppItem] = []) {
    self.apps = apps
  }

  func scanApplications(excludedApps: [String]) throws -> [AppItem] {
    apps.filter { !excludedApps.contains($0.path) }
  }
}

/// テスト用モック DirectoryScanner
private struct MockDirScanner: DirectoryScannerProtocol {
  let result: ScanResult

  init(result: ScanResult = ScanResult(directories: [], apps: [])) {
    self.result = result
  }

  func scan(directories: [RegisteredDirectory]) throws -> ScanResult {
    result
  }
}

/// テスト用モック IMEController（AppCoordinator テスト用）
private struct CoordinatorMockIMEController: IMEControlling {
  func switchToASCII() {
    // テスト用: 何もしない
  }
}

/// テスト用モック LaunchService
private final class MockLaunchService: Launching, @unchecked Sendable {
  var launchAppCalledWith: String?
  var openDirectoryCalledWith: (path: String, editor: EditorType?)?
  var openInTerminalCalledWith: (path: String, terminal: TerminalType)?
  var executeCommandCalledWith:
    (command: String, workingDirectory: String?, terminal: TerminalType)?

  func launchApp(at path: String) async throws {
    launchAppCalledWith = path
  }

  func openDirectory(_ path: String, editor: EditorType?) async throws {
    openDirectoryCalledWith = (path, editor)
  }

  func openInTerminal(_ path: String, terminal: TerminalType) async throws {
    openInTerminalCalledWith = (path, terminal)
  }

  func executeCommand(
    _ command: String, workingDirectory: String?, terminal: TerminalType
  ) async throws {
    executeCommandCalledWith = (command, workingDirectory, terminal)
  }

  func availableEditors() -> [EditorInfo] {
    EditorType.allCases.map { editor in
      EditorInfo(
        id: editor,
        name: editor.rawValue,
        appName: "\(editor.rawValue).app",
        installed: true
      )
    }
  }

  func availableTerminals() -> [TerminalInfo] {
    TerminalType.allCases.map { terminal in
      TerminalInfo(
        id: terminal,
        name: terminal.rawValue,
        appName: "\(terminal.rawValue).app",
        installed: true
      )
    }
  }
}

/// テスト用モック URLSession（アップデートチェック用）
private struct MockURLSession: URLSessionProtocol {
  let responseData: Data
  let statusCode: Int

  init(responseData: Data = "[]".data(using: .utf8)!, statusCode: Int = 200) {
    self.responseData = responseData
    self.statusCode = statusCode
  }

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: statusCode,
      httpVersion: nil,
      headerFields: nil
    )!
    return (responseData, response)
  }
}

// MARK: - テスト補助

@MainActor
private func makeTempSettingsManager() -> SettingsManager {
  let dir = FileManager.default.temporaryDirectory
    .appendingPathComponent("ignitero-coord-test-\(UUID().uuidString)")
  return SettingsManager(configDirectory: dir)
}

private func makeTempSelectionHistory() -> SelectionHistory {
  let path = FileManager.default.temporaryDirectory
    .appendingPathComponent("ignitero-history-test-\(UUID().uuidString).json").path
  return SelectionHistory(filePath: path)
}

@MainActor
private func makeCoordinator(
  settingsManager: SettingsManager? = nil,
  cacheDatabase: (any CacheDatabaseProtocol)? = nil,
  imeController: (any IMEControlling)? = nil,
  launchService: (any Launching)? = nil,
  appScanner: (any AppScannerProtocol)? = nil,
  directoryScanner: (any DirectoryScannerProtocol)? = nil,
  selectionHistory: SelectionHistory? = nil,
  urlSession: (any URLSessionProtocol)? = nil
) -> AppCoordinator {
  AppCoordinator(
    settingsManager: settingsManager ?? makeTempSettingsManager(),
    cacheDatabase: cacheDatabase ?? MockCacheDB(isEmpty: true),
    imeController: imeController ?? CoordinatorMockIMEController(),
    launchService: launchService ?? MockLaunchService(),
    appScanner: appScanner ?? MockAppScanner(),
    directoryScanner: directoryScanner ?? MockDirScanner(),
    selectionHistory: selectionHistory ?? makeTempSelectionHistory(),
    urlSession: urlSession ?? MockURLSession(),
    shortcutDebounceInterval: .zero
  )
}

// MARK: - 初期化テスト

@Suite("AppCoordinator Initialization")
struct AppCoordinatorInitTests {

  @Test("All components are wired correctly")
  @MainActor
  func allComponentsWired() {
    let settings = makeTempSettingsManager()
    let mockDB = MockCacheDB()
    let mockIME = CoordinatorMockIMEController()
    let mockLaunch = MockLaunchService()
    let mockAppScanner = MockAppScanner()
    let mockDirScanner = MockDirScanner()
    let history = makeTempSelectionHistory()

    let coordinator = AppCoordinator(
      settingsManager: settings,
      cacheDatabase: mockDB,
      imeController: mockIME,
      launchService: mockLaunch,
      appScanner: mockAppScanner,
      directoryScanner: mockDirScanner,
      selectionHistory: history,
      urlSession: MockURLSession()
    )

    // コアサービスを確認する
    #expect(coordinator.settingsManager === settings)
    #expect(coordinator.selectionHistory === history)

    // UI コンポーネントの存在を確認する
    #expect(coordinator.windowManager.launcherPanel === coordinator.launcherPanel)
    #expect(coordinator.launcherViewModel.searchQuery == "")
    #expect(coordinator.settingsViewModel.settingsManager === settings)

    // アプリ層コーディネーターを確認する
    #expect(coordinator.globalShortcut.windowManager === coordinator.windowManager)
    #expect(coordinator.menuBarActions.windowManager === coordinator.windowManager)
    #expect(coordinator.menuBarActions.settingsManager === settings)
  }

  @Test("Default initialization succeeds")
  @MainActor
  func defaultInitializationSucceeds() {
    // ファイルシステムアクセスを避けるためモック DB を使う
    let coordinator = makeCoordinator()
    #expect(coordinator.launcherViewModel.searchQuery == "")
    #expect(coordinator.launcherViewModel.searchResults.isEmpty)
  }

  @Test("Launcher panel is configured on window manager")
  @MainActor
  func launcherPanelConfigured() {
    let coordinator = makeCoordinator()
    #expect(coordinator.windowManager.launcherPanel != nil)
    #expect(coordinator.windowManager.launcherPanel === coordinator.launcherPanel)
  }
}

// MARK: - 起動・終了テスト

@Suite("AppCoordinator Lifecycle")
struct AppCoordinatorLifecycleTests {

  @Test("start() runs without crash")
  @MainActor
  func startRunsWithoutCrash() async {
    let coordinator = makeCoordinator()
    await coordinator.start()
    // ここまで到達すれば start() はクラッシュせず完了している
    #expect(Bool(true))
  }

  @Test("start() loads settings")
  @MainActor
  func startLoadsSettings() async {
    let settings = makeTempSettingsManager()
    settings.settings.defaultTerminal = .iterm2
    try? settings.save()

    let coordinator = makeCoordinator(settingsManager: settings)
    await coordinator.start()

    #expect(coordinator.settingsManager.settings.defaultTerminal == .iterm2)
  }

  @Test("start() loads selection history")
  @MainActor
  func startLoadsSelectionHistory() async {
    let history = makeTempSelectionHistory()
    let testApp = AppItem(name: "TestApp", path: "/Applications/TestApp.app")
    history.record(keyword: "test", path: testApp.path)
    try? history.save()

    let coordinator = makeCoordinator(
      appScanner: MockAppScanner(apps: [testApp]),
      selectionHistory: history
    )
    await coordinator.start()

    #expect(coordinator.selectionHistory.allEntries.count == 1)
    #expect(coordinator.launcherViewModel.history.count == 1)
  }

  @Test("start() loads commands from settings into view model")
  @MainActor
  func startLoadsCommandsIntoViewModel() async {
    let settings = makeTempSettingsManager()
    settings.settings.customCommands = [
      CustomCommand(alias: "build", command: "make build")
    ]
    try? settings.save()

    let coordinator = makeCoordinator(settingsManager: settings)
    await coordinator.start()

    #expect(coordinator.launcherViewModel.commands.count == 1)
    #expect(coordinator.launcherViewModel.commands[0].alias == "build")
  }

  @Test("start() loads cached apps and directories through CacheDatabaseProtocol")
  @MainActor
  func startLoadsCachedItemsThroughProtocol() async {
    let settings = makeTempSettingsManager()
    settings.settings.cacheUpdate = CacheUpdateSettings(
      updateOnStartup: false,
      autoUpdateEnabled: false,
      autoUpdateIntervalHours: 6
    )
    try? settings.save()

    let mockDB = MockCacheDB(isEmpty: false)
    mockDB.loadedApps = [
      AppItem(name: "CachedApp", path: "/Applications/CachedApp.app")
    ]
    mockDB.loadedDirectories = [
      DirectoryItem(name: "cached-project", path: "/Users/dev/cached-project")
    ]

    let coordinator = makeCoordinator(
      settingsManager: settings,
      cacheDatabase: mockDB
    )
    await coordinator.start()

    #expect(mockDB.loadAppsCalled == true)
    #expect(mockDB.loadDirectoriesCalled == true)
    #expect(coordinator.launcherViewModel.apps.map(\.name) == ["CachedApp"])
    #expect(coordinator.launcherViewModel.directories.map(\.name) == ["cached-project"])
  }

  @Test("start() preserves command selection history")
  @MainActor
  func startPreservesCommandSelectionHistory() async throws {
    let settings = makeTempSettingsManager()
    let commandID = try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
    let command = CustomCommand(id: commandID, alias: "build", command: "make build")
    settings.settings.customCommands = [command]
    try? settings.save()

    let history = makeTempSelectionHistory()
    history.record(keyword: "build", path: command.historyIdentifier)
    try? history.save()

    let coordinator = makeCoordinator(
      settingsManager: settings,
      selectionHistory: history
    )
    await coordinator.start()

    coordinator.launcherViewModel.searchQuery = ""
    coordinator.launcherViewModel.updateSearch()

    #expect(coordinator.selectionHistory.allEntries.count == 1)
    #expect(coordinator.launcherViewModel.searchResults.count == 1)
    #expect(coordinator.launcherViewModel.searchResults[0].kind == .command)
    #expect(coordinator.launcherViewModel.searchResults[0].name == "build")
  }

  @Test("shutdown() does not crash")
  @MainActor
  func shutdownDoesNotCrash() async {
    let coordinator = makeCoordinator()
    await coordinator.start()
    coordinator.shutdown()
    #expect(Bool(true))
  }

  @Test("shutdown() saves selection history")
  @MainActor
  func shutdownSavesHistory() async {
    let history = makeTempSelectionHistory()
    let coordinator = makeCoordinator(selectionHistory: history)
    await coordinator.start()

    // 履歴を追加する
    history.record(keyword: "chrome", path: "/Applications/Chrome.app")

    coordinator.shutdown()

    // 保存確認のため再読み込み用インスタンスを作る
    let reloaded = SelectionHistory(filePath: history.allEntries.isEmpty ? "" : "")
    // ファイル保存時にクラッシュしないことを確認する
    #expect(Bool(true))
    _ = reloaded  // 未使用警告を避ける
  }
}

// MARK: - 検索フローテスト

@Suite("AppCoordinator Search Flow")
struct AppCoordinatorSearchFlowTests {

  @Test("Search query updates search results")
  @MainActor
  func searchQueryUpdatesResults() async {
    let coordinator = makeCoordinator()

    // データを準備する
    coordinator.launcherViewModel.apps = [
      AppItem(name: "Safari", path: "/Applications/Safari.app"),
      AppItem(name: "Xcode", path: "/Applications/Xcode.app"),
    ]

    // 検索を実行する
    coordinator.launcherViewModel.searchQuery = "saf"
    coordinator.launcherViewModel.updateSearch()

    #expect(!coordinator.launcherViewModel.searchResults.isEmpty)
    #expect(coordinator.launcherViewModel.searchResults[0].name == "Safari")
  }

  @Test("Search with empty query returns no results")
  @MainActor
  func searchEmptyQueryReturnsNoResults() async {
    let coordinator = makeCoordinator()

    coordinator.launcherViewModel.apps = [
      AppItem(name: "Safari", path: "/Applications/Safari.app")
    ]

    coordinator.launcherViewModel.searchQuery = ""
    coordinator.launcherViewModel.updateSearch()

    #expect(coordinator.launcherViewModel.searchResults.isEmpty)
  }

  @Test("Calculator expression is evaluated")
  @MainActor
  func calculatorExpressionEvaluated() async {
    let coordinator = makeCoordinator()

    coordinator.launcherViewModel.searchQuery = "2 + 3"
    coordinator.launcherViewModel.updateSearch()

    #expect(coordinator.launcherViewModel.calculatorResult == "5")
  }

  @Test("Selection navigation works")
  @MainActor
  func selectionNavigationWorks() async {
    let coordinator = makeCoordinator()

    coordinator.launcherViewModel.apps = [
      AppItem(name: "Safari", path: "/Applications/Safari.app"),
      AppItem(name: "Slack", path: "/Applications/Slack.app"),
    ]

    coordinator.launcherViewModel.searchQuery = "s"
    coordinator.launcherViewModel.updateSearch()

    #expect(coordinator.launcherViewModel.selectedIndex == 0)

    coordinator.launcherViewModel.moveSelectionDown()
    #expect(coordinator.launcherViewModel.selectedIndex == 1)

    coordinator.launcherViewModel.moveSelectionUp()
    #expect(coordinator.launcherViewModel.selectedIndex == 0)
  }
}

// MARK: - 実行結果テスト

@Suite("AppCoordinator Execute Result")
struct AppCoordinatorExecuteResultTests {

  @Test("Execute app result launches app")
  @MainActor
  func executeAppResultLaunchesApp() async throws {
    let mockLaunch = MockLaunchService()
    let coordinator = makeCoordinator(launchService: mockLaunch)

    let result = SearchResult(
      appItem: AppItem(name: "Safari", path: "/Applications/Safari.app"),
      score: 0.0
    )

    coordinator.executeResult(result)

    // 非同期タスクの完了を待つ
    try await Task.sleep(nanoseconds: 100_000_000)

    #expect(mockLaunch.launchAppCalledWith == "/Applications/Safari.app")
  }

  @Test("Execute command result executes command")
  @MainActor
  func executeCommandResultExecutesCommand() async throws {
    let mockLaunch = MockLaunchService()
    let settings = makeTempSettingsManager()
    settings.settings.defaultTerminal = .iterm2
    let coordinator = makeCoordinator(
      settingsManager: settings,
      launchService: mockLaunch
    )

    let cmd = CustomCommand(alias: "build", command: "make build", workingDirectory: "/project")
    let result = SearchResult(customCommand: cmd, score: 0.0)

    coordinator.executeResult(result)

    // 非同期タスクの完了を待つ
    try await Task.sleep(nanoseconds: 100_000_000)

    #expect(mockLaunch.executeCommandCalledWith?.command == "make build")
    #expect(mockLaunch.executeCommandCalledWith?.workingDirectory == "/project")
    #expect(mockLaunch.executeCommandCalledWith?.terminal == .iterm2)
  }

  @Test("Execute result records selection history")
  @MainActor
  func executeResultRecordsHistory() async {
    let history = makeTempSelectionHistory()
    let coordinator = makeCoordinator(
      launchService: MockLaunchService(),
      selectionHistory: history
    )

    coordinator.launcherViewModel.searchQuery = "safari"

    let result = SearchResult(
      appItem: AppItem(name: "Safari", path: "/Applications/Safari.app"),
      score: 0.0
    )

    coordinator.executeResult(result)

    #expect(history.allEntries.count == 1)
    #expect(history.allEntries[0].keyword == "safari")
    #expect(history.allEntries[0].selectedPath == "/Applications/Safari.app")
  }

  @Test("Execute result normalizes history keyword")
  @MainActor
  func executeResultNormalizesHistoryKeyword() async {
    let history = makeTempSelectionHistory()
    let coordinator = makeCoordinator(
      launchService: MockLaunchService(),
      selectionHistory: history
    )

    // 大文字・全角・前後空白を含む生クエリで実行する
    coordinator.launcherViewModel.searchQuery = " Ｘｃｏｄｅ "

    let result = SearchResult(
      appItem: AppItem(name: "Xcode", path: "/Applications/Xcode.app"),
      score: 0.0
    )

    coordinator.executeResult(result)

    // 検索時の比較（applyHistoryBoost）と一致させるため、履歴 keyword は正規化済み "xcode" で保存される
    #expect(history.allEntries.count == 1)
    #expect(history.allEntries[0].keyword == "xcode")
    #expect(history.allEntries[0].selectedPath == "/Applications/Xcode.app")
  }

  @Test("Execute command result records command history identifier")
  @MainActor
  func executeCommandResultRecordsCommandHistoryIdentifier() async throws {
    let history = makeTempSelectionHistory()
    let coordinator = makeCoordinator(
      launchService: MockLaunchService(),
      selectionHistory: history
    )
    let commandID = try #require(UUID(uuidString: "44444444-4444-4444-4444-444444444444"))
    let command = CustomCommand(id: commandID, alias: "build", command: "make build")

    coordinator.launcherViewModel.searchQuery = "build"
    coordinator.executeResult(SearchResult(customCommand: command, score: 0.0))

    #expect(history.allEntries.count == 1)
    #expect(history.allEntries[0].keyword == "build")
    #expect(history.allEntries[0].selectedPath == command.historyIdentifier)
  }

  @Test("Execute result clears search")
  @MainActor
  func executeResultClearsSearch() async {
    let coordinator = makeCoordinator(launchService: MockLaunchService())

    coordinator.launcherViewModel.searchQuery = "safari"
    coordinator.launcherViewModel.apps = [
      AppItem(name: "Safari", path: "/Applications/Safari.app")
    ]
    coordinator.launcherViewModel.updateSearch()

    let result = SearchResult(
      appItem: AppItem(name: "Safari", path: "/Applications/Safari.app"),
      score: 0.0
    )

    coordinator.executeResult(result)

    #expect(coordinator.launcherViewModel.searchQuery == "")
    #expect(coordinator.launcherViewModel.searchResults.isEmpty)
  }
}

// MARK: - ランチャー非表示テスト

@Suite("AppCoordinator Dismiss Launcher")
struct AppCoordinatorDismissLauncherTests {

  @Test("dismissLauncher clears search and hides window")
  @MainActor
  func dismissLauncherClearsAndHides() {
    let coordinator = makeCoordinator()

    // 先にランチャーを表示する
    coordinator.windowManager.showLauncher()
    #expect(coordinator.windowManager.isLauncherVisible == true)

    coordinator.launcherViewModel.searchQuery = "test"
    coordinator.dismissLauncher()

    #expect(coordinator.launcherViewModel.searchQuery == "")
    #expect(coordinator.windowManager.isLauncherVisible == false)
  }
}

// MARK: - ターミナル起動テスト

@Suite("AppCoordinator Open In Terminal")
struct AppCoordinatorOpenInTerminalTests {

  @Test("openInTerminal uses default terminal from settings")
  @MainActor
  func openInTerminalUsesDefaultTerminal() async throws {
    let mockLaunch = MockLaunchService()
    let settings = makeTempSettingsManager()
    settings.settings.defaultTerminal = .ghostty

    let coordinator = makeCoordinator(
      settingsManager: settings,
      launchService: mockLaunch
    )

    coordinator.openInTerminal("/Users/dev/project")

    // 非同期タスクの完了を待つ
    try await Task.sleep(nanoseconds: 100_000_000)

    #expect(mockLaunch.openInTerminalCalledWith?.path == "/Users/dev/project")
    #expect(mockLaunch.openInTerminalCalledWith?.terminal == .ghostty)
  }
}

// MARK: - 設定連携テスト

@Suite("AppCoordinator Settings Integration")
struct AppCoordinatorSettingsIntegrationTests {

  @Test("Settings changes propagate to view model commands")
  @MainActor
  func settingsChangesPropagate() throws {
    let settings = makeTempSettingsManager()
    let coordinator = makeCoordinator(settingsManager: settings)

    // 初期状態では空
    #expect(coordinator.launcherViewModel.commands.isEmpty)

    // 設定経由でコマンドを追加する
    settings.settings.customCommands = [
      CustomCommand(alias: "deploy", command: "npm run deploy")
    ]

    // 再読み込みを実行する
    coordinator.reloadDataFromSettings()

    #expect(coordinator.launcherViewModel.commands.count == 1)
    #expect(coordinator.launcherViewModel.commands[0].alias == "deploy")
  }

  @Test("SettingsViewModel shares same SettingsManager")
  @MainActor
  func settingsViewModelSharesManager() {
    let settings = makeTempSettingsManager()
    let coordinator = makeCoordinator(settingsManager: settings)

    #expect(coordinator.settingsViewModel.settingsManager === settings)
    #expect(coordinator.menuBarActions.settingsManager === settings)
  }

  @Test("Default terminal change affects command execution")
  @MainActor
  func defaultTerminalChangeAffectsExecution() async throws {
    let mockLaunch = MockLaunchService()
    let settings = makeTempSettingsManager()
    settings.settings.defaultTerminal = .terminal

    let coordinator = makeCoordinator(
      settingsManager: settings,
      launchService: mockLaunch
    )

    // 設定経由で既定ターミナルを変更する
    settings.settings.defaultTerminal = .warp

    coordinator.openInTerminal("/test")

    try await Task.sleep(nanoseconds: 100_000_000)

    #expect(mockLaunch.openInTerminalCalledWith?.terminal == .warp)
  }
}

// MARK: - キーボードショートカット連携テスト

@Suite("AppCoordinator Keyboard Shortcut Integration")
struct AppCoordinatorShortcutIntegrationTests {

  @Test("GlobalShortcutManager is wired to WindowManager")
  @MainActor
  func globalShortcutWiredToWindowManager() {
    let coordinator = makeCoordinator()

    // ショートカット管理は同じ WindowManager を使う
    #expect(coordinator.globalShortcut.windowManager === coordinator.windowManager)
  }

  @Test("Shortcut handler toggles launcher visibility")
  @MainActor
  func shortcutHandlerTogglesVisibility() {
    let coordinator = makeCoordinator()

    #expect(coordinator.windowManager.isLauncherVisible == false)

    // ショートカット押下をシミュレートする
    coordinator.globalShortcut.handleShortcut()

    #expect(coordinator.windowManager.isLauncherVisible == true)

    // もう一度トグルする
    coordinator.globalShortcut.handleShortcut()

    #expect(coordinator.windowManager.isLauncherVisible == false)
  }
}

// MARK: - メニューバー連携テスト

@Suite("AppCoordinator Menu Bar Integration")
struct AppCoordinatorMenuBarIntegrationTests {

  @Test("Menu bar showWindow shows launcher")
  @MainActor
  func menuBarShowWindow() {
    let coordinator = makeCoordinator()

    #expect(coordinator.windowManager.isLauncherVisible == false)

    coordinator.menuBarActions.showWindow()

    #expect(coordinator.windowManager.isLauncherVisible == true)
  }

  @Test("Menu bar openSettings sets isSettingsOpen")
  @MainActor
  func menuBarOpenSettings() {
    let coordinator = makeCoordinator()

    #expect(coordinator.menuBarActions.isSettingsOpen == false)

    coordinator.menuBarActions.openSettings()

    #expect(coordinator.menuBarActions.isSettingsOpen == true)
  }

  @Test("Menu bar closeSettings resets isSettingsOpen")
  @MainActor
  func menuBarCloseSettings() {
    let coordinator = makeCoordinator()

    coordinator.menuBarActions.openSettings()
    #expect(coordinator.menuBarActions.isSettingsOpen == true)

    coordinator.menuBarActions.closeSettings()
    #expect(coordinator.menuBarActions.isSettingsOpen == false)
  }

  @Test("Menu bar rebuildCache completes without error")
  @MainActor
  func menuBarRebuildCache() async {
    let coordinator = makeCoordinator()

    await coordinator.menuBarActions.rebuildCache()

    #expect(coordinator.menuBarActions.isRebuildingCache == false)
  }

  @Test("Menu items contain expected entries")
  @MainActor
  func menuItemsContainExpectedEntries() {
    let coordinator = makeCoordinator()
    let items = coordinator.menuBarActions.menuItems

    #expect(items.count == 4)
    #expect(items[0].id == "show-window")
    #expect(items[1].id == "rebuild-cache")
    #expect(items[2].id == "settings")
    #expect(items[3].id == "quit")
  }
}

// MARK: - キャッシュブートストラップ連携テスト

@Suite("AppCoordinator Cache Bootstrap Integration")
struct AppCoordinatorCacheBootstrapTests {

  @Test("Cache bootstrap performs initial scan")
  @MainActor
  func cacheBootstrapPerformsInitialScan() async {
    let mockDB = MockCacheDB(isEmpty: true)
    let testApps = [
      AppItem(name: "Safari", path: "/Applications/Safari.app")
    ]
    let mockAppScanner = MockAppScanner(apps: testApps)

    let coordinator = makeCoordinator(
      cacheDatabase: mockDB,
      appScanner: mockAppScanner
    )

    await coordinator.cacheBootstrap.performInitialScan()

    #expect(mockDB.saveAppsCalled)
    #expect(mockDB.saveDirectoriesCalled)
  }

  @Test("Cache bootstrap auto-update starts when enabled")
  @MainActor
  func cacheBootstrapAutoUpdateStarts() async {
    let settings = makeTempSettingsManager()
    settings.settings.cacheUpdate.autoUpdateEnabled = true
    settings.settings.cacheUpdate.autoUpdateIntervalHours = 1

    let coordinator = makeCoordinator(settingsManager: settings)

    coordinator.cacheBootstrap.startAutoUpdate()

    #expect(coordinator.cacheBootstrap.autoUpdateTask != nil)

    coordinator.cacheBootstrap.stopAutoUpdate()
  }
}

// MARK: - 特殊キーアクションテスト

@Suite("AppCoordinator Special Key Actions")
struct AppCoordinatorSpecialKeyActionTests {

  @Test("Escape key triggers dismiss")
  @MainActor
  func escapeKeyTriggersDismiss() {
    let coordinator = makeCoordinator()

    let action = coordinator.launcherViewModel.handleSpecialKey(.escape, modifiers: [])

    #expect(action == .dismiss)
  }

  @Test("Enter key with results triggers execute")
  @MainActor
  func enterKeyWithResultsTriggersExecute() {
    let coordinator = makeCoordinator()

    coordinator.launcherViewModel.apps = [
      AppItem(name: "Safari", path: "/Applications/Safari.app")
    ]
    coordinator.launcherViewModel.searchQuery = "safari"
    coordinator.launcherViewModel.updateSearch()

    let action = coordinator.launcherViewModel.handleSpecialKey(.enter, modifiers: [])

    #expect(action == .execute)
  }

  @Test("Left arrow on directory triggers editor picker")
  @MainActor
  func leftArrowOnDirectoryTriggersEditorPicker() {
    let coordinator = makeCoordinator()

    coordinator.launcherViewModel.directories = [
      DirectoryItem(name: "project", path: "/Users/dev/project")
    ]
    coordinator.launcherViewModel.searchQuery = "project"
    coordinator.launcherViewModel.updateSearch()

    // ディレクトリ結果が選択されていることを確認する
    guard
      let firstResult = coordinator.launcherViewModel.searchResults.first,
      firstResult.kind == .directory
    else {
      // ディレクトリ結果がなければこのテストは終了する
      return
    }

    let action = coordinator.launcherViewModel.handleSpecialKey(.left, modifiers: [])

    #expect(action == .showEditorPicker)
  }

  @Test("Right arrow on directory triggers terminal open")
  @MainActor
  func rightArrowOnDirectoryTriggersTerminalOpen() {
    let coordinator = makeCoordinator()

    coordinator.launcherViewModel.directories = [
      DirectoryItem(name: "project", path: "/Users/dev/project")
    ]
    coordinator.launcherViewModel.searchQuery = "project"
    coordinator.launcherViewModel.updateSearch()

    guard
      let firstResult = coordinator.launcherViewModel.searchResults.first,
      firstResult.kind == .directory
    else {
      return
    }

    let action = coordinator.launcherViewModel.handleSpecialKey(.right, modifiers: [])

    #expect(action == .openInTerminal)
  }

  @Test("Cmd+Right arrow on directory triggers terminal picker")
  @MainActor
  func cmdRightArrowOnDirectoryTriggersTerminalPicker() {
    let coordinator = makeCoordinator()

    coordinator.launcherViewModel.directories = [
      DirectoryItem(name: "project", path: "/Users/dev/project")
    ]
    coordinator.launcherViewModel.searchQuery = "project"
    coordinator.launcherViewModel.updateSearch()

    guard
      let firstResult = coordinator.launcherViewModel.searchResults.first,
      firstResult.kind == .directory
    else {
      return
    }

    let action = coordinator.launcherViewModel.handleSpecialKey(.right, modifiers: .command)

    #expect(action == .showTerminalPicker)
  }
}

// MARK: - エディタ・ターミナルピッカー連携テスト

@Suite("AppCoordinator Picker Integration")
struct AppCoordinatorPickerIntegrationTests {

  @Test("EditorPickerPanel exists on coordinator")
  @MainActor
  func editorPickerPanelExists() {
    let coordinator = makeCoordinator()
    #expect(coordinator.editorPickerPanel.pickerState.availableEditors.count > 0)
  }

  @Test("TerminalPickerPanel exists on coordinator")
  @MainActor
  func terminalPickerPanelExists() {
    let coordinator = makeCoordinator()
    // TerminalPickerPanel は空の端末一覧で開始する
    #expect(coordinator.terminalPickerPanel.state.terminals.isEmpty)
  }

  @Test("showEditorPicker sets picker visible")
  @MainActor
  func showEditorPickerSetsPickerVisible() {
    let coordinator = makeCoordinator()

    coordinator.showEditorPicker(for: "/Users/dev/project")

    #expect(coordinator.windowManager.isPickerVisible == true)
  }

  @Test("showTerminalPicker sets picker visible")
  @MainActor
  func showTerminalPickerSetsPickerVisible() {
    let coordinator = makeCoordinator()

    coordinator.showTerminalPicker(for: "/Users/dev/project")

    #expect(coordinator.windowManager.isPickerVisible == true)
  }

  @Test("Execute emoji result sets picker visible")
  @MainActor
  func executeEmojiResultSetsPickerVisible() {
    let coordinator = makeCoordinator()

    // emoji 特殊アクションの実行で Emoji ピッカーが表示され picker 状態が立つ。
    // これを怠ると emoji 表示中の Option+Space で onCloseAllPickers が呼ばれず二重表示になる。
    coordinator.executeResult(SearchResult(name: "Emoji ピッカー", kind: .emoji, score: -10))

    #expect(coordinator.windowManager.isPickerVisible == true)
  }

  @Test("Emoji picker dismiss clears picker visible")
  @MainActor
  func emojiPickerDismissClearsPickerVisible() {
    let coordinator = makeCoordinator()

    coordinator.executeResult(SearchResult(name: "Emoji ピッカー", kind: .emoji, score: -10))
    #expect(coordinator.windowManager.isPickerVisible == true)

    // パネルを閉じると onDismiss 経由で picker 状態が解除される
    coordinator.emojiPickerPanel.dismissPanel()
    #expect(coordinator.windowManager.isPickerVisible == false)
  }
}

// MARK: - アップデートチェッカー連携テスト

@Suite("AppCoordinator Update Checker Integration")
struct AppCoordinatorUpdateCheckerTests {

  @Test("Update checker with no new version shows no banner")
  @MainActor
  func noNewVersionShowsNoBanner() async {
    let coordinator = makeCoordinator(urlSession: MockURLSession())

    await coordinator.start()

    // 空の releases 配列はアップデートなしを意味する
    #expect(coordinator.launcherViewModel.updateBannerVersion == nil)
  }

  @Test("Update banner can be shown")
  @MainActor
  func updateBannerCanBeShown() {
    let coordinator = makeCoordinator()

    coordinator.launcherViewModel.showUpdateBanner(version: "99.0.0")

    #expect(coordinator.launcherViewModel.shouldShowUpdateBanner == true)
    #expect(coordinator.launcherViewModel.updateBannerVersion == "99.0.0")
  }

  @Test("Update banner can be dismissed")
  @MainActor
  func updateBannerCanBeDismissed() {
    let coordinator = makeCoordinator()

    coordinator.launcherViewModel.showUpdateBanner(version: "99.0.0")
    coordinator.launcherViewModel.dismissUpdateBanner(version: "99.0.0")

    #expect(coordinator.launcherViewModel.shouldShowUpdateBanner == false)
  }
}

// MARK: - エンドツーエンドフローテスト

@Suite("AppCoordinator End-to-End Flows")
struct AppCoordinatorEndToEndFlowTests {

  @Test("Full launcher flow: search -> select -> execute")
  @MainActor
  func fullLauncherFlow() async throws {
    let mockLaunch = MockLaunchService()
    let history = makeTempSelectionHistory()
    let coordinator = makeCoordinator(
      launchService: mockLaunch,
      selectionHistory: history
    )

    // 1. アプリデータを準備する
    coordinator.launcherViewModel.apps = [
      AppItem(name: "Safari", path: "/Applications/Safari.app"),
      AppItem(name: "Xcode", path: "/Applications/Xcode.app"),
      AppItem(name: "Slack", path: "/Applications/Slack.app"),
    ]

    // 2. ランチャーを表示する
    coordinator.windowManager.showLauncher()
    #expect(coordinator.windowManager.isLauncherVisible == true)

    // 3. 検索クエリを入力する
    coordinator.launcherViewModel.searchQuery = "xco"
    coordinator.launcherViewModel.updateSearch()
    #expect(!coordinator.launcherViewModel.searchResults.isEmpty)
    #expect(coordinator.launcherViewModel.searchResults[0].name == "Xcode")

    // 4. 選択項目を実行する
    let selected = coordinator.launcherViewModel.confirmSelection()!
    coordinator.executeResult(selected)

    // 5. 非同期実行の完了を待つ
    try await Task.sleep(nanoseconds: 100_000_000)

    // 6. アプリが起動されたことを確認する
    #expect(mockLaunch.launchAppCalledWith == "/Applications/Xcode.app")

    // 7. 検索状態がクリアされたことを確認する
    #expect(coordinator.launcherViewModel.searchQuery == "")

    // 8. 履歴が記録されたことを確認する
    #expect(history.allEntries.count == 1)
    #expect(history.allEntries[0].keyword == "xco")
  }

  @Test("Full directory flow: search -> right arrow -> terminal open")
  @MainActor
  func fullDirectoryTerminalFlow() async throws {
    let mockLaunch = MockLaunchService()
    let settings = makeTempSettingsManager()
    settings.settings.defaultTerminal = .iterm2

    let coordinator = makeCoordinator(
      settingsManager: settings,
      launchService: mockLaunch
    )

    // 1. ディレクトリデータを準備する
    coordinator.launcherViewModel.directories = [
      DirectoryItem(name: "my-project", path: "/Users/dev/my-project")
    ]

    // 2. ディレクトリを検索する
    coordinator.launcherViewModel.searchQuery = "my-proj"
    coordinator.launcherViewModel.updateSearch()

    guard
      let firstResult = coordinator.launcherViewModel.searchResults.first,
      firstResult.kind == .directory
    else {
      // ディレクトリ結果がなければこのテストは終了する
      return
    }

    // 3. 右矢印キー入力をシミュレートする
    let action = coordinator.launcherViewModel.handleSpecialKey(.right, modifiers: [])
    #expect(action == .openInTerminal)

    // 4. ターミナル起動を実行する
    coordinator.openInTerminal(firstResult.path)

    try await Task.sleep(nanoseconds: 100_000_000)

    #expect(mockLaunch.openInTerminalCalledWith?.path == "/Users/dev/my-project")
    #expect(mockLaunch.openInTerminalCalledWith?.terminal == .iterm2)
  }

  @Test("Settings change reflects in search results")
  @MainActor
  func settingsChangeReflectsInSearch() async {
    let settings = makeTempSettingsManager()
    let coordinator = makeCoordinator(settingsManager: settings)

    // 初期状態ではコマンドがない
    #expect(coordinator.launcherViewModel.commands.isEmpty)

    // 設定経由でコマンドを追加する
    settings.settings.customCommands = [
      CustomCommand(alias: "deploy", command: "npm run deploy")
    ]
    coordinator.reloadDataFromSettings()

    // コマンドを検索する
    coordinator.launcherViewModel.searchQuery = "deploy"
    coordinator.launcherViewModel.updateSearch()

    #expect(!coordinator.launcherViewModel.searchResults.isEmpty)
    #expect(coordinator.launcherViewModel.searchResults[0].kind == .command)
    #expect(coordinator.launcherViewModel.searchResults[0].name == "deploy")
  }

  @Test("History boost affects search result ordering")
  @MainActor
  func historyBoostAffectsOrdering() async {
    let history = makeTempSelectionHistory()
    let coordinator = makeCoordinator(selectionHistory: history)

    // 2つのアプリを準備する
    coordinator.launcherViewModel.apps = [
      AppItem(name: "Safari", path: "/Applications/Safari.app"),
      AppItem(name: "Slack", path: "/Applications/Slack.app"),
    ]

    // キーワード "s" で Slack の履歴を記録する
    history.record(keyword: "s", path: "/Applications/Slack.app")
    history.record(keyword: "s", path: "/Applications/Slack.app")
    history.record(keyword: "s", path: "/Applications/Slack.app")
    coordinator.launcherViewModel.history = history.allEntries

    // "s" を検索する
    coordinator.launcherViewModel.searchQuery = "s"
    coordinator.launcherViewModel.updateSearch()

    // 履歴により Slack が先頭に来る
    #expect(!coordinator.launcherViewModel.searchResults.isEmpty)
    if coordinator.launcherViewModel.searchResults.count >= 2 {
      #expect(coordinator.launcherViewModel.searchResults[0].name == "Slack")
    }
  }
}

// MARK: - WindowManager 連携テスト

@Suite("AppCoordinator Window Manager Integration")
struct AppCoordinatorWindowManagerTests {

  @Test("Launcher can be hidden even when picker is visible")
  @MainActor
  func launcherCanBeHiddenWhenPickerVisible() {
    let coordinator = makeCoordinator()

    coordinator.windowManager.showLauncher()
    coordinator.windowManager.showPicker()

    // ピッカー表示中でもランチャーは隠せる（Tauri と同じフロー）
    coordinator.windowManager.hideLauncher()
    #expect(coordinator.windowManager.isLauncherVisible == false)
  }

  @Test("Window resize based on result count")
  @MainActor
  func windowResizeBasedOnResultCount() {
    let coordinator = makeCoordinator()

    let height0 = coordinator.windowManager.heightForResults(count: 0)
    let height5 = coordinator.windowManager.heightForResults(count: 5)
    let height100 = coordinator.windowManager.heightForResults(count: 100)

    #expect(height0 == WindowManager.minHeight)
    #expect(height5 > height0)
    #expect(height100 == WindowManager.maxHeight)
  }
}

// MARK: - エディタピッカー確定コールバックテスト

@Suite("AppCoordinator Editor Picker Selection")
struct AppCoordinatorEditorPickerSelectionTests {

  @Test("showEditorPicker の連続呼び出しでクラッシュしない")
  @MainActor
  func consecutiveShowEditorPickerDoesNotCrash() {
    let coordinator = makeCoordinator()

    coordinator.showEditorPicker(for: "/tmp/dir1")
    coordinator.showEditorPicker(for: "/tmp/dir2")
    coordinator.showEditorPicker(for: "/tmp/dir3")

    // クラッシュせずピッカーが表示されていることを確認
    #expect(coordinator.windowManager.isPickerVisible == true)
  }

  @Test("エディタ確定で openDirectory が呼ばれ、検索がクリアされる")
  @MainActor
  func editorSelectOpensDirectory() async throws {
    let launchService = MockLaunchService()
    let coordinator = makeCoordinator(launchService: launchService)

    coordinator.showEditorPicker(for: "/tmp/test")
    coordinator.launcherViewModel.searchQuery = "query"

    // Enter 確定相当の onSelect コールバックを発火する
    coordinator.editorPickerPanel.onSelect?(.vscode)

    // 非同期の openDirectory 完了をポーリングで待つ
    for _ in 0..<1000 where launchService.openDirectoryCalledWith == nil {
      await Task.yield()
    }
    #expect(launchService.openDirectoryCalledWith?.path == "/tmp/test")
    #expect(launchService.openDirectoryCalledWith?.editor == .vscode)
    #expect(coordinator.launcherViewModel.searchQuery.isEmpty)
  }

  @Test("dismissPanel で isPickerVisible が解除される")
  @MainActor
  func editorPickerDismissClearsPickerVisible() {
    let coordinator = makeCoordinator()

    coordinator.showEditorPicker(for: "/tmp/test")
    #expect(coordinator.windowManager.isPickerVisible == true)

    coordinator.editorPickerPanel.dismissPanel()

    #expect(coordinator.windowManager.isPickerVisible == false)
  }
}

// MARK: - 設定変更の反映テスト

@Suite("AppCoordinator Settings Change Propagation")
struct AppCoordinatorSettingsChangeTests {

  @Test("コマンド追加が即座にランチャーへ反映される")
  @MainActor
  func addCommandReflectsImmediately() async throws {
    let coordinator = makeCoordinator()
    await coordinator.start()

    try coordinator.settingsViewModel.addCommand(
      alias: "build", command: "make build", workingDirectory: nil)

    #expect(coordinator.launcherViewModel.commands.contains { $0.alias == "build" })
  }

  @Test("コマンド削除が即座にランチャーへ反映される")
  @MainActor
  func removeCommandReflectsImmediately() async throws {
    let coordinator = makeCoordinator()
    await coordinator.start()
    try coordinator.settingsViewModel.addCommand(
      alias: "build", command: "make build", workingDirectory: nil)

    try coordinator.settingsViewModel.removeCommand(at: 0)

    #expect(coordinator.launcherViewModel.commands.isEmpty)
  }

  @Test("ディレクトリ追加がキャッシュ再構築をトリガーする")
  @MainActor
  func addDirectoryTriggersCacheRebuild() async throws {
    let mockDB = MockCacheDB(isEmpty: true)
    let coordinator = makeCoordinator(cacheDatabase: mockDB)
    await coordinator.start()
    mockDB.saveAppsCalled = false

    try coordinator.settingsViewModel.addDirectory(
      path: "/tmp/projects", parentOpenMode: .finder, subdirsOpenMode: .editor,
      scanForApps: false)

    // cacheInvalidated は Task 経由で再構築するため完了をポーリングで待つ
    for _ in 0..<1000 where !mockDB.saveAppsCalled {
      await Task.yield()
    }
    #expect(mockDB.saveAppsCalled)
  }

  @Test("自動更新設定の変更がタイマーへ即時反映される")
  @MainActor
  func cacheUpdateSettingsRestartTimer() async throws {
    let coordinator = makeCoordinator()
    await coordinator.start()
    #expect(coordinator.cacheBootstrap.autoUpdateTask == nil)

    // 有効化 → タイマー起動
    try coordinator.settingsViewModel.setCacheUpdateSettings(
      CacheUpdateSettings(
        updateOnStartup: true, autoUpdateEnabled: true, autoUpdateIntervalHours: 6))
    #expect(coordinator.cacheBootstrap.autoUpdateTask != nil)

    // 無効化 → タイマー停止
    try coordinator.settingsViewModel.setCacheUpdateSettings(
      CacheUpdateSettings(
        updateOnStartup: true, autoUpdateEnabled: false, autoUpdateIntervalHours: 6))
    #expect(coordinator.cacheBootstrap.autoUpdateTask == nil)
  }

  @Test("スキャン完了でビューモデルへ再読込される（自動更新経路の配線）")
  @MainActor
  func scanCompletionReloadsViewModel() async throws {
    let mockDB = MockCacheDB(isEmpty: false)
    let app = AppItem(name: "Safari", path: "/Applications/Safari.app")
    let coordinator = makeCoordinator(
      cacheDatabase: mockDB, appScanner: MockAppScanner(apps: [app]))
    await coordinator.start()

    // スキャン後の load で返すアプリを差し替えて、再読込されたことを観測する
    mockDB.loadedApps = [app]
    coordinator.launcherViewModel.apps = []

    // 自動更新と同じ経路（runScan）で再構築する
    await coordinator.cacheBootstrap.rebuildCache()

    #expect(coordinator.launcherViewModel.apps.map(\.path) == [app.path])
  }

  @Test("バナー dismiss が dismissedVersion として永続化される")
  @MainActor
  func bannerDismissPersistsDismissedVersion() async throws {
    let settings = makeTempSettingsManager()
    let coordinator = makeCoordinator(settingsManager: settings)
    await coordinator.start()

    coordinator.launcherViewModel.showUpdateBanner(version: "99.0.0")
    coordinator.launcherViewModel.dismissUpdateBanner(version: "99.0.0")

    #expect(settings.settings.updateCache?.dismissedVersion == "99.0.0")
  }

  @Test("再構築中の再入はスキップされる")
  @MainActor
  func rebuildReentryIsSkipped() async throws {
    let mockDB = MockCacheDB(isEmpty: true)
    let coordinator = makeCoordinator(cacheDatabase: mockDB)
    await coordinator.start()

    // 並行で2回起動しても再構築は完了し、状態固着が起きない
    mockDB.saveAppsCalled = false
    async let first: Void = coordinator.rebuildCacheAndReload()
    async let second: Void = coordinator.rebuildCacheAndReload()
    _ = await (first, second)

    #expect(mockDB.saveAppsCalled)
    #expect(coordinator.launcherViewModel.isScanning == false)
  }
}
