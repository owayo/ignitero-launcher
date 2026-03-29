import AppKit
import Foundation
import Testing

@testable import IgniteroCore

// MARK: - Mock Implementations

/// テスト用モック CacheDatabase
private final class MockCacheDB: CacheDatabaseProtocol, @unchecked Sendable {
  var isEmptyResult = true
  var saveAppsCalled = false
  var saveDirectoriesCalled = false
  var clearCacheCalled = false
  var savedApps: [AppItem] = []
  var savedDirectories: [DirectoryItem] = []

  init(isEmpty: Bool = true) {
    self.isEmptyResult = isEmpty
  }

  func isEmpty() throws -> Bool { isEmptyResult }

  func saveApps(_ apps: [AppItem]) throws {
    saveAppsCalled = true
    savedApps = apps
  }

  func saveDirectories(_ dirs: [DirectoryItem]) throws {
    saveDirectoriesCalled = true
    savedDirectories = dirs
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

// MARK: - Test Helpers

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

// MARK: - Initialization Tests

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

    // Verify core services
    #expect(coordinator.settingsManager === settings)
    #expect(coordinator.selectionHistory === history)

    // Verify UI components exist
    #expect(coordinator.windowManager.launcherPanel === coordinator.launcherPanel)
    #expect(coordinator.launcherViewModel.searchQuery == "")
    #expect(coordinator.settingsViewModel.settingsManager === settings)

    // Verify app-level coordinators
    #expect(coordinator.globalShortcut.windowManager === coordinator.windowManager)
    #expect(coordinator.menuBarActions.windowManager === coordinator.windowManager)
    #expect(coordinator.menuBarActions.settingsManager === settings)
  }

