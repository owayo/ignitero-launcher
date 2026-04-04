import Foundation
import Testing

@testable import IgniteroCore

// MARK: - Test Helpers

@MainActor
private func makeTempSettingsManager() throws -> SettingsManager {
  let dir = FileManager.default.temporaryDirectory
    .appendingPathComponent("ignitero-settings-vm-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  return SettingsManager(configDirectory: dir)
}

// MARK: - SettingsTab Tests

@Suite("SettingsTab Enum")
struct SettingsTabTests {

  @Test func allCasesExist() {
    let cases = SettingsTab.allCases
    #expect(cases.count == 4)
    #expect(cases.contains(.general))
    #expect(cases.contains(.directories))
    #expect(cases.contains(.commands))
    #expect(cases.contains(.excludedApps))
  }

  @Test func rawValues() {
    #expect(SettingsTab.general.rawValue == "general")
    #expect(SettingsTab.directories.rawValue == "directories")
    #expect(SettingsTab.commands.rawValue == "commands")
    #expect(SettingsTab.excludedApps.rawValue == "excludedApps")
  }
}

// MARK: - SettingsViewModel Initial State Tests

@Suite("SettingsViewModel Initial State")
@MainActor
struct SettingsViewModelInitialStateTests {

  @MainActor
  @Test func initialTabIsGeneral() throws {
    let manager = try makeTempSettingsManager()
    let vm = SettingsViewModel(settingsManager: manager)
    #expect(vm.selectedTab == .general)
  }

  @MainActor
  @Test func initialAllAppsIsEmpty() throws {
    let manager = try makeTempSettingsManager()
    let vm = SettingsViewModel(settingsManager: manager)
    #expect(vm.allApps.isEmpty)
  }

  @MainActor
  @Test func settingsProxiesToSettingsManager() throws {
    let manager = try makeTempSettingsManager()
    manager.settings.defaultTerminal = .ghostty
    let vm = SettingsViewModel(settingsManager: manager)
    #expect(vm.settings.defaultTerminal == .ghostty)
  }

  @MainActor
  @Test func versionReturnsIgniteroVersion() throws {
    let manager = try makeTempSettingsManager()
    let vm = SettingsViewModel(settingsManager: manager)
    #expect(vm.version == Ignitero.version)
  }
}

// MARK: - Tab Selection Tests

@Suite("SettingsViewModel Tab Selection")
@MainActor
struct SettingsViewModelTabSelectionTests {

  @MainActor
  @Test func selectDirectoriesTab() throws {
    let manager = try makeTempSettingsManager()
    let vm = SettingsViewModel(settingsManager: manager)
    vm.selectedTab = .directories
    #expect(vm.selectedTab == .directories)
  }

  @MainActor
  @Test func selectCommandsTab() throws {
    let manager = try makeTempSettingsManager()
    let vm = SettingsViewModel(settingsManager: manager)
    vm.selectedTab = .commands
    #expect(vm.selectedTab == .commands)
  }

  @MainActor
  @Test func selectExcludedAppsTab() throws {
    let manager = try makeTempSettingsManager()
    let vm = SettingsViewModel(settingsManager: manager)
    vm.selectedTab = .excludedApps
    #expect(vm.selectedTab == .excludedApps)
  }

  @MainActor
  @Test func selectGeneralTab() throws {
    let manager = try makeTempSettingsManager()
    let vm = SettingsViewModel(settingsManager: manager)
    vm.selectedTab = .commands
    vm.selectedTab = .general
    #expect(vm.selectedTab == .general)
  }
}

// MARK: - Default Terminal Tests

@Suite("SettingsViewModel Default Terminal")
@MainActor
struct SettingsViewModelDefaultTerminalTests {

  @MainActor
  @Test func setDefaultTerminalToGhostty() throws {
    let manager = try makeTempSettingsManager()
    let vm = SettingsViewModel(settingsManager: manager)
    try vm.setDefaultTerminal(.ghostty)
    #expect(vm.settings.defaultTerminal == .ghostty)
    #expect(manager.settings.defaultTerminal == .ghostty)
  }

  @MainActor
  @Test func setDefaultTerminalToIterm2() throws {
    let manager = try makeTempSettingsManager()
    let vm = SettingsViewModel(settingsManager: manager)
    try vm.setDefaultTerminal(.iterm2)
    #expect(vm.settings.defaultTerminal == .iterm2)
  }

  @MainActor
  @Test func setDefaultTerminalToWarp() throws {
    let manager = try makeTempSettingsManager()
    let vm = SettingsViewModel(settingsManager: manager)
    try vm.setDefaultTerminal(.warp)
    #expect(vm.settings.defaultTerminal == .warp)
  }

  @MainActor
  @Test func setDefaultTerminalPersists() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("ignitero-settings-vm-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let manager = SettingsManager(configDirectory: dir)
    let vm = SettingsViewModel(settingsManager: manager)
    try vm.setDefaultTerminal(.warp)

    // Reload in new manager to verify persistence
    let manager2 = SettingsManager(configDirectory: dir)
    try manager2.load()
    #expect(manager2.settings.defaultTerminal == .warp)
  }
}

// MARK: - Cache Update Settings Tests

@Suite("SettingsViewModel Cache Update Settings")
@MainActor
struct SettingsViewModelCacheUpdateTests {

  @MainActor
  @Test func setCacheUpdateSettings() throws {
    let manager = try makeTempSettingsManager()
    let vm = SettingsViewModel(settingsManager: manager)

    let newSettings = CacheUpdateSettings(
      updateOnStartup: false,
      autoUpdateEnabled: true,
      autoUpdateIntervalHours: 12
    )
    try vm.setCacheUpdateSettings(newSettings)

    #expect(vm.settings.cacheUpdate.updateOnStartup == false)
    #expect(vm.settings.cacheUpdate.autoUpdateEnabled == true)
    #expect(vm.settings.cacheUpdate.autoUpdateIntervalHours == 12)
    #expect(manager.settings.cacheUpdate == newSettings)
  }

  @MainActor
  @Test func setCacheUpdateSettingsCallsOnSettingsChanged() throws {
    let manager = try makeTempSettingsManager()
    let vm = SettingsViewModel(settingsManager: manager)

    var callbackCount = 0
    vm.onSettingsChanged = { callbackCount += 1 }

    let newSettings = CacheUpdateSettings(
      updateOnStartup: false,
      autoUpdateEnabled: true,
      autoUpdateIntervalHours: 6
    )
    try vm.setCacheUpdateSettings(newSettings)

    #expect(callbackCount == 1)
  }

  @MainActor
  @Test func setCacheUpdateSettingsPersists() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("ignitero-settings-vm-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let manager = SettingsManager(configDirectory: dir)
    let vm = SettingsViewModel(settingsManager: manager)

    let newSettings = CacheUpdateSettings(
      updateOnStartup: false,
      autoUpdateEnabled: true,
      autoUpdateIntervalHours: 24
    )
    try vm.setCacheUpdateSettings(newSettings)

    let manager2 = SettingsManager(configDirectory: dir)
    try manager2.load()
    #expect(manager2.settings.cacheUpdate == newSettings)
  }
}

// MARK: - Directory Management Tests

@Suite("SettingsViewModel Directory Management")
@MainActor
struct SettingsViewModelDirectoryTests {

  @MainActor
  @Test func addDirectory() throws {
    let manager = try makeTempSettingsManager()
    let vm = SettingsViewModel(settingsManager: manager)

    try vm.addDirectory(
      path: "/Users/test/projects",
      parentOpenMode: .editor,
      subdirsOpenMode: .editor,
      scanForApps: false
    )

    #expect(vm.settings.registeredDirectories.count == 1)
    #expect(vm.settings.registeredDirectories[0].path == "/Users/test/projects")
    #expect(vm.settings.registeredDirectories[0].parentOpenMode == .editor)
    #expect(vm.settings.registeredDirectories[0].subdirsOpenMode == .editor)
    #expect(vm.settings.registeredDirectories[0].scanForApps == false)
  }

  @MainActor
  @Test func addMultipleDirectories() throws {
    let manager = try makeTempSettingsManager()
    let vm = SettingsViewModel(settingsManager: manager)

    try vm.addDirectory(
      path: "/path/a", parentOpenMode: .editor, subdirsOpenMode: .editor, scanForApps: false)
    try vm.addDirectory(
      path: "/path/b", parentOpenMode: .finder, subdirsOpenMode: .none, scanForApps: true)

    #expect(vm.settings.registeredDirectories.count == 2)
    #expect(vm.settings.registeredDirectories[0].path == "/path/a")
    #expect(vm.settings.registeredDirectories[1].path == "/path/b")
  }

  @MainActor
  @Test func removeDirectoryAtIndex() throws {
    let manager = try makeTempSettingsManager()
    let vm = SettingsViewModel(settingsManager: manager)

    try vm.addDirectory(
      path: "/path/a", parentOpenMode: .editor, subdirsOpenMode: .editor, scanForApps: false)
    try vm.addDirectory(
      path: "/path/b", parentOpenMode: .finder, subdirsOpenMode: .none, scanForApps: true)
    try vm.addDirectory(
      path: "/path/c", parentOpenMode: .none, subdirsOpenMode: .finder, scanForApps: false)

    #expect(vm.settings.registeredDirectories.count == 3)

    try vm.removeDirectory(at: 1)

    #expect(vm.settings.registeredDirectories.count == 2)
    #expect(vm.settings.registeredDirectories[0].path == "/path/a")
    #expect(vm.settings.registeredDirectories[1].path == "/path/c")
  }

  @MainActor
  @Test func removeDirectoryAtFirstIndex() throws {
    let manager = try makeTempSettingsManager()
    let vm = SettingsViewModel(settingsManager: manager)

    try vm.addDirectory(
      path: "/path/a", parentOpenMode: .editor, subdirsOpenMode: .editor, scanForApps: false)
    try vm.addDirectory(
      path: "/path/b", parentOpenMode: .finder, subdirsOpenMode: .none, scanForApps: true)

    try vm.removeDirectory(at: 0)

    #expect(vm.settings.registeredDirectories.count == 1)
    #expect(vm.settings.registeredDirectories[0].path == "/path/b")
  }

  @MainActor
  @Test func removeDirectoryAtLastIndex() throws {
    let manager = try makeTempSettingsManager()
    let vm = SettingsViewModel(settingsManager: manager)

    try vm.addDirectory(
      path: "/path/a", parentOpenMode: .editor, subdirsOpenMode: .editor, scanForApps: false)
    try vm.addDirectory(
      path: "/path/b", parentOpenMode: .finder, subdirsOpenMode: .none, scanForApps: true)

    try vm.removeDirectory(at: 1)

    #expect(vm.settings.registeredDirectories.count == 1)
    #expect(vm.settings.registeredDirectories[0].path == "/path/a")
  }

  @MainActor
  @Test func updateDirectoryAtIndex() throws {
    let manager = try makeTempSettingsManager()
    let vm = SettingsViewModel(settingsManager: manager)

    try vm.addDirectory(
      path: "/path/original", parentOpenMode: .none, subdirsOpenMode: .none, scanForApps: false)

    var updated = vm.settings.registeredDirectories[0]
    updated.parentOpenMode = .editor
    updated.parentEditor = "cursor"
    updated.subdirsOpenMode = .editor
    updated.subdirsEditor = "cursor"
    updated.scanForApps = true

    try vm.updateDirectory(at: 0, updated)

    #expect(vm.settings.registeredDirectories[0].path == "/path/original")
    #expect(vm.settings.registeredDirectories[0].parentOpenMode == .editor)
    #expect(vm.settings.registeredDirectories[0].parentEditor == "cursor")
    #expect(vm.settings.registeredDirectories[0].subdirsOpenMode == .editor)
    #expect(vm.settings.registeredDirectories[0].subdirsEditor == "cursor")
    #expect(vm.settings.registeredDirectories[0].scanForApps == true)
  }

  @MainActor
  @Test func updateDirectoryPreservesOthers() throws {
    let manager = try makeTempSettingsManager()
    let vm = SettingsViewModel(settingsManager: manager)

    try vm.addDirectory(
      path: "/path/a", parentOpenMode: .none, subdirsOpenMode: .none, scanForApps: false)
    try vm.addDirectory(
      path: "/path/b", parentOpenMode: .finder, subdirsOpenMode: .finder, scanForApps: true)

    var updated = vm.settings.registeredDirectories[0]
    updated.parentOpenMode = .editor
    try vm.updateDirectory(at: 0, updated)

    // First directory updated
    #expect(vm.settings.registeredDirectories[0].parentOpenMode == .editor)
    // Second directory unchanged
    #expect(vm.settings.registeredDirectories[1].path == "/path/b")
    #expect(vm.settings.registeredDirectories[1].parentOpenMode == .finder)
  }

  @MainActor
  @Test func addDirectoryPersists() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("ignitero-settings-vm-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let manager = SettingsManager(configDirectory: dir)
    let vm = SettingsViewModel(settingsManager: manager)
    try vm.addDirectory(
      path: "/persist/test", parentOpenMode: .editor, subdirsOpenMode: .none, scanForApps: true)

    let manager2 = SettingsManager(configDirectory: dir)
    try manager2.load()
    #expect(manager2.settings.registeredDirectories.count == 1)
    #expect(manager2.settings.registeredDirectories[0].path == "/persist/test")
  }
}

// MARK: - Command Management Tests

@Suite("SettingsViewModel Command Management")
@MainActor
struct SettingsViewModelCommandTests {

  @MainActor
  @Test func addCommand() throws {
    let manager = try makeTempSettingsManager()
    let vm = SettingsViewModel(settingsManager: manager)

    try vm.addCommand(alias: "dev", command: "npm run dev", workingDirectory: "/Users/test/app")

    #expect(vm.settings.customCommands.count == 1)
    #expect(vm.settings.customCommands[0].alias == "dev")
    #expect(vm.settings.customCommands[0].command == "npm run dev")
    #expect(vm.settings.customCommands[0].workingDirectory == "/Users/test/app")
  }

  @MainActor
  @Test func addCommandWithoutWorkingDirectory() throws {
    let manager = try makeTempSettingsManager()
    let vm = SettingsViewModel(settingsManager: manager)

    try vm.addCommand(alias: "hello", command: "echo hello", workingDirectory: nil)

    #expect(vm.settings.customCommands.count == 1)
    #expect(vm.settings.customCommands[0].workingDirectory == nil)
  }

  @MainActor
  @Test func addMultipleCommands() throws {
    let manager = try makeTempSettingsManager()
    let vm = SettingsViewModel(settingsManager: manager)

    try vm.addCommand(alias: "a", command: "cmd-a", workingDirectory: nil)
    try vm.addCommand(alias: "b", command: "cmd-b", workingDirectory: "/tmp")

    #expect(vm.settings.customCommands.count == 2)
    #expect(vm.settings.customCommands[0].alias == "a")
    #expect(vm.settings.customCommands[1].alias == "b")
  }

  @MainActor
  @Test func removeCommandAtIndex() throws {
    let manager = try makeTempSettingsManager()
    let vm = SettingsViewModel(settingsManager: manager)

    try vm.addCommand(alias: "a", command: "cmd-a", workingDirectory: nil)
    try vm.addCommand(alias: "b", command: "cmd-b", workingDirectory: nil)
    try vm.addCommand(alias: "c", command: "cmd-c", workingDirectory: nil)

    try vm.removeCommand(at: 1)

    #expect(vm.settings.customCommands.count == 2)
    #expect(vm.settings.customCommands[0].alias == "a")
    #expect(vm.settings.customCommands[1].alias == "c")
  }

  @MainActor
  @Test func removeCommandAtFirstIndex() throws {
    let manager = try makeTempSettingsManager()
    let vm = SettingsViewModel(settingsManager: manager)

    try vm.addCommand(alias: "a", command: "cmd-a", workingDirectory: nil)
    try vm.addCommand(alias: "b", command: "cmd-b", workingDirectory: nil)

    try vm.removeCommand(at: 0)

    #expect(vm.settings.customCommands.count == 1)
    #expect(vm.settings.customCommands[0].alias == "b")
  }

  @MainActor
  @Test func updateCommandAtIndex() throws {
    let manager = try makeTempSettingsManager()
    let vm = SettingsViewModel(settingsManager: manager)

    try vm.addCommand(alias: "old", command: "old-cmd", workingDirectory: nil)

    let updated = CustomCommand(alias: "new", command: "new-cmd", workingDirectory: "/home")
    try vm.updateCommand(at: 0, updated)

    #expect(vm.settings.customCommands[0].alias == "new")
    #expect(vm.settings.customCommands[0].command == "new-cmd")
    #expect(vm.settings.customCommands[0].workingDirectory == "/home")
  }

  @MainActor
  @Test func updateCommandPreservesOthers() throws {
    let manager = try makeTempSettingsManager()
    let vm = SettingsViewModel(settingsManager: manager)

    try vm.addCommand(alias: "a", command: "cmd-a", workingDirectory: nil)
    try vm.addCommand(alias: "b", command: "cmd-b", workingDirectory: nil)

    let updated = CustomCommand(alias: "a-updated", command: "cmd-a-updated", workingDirectory: nil)
    try vm.updateCommand(at: 0, updated)

    #expect(vm.settings.customCommands[0].alias == "a-updated")
    #expect(vm.settings.customCommands[1].alias == "b")
  }

  @MainActor
  @Test func addCommandPersists() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("ignitero-settings-vm-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let manager = SettingsManager(configDirectory: dir)
    let vm = SettingsViewModel(settingsManager: manager)
    try vm.addCommand(alias: "persist", command: "echo persist", workingDirectory: nil)

    let manager2 = SettingsManager(configDirectory: dir)
    try manager2.load()
    #expect(manager2.settings.customCommands.count == 1)
    #expect(manager2.settings.customCommands[0].alias == "persist")
  }
}

// MARK: - Excluded Apps Tests

@Suite("SettingsViewModel Excluded Apps")
@MainActor
struct SettingsViewModelExcludedAppsTests {

  @MainActor
  @Test func isAppExcludedReturnsFalseByDefault() throws {
    let manager = try makeTempSettingsManager()
    let vm = SettingsViewModel(settingsManager: manager)
    #expect(vm.isAppExcluded("Safari.app") == false)
  }

  @MainActor
  @Test func toggleExcludedAppAddsApp() throws {
    let manager = try makeTempSettingsManager()
    let vm = SettingsViewModel(settingsManager: manager)

    try vm.toggleExcludedApp("Safari.app")

    #expect(vm.isAppExcluded("Safari.app") == true)
    #expect(vm.settings.excludedApps.contains("Safari.app"))
  }

  @MainActor
  @Test func toggleExcludedAppRemovesApp() throws {
    let manager = try makeTempSettingsManager()
    let vm = SettingsViewModel(settingsManager: manager)

    try vm.toggleExcludedApp("Safari.app")
    #expect(vm.isAppExcluded("Safari.app") == true)

    try vm.toggleExcludedApp("Safari.app")
    #expect(vm.isAppExcluded("Safari.app") == false)
    #expect(!vm.settings.excludedApps.contains("Safari.app"))
  }

  @MainActor
  @Test func toggleExcludedAppMultipleApps() throws {
    let manager = try makeTempSettingsManager()
    let vm = SettingsViewModel(settingsManager: manager)

    try vm.toggleExcludedApp("Safari.app")
    try vm.toggleExcludedApp("Mail.app")
    try vm.toggleExcludedApp("Chess.app")

    #expect(vm.isAppExcluded("Safari.app") == true)
    #expect(vm.isAppExcluded("Mail.app") == true)
    #expect(vm.isAppExcluded("Chess.app") == true)
    #expect(vm.settings.excludedApps.count == 3)
  }

  @MainActor
  @Test func toggleExcludedAppPreservesOthers() throws {
    let manager = try makeTempSettingsManager()
    let vm = SettingsViewModel(settingsManager: manager)

    try vm.toggleExcludedApp("Safari.app")
    try vm.toggleExcludedApp("Mail.app")

    // Remove only Safari
    try vm.toggleExcludedApp("Safari.app")

    #expect(vm.isAppExcluded("Safari.app") == false)
    #expect(vm.isAppExcluded("Mail.app") == true)
    #expect(vm.settings.excludedApps.count == 1)
  }

  @MainActor
  @Test func toggleExcludedAppPersists() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("ignitero-settings-vm-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let manager = SettingsManager(configDirectory: dir)
    let vm = SettingsViewModel(settingsManager: manager)
    try vm.toggleExcludedApp("Xcode.app")

    let manager2 = SettingsManager(configDirectory: dir)
    try manager2.load()
    #expect(manager2.settings.excludedApps.contains("Xcode.app"))
  }

  @MainActor
  @Test func allAppsCanBeSetExternally() throws {
    let manager = try makeTempSettingsManager()
    let vm = SettingsViewModel(settingsManager: manager)

    let apps = [
      AppItem(name: "Safari", path: "/Applications/Safari.app"),
      AppItem(name: "Mail", path: "/Applications/Mail.app"),
    ]
    vm.allApps = apps

    #expect(vm.allApps.count == 2)
    #expect(vm.allApps[0].name == "Safari")
    #expect(vm.allApps[1].name == "Mail")
  }
}

// MARK: - onSettingsChanged Callback Tests

@Suite("SettingsViewModel onSettingsChanged Callback")
@MainActor
struct SettingsViewModelOnSettingsChangedTests {

  @MainActor
  @Test func setDefaultEditorCallsOnSettingsChanged() throws {
    let manager = try makeTempSettingsManager()
    let vm = SettingsViewModel(settingsManager: manager)

    var callbackCount = 0
    vm.onSettingsChanged = { callbackCount += 1 }

    try vm.setDefaultEditor(.cursor)
    #expect(callbackCount == 1)
  }

  @MainActor
  @Test func setDefaultTerminalCallsOnSettingsChanged() throws {
    let manager = try makeTempSettingsManager()
    let vm = SettingsViewModel(settingsManager: manager)

    var callbackCount = 0
    vm.onSettingsChanged = { callbackCount += 1 }

    try vm.setDefaultTerminal(.ghostty)
    #expect(callbackCount == 1)
  }

  @MainActor
  @Test func setCacheUpdateSettingsCallsOnSettingsChangedFromSuite() throws {
    let manager = try makeTempSettingsManager()
    let vm = SettingsViewModel(settingsManager: manager)

    var callbackCount = 0
    vm.onSettingsChanged = { callbackCount += 1 }

    let newSettings = CacheUpdateSettings(
      updateOnStartup: false,
      autoUpdateEnabled: false,
      autoUpdateIntervalHours: 24
    )
    try vm.setCacheUpdateSettings(newSettings)
    #expect(callbackCount == 1)
  }

  @MainActor
  @Test func multipleSettingsChangesCallCallbackMultipleTimes() throws {
    let manager = try makeTempSettingsManager()
    let vm = SettingsViewModel(settingsManager: manager)

    var callbackCount = 0
    vm.onSettingsChanged = { callbackCount += 1 }

    try vm.setDefaultEditor(.vscode)
    try vm.setDefaultTerminal(.warp)
    let cacheSettings = CacheUpdateSettings(
      updateOnStartup: true,
      autoUpdateEnabled: true,
      autoUpdateIntervalHours: 6
    )
    try vm.setCacheUpdateSettings(cacheSettings)

    #expect(callbackCount == 3)
  }

  @MainActor
  @Test func noCallbackWhenNotSet() throws {
    let manager = try makeTempSettingsManager()
    let vm = SettingsViewModel(settingsManager: manager)
    // onSettingsChanged を設定しない状態でクラッシュしないこと
    try vm.setDefaultEditor(.zed)
    try vm.setDefaultTerminal(.terminal)
    let cacheSettings = CacheUpdateSettings(
      updateOnStartup: false,
      autoUpdateEnabled: false,
      autoUpdateIntervalHours: 12
    )
    try vm.setCacheUpdateSettings(cacheSettings)
    // クラッシュしなければOK
  }
}

// MARK: - Version Tests

@Suite("SettingsViewModel Version")
@MainActor
struct SettingsViewModelVersionTests {

  @MainActor
  @Test func versionMatchesIgniteroVersion() throws {
    let manager = try makeTempSettingsManager()
    let vm = SettingsViewModel(settingsManager: manager)
    #expect(vm.version == Ignitero.version)
    #expect(!vm.version.isEmpty)
  }
}