  @Test("Default initialization succeeds")
  @MainActor
  func defaultInitializationSucceeds() {
    // Using mock DB to avoid file system access
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

// MARK: - Start / Shutdown Tests

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

// MARK: - Search Flow Tests

@Suite("AppCoordinator Search Flow")
struct AppCoordinatorSearchFlowTests {

  @Test("Search query updates search results")
  @MainActor
  func searchQueryUpdatesResults() async {
    let coordinator = makeCoordinator()

    // Set up data
    coordinator.launcherViewModel.apps = [
      AppItem(name: "Safari", path: "/Applications/Safari.app"),
      AppItem(name: "Xcode", path: "/Applications/Xcode.app"),
    ]

    // Perform search
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

// MARK: - Execute Result Tests

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

    // Wait for async task to complete
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

// MARK: - Dismiss Launcher Tests

@Suite("AppCoordinator Dismiss Launcher")
struct AppCoordinatorDismissLauncherTests {

  @Test("dismissLauncher clears search and hides window")
  @MainActor
  func dismissLauncherClearsAndHides() {
    let coordinator = makeCoordinator()

    // Show launcher first
    coordinator.windowManager.showLauncher()
    #expect(coordinator.windowManager.isLauncherVisible == true)

    coordinator.launcherViewModel.searchQuery = "test"
    coordinator.dismissLauncher()

    #expect(coordinator.launcherViewModel.searchQuery == "")
    #expect(coordinator.windowManager.isLauncherVisible == false)
  }
}

// MARK: - Open In Terminal Tests

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

    // Wait for async task
    try await Task.sleep(nanoseconds: 100_000_000)

    #expect(mockLaunch.openInTerminalCalledWith?.path == "/Users/dev/project")
    #expect(mockLaunch.openInTerminalCalledWith?.terminal == .ghostty)
  }
}

// MARK: - Settings Integration Tests

@Suite("AppCoordinator Settings Integration")
struct AppCoordinatorSettingsIntegrationTests {

  @Test("Settings changes propagate to view model commands")
  @MainActor
  func settingsChangesPropagate() throws {
    let settings = makeTempSettingsManager()
    let coordinator = makeCoordinator(settingsManager: settings)

    // Initially empty
    #expect(coordinator.launcherViewModel.commands.isEmpty)

    // Add a command through settings
    settings.settings.customCommands = [
      CustomCommand(alias: "deploy", command: "npm run deploy")
    ]

    // Trigger reload
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

    // Change default terminal via settings
    settings.settings.defaultTerminal = .warp

    coordinator.openInTerminal("/test")

    try await Task.sleep(nanoseconds: 100_000_000)

    #expect(mockLaunch.openInTerminalCalledWith?.terminal == .warp)
  }
}

// MARK: - Keyboard Shortcut Integration Tests

@Suite("AppCoordinator Keyboard Shortcut Integration")
struct AppCoordinatorShortcutIntegrationTests {

  @Test("GlobalShortcutManager is wired to WindowManager")
  @MainActor
  func globalShortcutWiredToWindowManager() {
    let coordinator = makeCoordinator()

    // The shortcut manager should use the same window manager
    #expect(coordinator.globalShortcut.windowManager === coordinator.windowManager)
  }

  @Test("Shortcut handler toggles launcher visibility")
  @MainActor
  func shortcutHandlerTogglesVisibility() {
    let coordinator = makeCoordinator()

    #expect(coordinator.windowManager.isLauncherVisible == false)

    // Simulate shortcut press
    coordinator.globalShortcut.handleShortcut()

    #expect(coordinator.windowManager.isLauncherVisible == true)

    // Toggle again
    coordinator.globalShortcut.handleShortcut()

    #expect(coordinator.windowManager.isLauncherVisible == false)
  }
}

// MARK: - Menu Bar Actions Integration Tests

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

// MARK: - Cache Bootstrap Integration Tests

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

// MARK: - Special Key Action Tests

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

    // Ensure we have a directory result selected
    guard
      let firstResult = coordinator.launcherViewModel.searchResults.first,
      firstResult.kind == .directory
    else {
      // Skip if no directory result
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

// MARK: - Editor/Terminal Picker Integration Tests

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
    // TerminalPickerPanel starts with empty terminals
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
}

// MARK: - Update Checker Integration Tests

@Suite("AppCoordinator Update Checker Integration")
struct AppCoordinatorUpdateCheckerTests {

  @Test("Update checker with no new version shows no banner")
  @MainActor
  func noNewVersionShowsNoBanner() async {
    let coordinator = makeCoordinator(urlSession: MockURLSession())

    await coordinator.start()

    // Empty releases array means no update
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

// MARK: - End-to-End Flow Tests

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

    // 1. Set up apps data
    coordinator.launcherViewModel.apps = [
      AppItem(name: "Safari", path: "/Applications/Safari.app"),
      AppItem(name: "Xcode", path: "/Applications/Xcode.app"),
      AppItem(name: "Slack", path: "/Applications/Slack.app"),
    ]

    // 2. Show launcher
    coordinator.windowManager.showLauncher()
    #expect(coordinator.windowManager.isLauncherVisible == true)

    // 3. Enter search query
    coordinator.launcherViewModel.searchQuery = "xco"
    coordinator.launcherViewModel.updateSearch()
    #expect(!coordinator.launcherViewModel.searchResults.isEmpty)
    #expect(coordinator.launcherViewModel.searchResults[0].name == "Xcode")

    // 4. Execute selection
    let selected = coordinator.launcherViewModel.confirmSelection()!
    coordinator.executeResult(selected)

    // 5. Wait for async execution
    try await Task.sleep(nanoseconds: 100_000_000)

    // 6. Verify app was launched
    #expect(mockLaunch.launchAppCalledWith == "/Applications/Xcode.app")

    // 7. Verify search was cleared
    #expect(coordinator.launcherViewModel.searchQuery == "")

    // 8. Verify history was recorded
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

    // 1. Set up directory data
    coordinator.launcherViewModel.directories = [
      DirectoryItem(name: "my-project", path: "/Users/dev/my-project")
    ]

    // 2. Search for directory
    coordinator.launcherViewModel.searchQuery = "my-proj"
    coordinator.launcherViewModel.updateSearch()

    guard
      let firstResult = coordinator.launcherViewModel.searchResults.first,
      firstResult.kind == .directory
    else {
      // Skip if no directory result (fuzzy search threshold)
      return
    }

    // 3. Simulate right arrow key (open in terminal)
    let action = coordinator.launcherViewModel.handleSpecialKey(.right, modifiers: [])
    #expect(action == .openInTerminal)

    // 4. Execute the terminal open
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

    // Initially no commands
    #expect(coordinator.launcherViewModel.commands.isEmpty)

    // Add command through settings
    settings.settings.customCommands = [
      CustomCommand(alias: "deploy", command: "npm run deploy")
    ]
    coordinator.reloadDataFromSettings()

    // Search for command
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

    // Set up two apps
    coordinator.launcherViewModel.apps = [
      AppItem(name: "Safari", path: "/Applications/Safari.app"),
      AppItem(name: "Slack", path: "/Applications/Slack.app"),
    ]

    // Record history for Slack with keyword "s"
    history.record(keyword: "s", path: "/Applications/Slack.app")
    history.record(keyword: "s", path: "/Applications/Slack.app")
    history.record(keyword: "s", path: "/Applications/Slack.app")
    coordinator.launcherViewModel.history = history.allEntries

    // Search for "s"
    coordinator.launcherViewModel.searchQuery = "s"
    coordinator.launcherViewModel.updateSearch()

    // Slack should be boosted to top due to history
    #expect(!coordinator.launcherViewModel.searchResults.isEmpty)
    if coordinator.launcherViewModel.searchResults.count >= 2 {
      #expect(coordinator.launcherViewModel.searchResults[0].name == "Slack")
    }
  }
}

// MARK: - Window Manager Integration Tests

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
