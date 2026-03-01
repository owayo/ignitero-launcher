import Foundation
import Testing

@testable import IgniteroCore

// MARK: - Settings Codable Tests

@Suite("Settings JSON Encode/Decode")
struct SettingsCodableTests {

  @Test func encodeAndDecodeRoundTrip() throws {
    let settings = Settings(
      registeredDirectories: [
        RegisteredDirectory(
          path: "/Users/test/projects",
          parentOpenMode: .editor,
          parentEditor: "cursor",
          parentSearchKeyword: "projects",
          subdirsOpenMode: .editor,
          subdirsEditor: "cursor",
          scanForApps: false
        )
      ],
      customCommands: [
        CustomCommand(alias: "dev", command: "npm run dev", workingDirectory: "/Users/test/app")
      ],
      defaultTerminal: .terminal,
      cacheUpdate: CacheUpdateSettings(
        updateOnStartup: true,
        autoUpdateEnabled: false,
        autoUpdateIntervalHours: 6
      ),
      excludedApps: ["Chess.app"],
      windowPosition: WindowPosition(x: 100, y: 200),
      updateCache: nil
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(settings)
    let decoded = try JSONDecoder().decode(Settings.self, from: data)

    #expect(decoded.registeredDirectories.count == 1)
    #expect(decoded.registeredDirectories[0].path == "/Users/test/projects")
    #expect(decoded.registeredDirectories[0].parentOpenMode == .editor)
    #expect(decoded.registeredDirectories[0].parentEditor == "cursor")
    #expect(decoded.registeredDirectories[0].parentSearchKeyword == "projects")
    #expect(decoded.registeredDirectories[0].subdirsOpenMode == .editor)
    #expect(decoded.registeredDirectories[0].subdirsEditor == "cursor")
    #expect(decoded.registeredDirectories[0].scanForApps == false)
    #expect(decoded.customCommands.count == 1)
    #expect(decoded.customCommands[0].alias == "dev")
    #expect(decoded.customCommands[0].command == "npm run dev")
    #expect(decoded.customCommands[0].workingDirectory == "/Users/test/app")
    #expect(decoded.defaultTerminal == .terminal)
    #expect(decoded.cacheUpdate.updateOnStartup == true)
    #expect(decoded.cacheUpdate.autoUpdateEnabled == false)
    #expect(decoded.cacheUpdate.autoUpdateIntervalHours == 6)
    #expect(decoded.excludedApps == ["Chess.app"])
    #expect(decoded.windowPosition?.x == 100)
    #expect(decoded.windowPosition?.y == 200)
    #expect(decoded.updateCache == nil)
  }

  @Test func decodeFromTauriSnakeCaseJSON() throws {
    let json = """
      {
        "registered_directories": [
          {
            "path": "/Users/test/dev",
            "parent_open_mode": "finder",
            "parent_editor": null,
            "parent_search_keyword": null,
            "subdirs_open_mode": "editor",
            "subdirs_editor": "vscode",
            "scan_for_apps": true
          }
        ],
        "custom_commands": [
          {
            "alias": "build",
            "command": "make build",
            "working_directory": "/tmp"
          }
        ],
        "default_terminal": "iterm2",
        "cache_update": {
          "update_on_startup": false,
          "auto_update_enabled": true,
          "auto_update_interval_hours": 12
        },
        "excluded_apps": ["Safari.app", "Mail.app"],
        "main_window_position": { "x": 50, "y": 75 }
      }
      """
    let data = Data(json.utf8)
    let settings = try JSONDecoder().decode(Settings.self, from: data)

    #expect(settings.registeredDirectories.count == 1)
    #expect(settings.registeredDirectories[0].path == "/Users/test/dev")
    #expect(settings.registeredDirectories[0].parentOpenMode == .finder)
    #expect(settings.registeredDirectories[0].subdirsOpenMode == .editor)
    #expect(settings.registeredDirectories[0].subdirsEditor == "vscode")
    #expect(settings.registeredDirectories[0].scanForApps == true)
    #expect(settings.customCommands[0].alias == "build")
    #expect(settings.defaultTerminal == .iterm2)
    #expect(settings.cacheUpdate.updateOnStartup == false)
    #expect(settings.cacheUpdate.autoUpdateEnabled == true)
    #expect(settings.cacheUpdate.autoUpdateIntervalHours == 12)
    #expect(settings.excludedApps == ["Safari.app", "Mail.app"])
    #expect(settings.windowPosition?.x == 50)
    #expect(settings.windowPosition?.y == 75)
    #expect(settings.updateCache == nil)
  }

  @Test func encodesToSnakeCaseCompatibleKeys() throws {
    let settings = Settings.default
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    let data = try encoder.encode(settings)
    let jsonString = String(data: data, encoding: .utf8)!

    // snake_case keys in JSON output
    #expect(jsonString.contains("\"registered_directories\""))
    #expect(jsonString.contains("\"custom_commands\""))
    #expect(jsonString.contains("\"default_terminal\""))
    #expect(jsonString.contains("\"cache_update\""))
    #expect(jsonString.contains("\"excluded_apps\""))
    // camelCase should NOT appear
    #expect(!jsonString.contains("\"registeredDirectories\""))
    #expect(!jsonString.contains("\"customCommands\""))
    #expect(!jsonString.contains("\"defaultTerminal\""))
  }

  @Test func defaultSettingsValues() {
    let settings = Settings.default
    #expect(settings.registeredDirectories.isEmpty)
    #expect(settings.customCommands.isEmpty)
    #expect(settings.defaultTerminal == .terminal)
    #expect(settings.cacheUpdate.updateOnStartup == true)
    #expect(settings.cacheUpdate.autoUpdateEnabled == false)
    #expect(settings.cacheUpdate.autoUpdateIntervalHours == 6)
    #expect(settings.excludedApps.isEmpty)
    #expect(settings.windowPosition == nil)
    #expect(settings.updateCache == nil)
  }

  @Test func decodeWithUnknownKeysIgnored() throws {
    let json = """
      {
        "registered_directories": [],
        "custom_commands": [],
        "default_terminal": "terminal",
        "cache_update": {
          "update_on_startup": true,
          "auto_update_enabled": false,
          "auto_update_interval_hours": 6
        },
        "excluded_apps": [],
        "future_field": "should be ignored",
        "another_unknown": 42
      }
      """
    let data = Data(json.utf8)
    // Should not throw even with unknown keys
    let settings = try JSONDecoder().decode(Settings.self, from: data)
    #expect(settings.defaultTerminal == .terminal)
  }

  @Test func decodeWithMissingOptionalFields() throws {
    // Minimal JSON: no default_editor, no main_window_position, no update_cache
    let json = """
      {
        "registered_directories": [],
        "custom_commands": [],
        "default_terminal": "ghostty",
        "cache_update": {
          "update_on_startup": true,
          "auto_update_enabled": false,
          "auto_update_interval_hours": 3
        },
        "excluded_apps": []
      }
      """
    let data = Data(json.utf8)
    let settings = try JSONDecoder().decode(Settings.self, from: data)
    #expect(settings.windowPosition == nil)
    #expect(settings.updateCache == nil)
    #expect(settings.defaultEditor == .cursor)
    #expect(settings.defaultTerminal == .ghostty)
  }

  @Test func allTerminalTypes() throws {
    for terminal in TerminalType.allCases {
      let json = """
        {
          "registered_directories": [],
          "custom_commands": [],
          "default_terminal": "\(terminal.rawValue)",
          "cache_update": {
            "update_on_startup": true,
            "auto_update_enabled": false,
            "auto_update_interval_hours": 6
          },
          "excluded_apps": []
        }
        """
      let data = Data(json.utf8)
      let settings = try JSONDecoder().decode(Settings.self, from: data)
      #expect(settings.defaultTerminal == terminal)
    }
  }

  @Test func allOpenModes() throws {
    for mode in OpenMode.allCases {
      let json = """
        {
          "path": "/test",
          "parent_open_mode": "\(mode.rawValue)",
          "subdirs_open_mode": "\(mode.rawValue)",
          "scan_for_apps": false
        }
        """
      let data = Data(json.utf8)
      let dir = try JSONDecoder().decode(RegisteredDirectory.self, from: data)
      #expect(dir.parentOpenMode == mode)
      #expect(dir.subdirsOpenMode == mode)
    }
  }

  @Test func updateCacheEncodeDecode() throws {
    let cache = UpdateCache(
      latestVersion: "27.1.0",
      checkedAt: Date(timeIntervalSince1970: 1_700_000_000),
      dismissedVersion: "27.0.0"
    )
    let data = try JSONEncoder().encode(cache)
    let decoded = try JSONDecoder().decode(UpdateCache.self, from: data)
    #expect(decoded.latestVersion == "27.1.0")
    #expect(decoded.checkedAt == Date(timeIntervalSince1970: 1_700_000_000))
    #expect(decoded.dismissedVersion == "27.0.0")
  }
}

// MARK: - SettingsManager Tests

@Suite("SettingsManager Save/Load")
struct SettingsManagerTests {

  private func makeTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("ignitero-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func cleanup(_ dir: URL) {
    try? FileManager.default.removeItem(at: dir)
  }

  @Test func saveAndLoadSettings() throws {
    let dir = try makeTempDir()
    defer { cleanup(dir) }

    let manager = SettingsManager(configDirectory: dir)
    manager.settings.defaultTerminal = .warp
    manager.settings.excludedApps = ["Xcode.app"]
    try manager.save()

    let manager2 = SettingsManager(configDirectory: dir)
    try manager2.load()

    #expect(manager2.settings.defaultTerminal == .warp)
    #expect(manager2.settings.excludedApps == ["Xcode.app"])
  }

  @Test func loadFromNonExistentFileUsesDefaults() throws {
    let dir = try makeTempDir()
    defer { cleanup(dir) }

    let manager = SettingsManager(configDirectory: dir)
    try manager.load()

    // Should use default settings, not throw
    #expect(manager.settings.defaultTerminal == .terminal)
    #expect(manager.settings.registeredDirectories.isEmpty)
  }

  @Test func loadFromCorruptedFileRestoresDefaults() throws {
    let dir = try makeTempDir()
    defer { cleanup(dir) }

    let filePath = dir.appendingPathComponent("settings.json")
    try "not valid json {{{".write(to: filePath, atomically: true, encoding: .utf8)

    let manager = SettingsManager(configDirectory: dir)
    try manager.load()

    // Corrupted: should fall back to defaults
    #expect(manager.settings.defaultTerminal == .terminal)
    #expect(manager.settings.registeredDirectories.isEmpty)

    // Backup file should have been created
    let backupExists = FileManager.default.fileExists(
      atPath: dir.appendingPathComponent("settings.json.backup").path
    )
    #expect(backupExists)
  }

  @Test func loadFromUnreadableSettingsFileThrows() throws {
    let dir = try makeTempDir()
    defer { cleanup(dir) }

    // settings.json の代わりに同名ディレクトリを作成し、Data(contentsOf:) を失敗させる。
    let filePath = dir.appendingPathComponent("settings.json")
    try FileManager.default.createDirectory(at: filePath, withIntermediateDirectories: true)

    let manager = SettingsManager(configDirectory: dir)
    manager.settings.defaultTerminal = .warp

    do {
      try manager.load()
      Issue.record("Expected load() to throw for unreadable settings file")
    } catch {
      #expect(manager.settings.defaultTerminal == .warp)
      let backupPath = dir.appendingPathComponent("settings.json.backup")
      #expect(!FileManager.default.fileExists(atPath: backupPath.path))
    }
  }

  @Test func addDirectory() throws {
    let dir = try makeTempDir()
    defer { cleanup(dir) }

    let manager = SettingsManager(configDirectory: dir)
    let newDir = RegisteredDirectory(
      path: "/Users/test/workspace",
      parentOpenMode: .editor,
      parentEditor: "cursor",
      parentSearchKeyword: nil,
      subdirsOpenMode: .editor,
      subdirsEditor: "cursor",
      scanForApps: false
    )
    try manager.addDirectory(newDir)

    #expect(manager.settings.registeredDirectories.count == 1)
    #expect(manager.settings.registeredDirectories[0].path == "/Users/test/workspace")

    // Verify persistence
    let manager2 = SettingsManager(configDirectory: dir)
    try manager2.load()
    #expect(manager2.settings.registeredDirectories.count == 1)
  }

  @Test func removeDirectory() throws {
    let dir = try makeTempDir()
    defer { cleanup(dir) }

    let manager = SettingsManager(configDirectory: dir)
    let dir1 = RegisteredDirectory(
      path: "/path/a",
      parentOpenMode: .none,
      subdirsOpenMode: .none,
      scanForApps: false
    )
    let dir2 = RegisteredDirectory(
      path: "/path/b",
      parentOpenMode: .finder,
      subdirsOpenMode: .finder,
      scanForApps: true
    )
    try manager.addDirectory(dir1)
    try manager.addDirectory(dir2)
    #expect(manager.settings.registeredDirectories.count == 2)

    try manager.removeDirectory(path: "/path/a")
    #expect(manager.settings.registeredDirectories.count == 1)
    #expect(manager.settings.registeredDirectories[0].path == "/path/b")
  }

  @Test func addCommand() throws {
    let dir = try makeTempDir()
    defer { cleanup(dir) }

    let manager = SettingsManager(configDirectory: dir)
    let cmd = CustomCommand(alias: "test", command: "echo hello", workingDirectory: nil)
    try manager.addCommand(cmd)

    #expect(manager.settings.customCommands.count == 1)
    #expect(manager.settings.customCommands[0].alias == "test")

    // Verify persistence
    let manager2 = SettingsManager(configDirectory: dir)
    try manager2.load()
    #expect(manager2.settings.customCommands.count == 1)
  }

  @Test func removeCommand() throws {
    let dir = try makeTempDir()
    defer { cleanup(dir) }

    let manager = SettingsManager(configDirectory: dir)
    let cmd1 = CustomCommand(alias: "a", command: "cmd-a", workingDirectory: nil)
    let cmd2 = CustomCommand(alias: "b", command: "cmd-b", workingDirectory: "/tmp")
    try manager.addCommand(cmd1)
    try manager.addCommand(cmd2)
    #expect(manager.settings.customCommands.count == 2)

    try manager.removeCommand(alias: "a")
    #expect(manager.settings.customCommands.count == 1)
    #expect(manager.settings.customCommands[0].alias == "b")
  }

  @Test func savesCreatesDirectoryIfNeeded() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("ignitero-nested-\(UUID().uuidString)")
      .appendingPathComponent("sub")
    defer { cleanup(dir.deletingLastPathComponent()) }

    let manager = SettingsManager(configDirectory: dir)
    manager.settings.defaultTerminal = .ghostty
    try manager.save()

    let manager2 = SettingsManager(configDirectory: dir)
    try manager2.load()
    #expect(manager2.settings.defaultTerminal == .ghostty)
  }

  @Test func loadFromTruncatedJSONRestoresDefaults() throws {
    let dir = try makeTempDir()
    defer { cleanup(dir) }

    let filePath = dir.appendingPathComponent("settings.json")
    try """
    {"registered_directories": [{"path": "/test", "parent_open_mode": "editor"
    """.write(to: filePath, atomically: true, encoding: .utf8)

    let manager = SettingsManager(configDirectory: dir)
    try manager.load()

    #expect(manager.settings.defaultTerminal == .terminal)
    #expect(manager.settings.registeredDirectories.isEmpty)

    let backupExists = FileManager.default.fileExists(
      atPath: dir.appendingPathComponent("settings.json.backup").path
    )
    #expect(backupExists)
  }

  @Test func loadFromCorruptedFileOverwritesExistingBackup() throws {
    let dir = try makeTempDir()
    defer { cleanup(dir) }

    let backupPath = dir.appendingPathComponent("settings.json.backup")
    try "old backup content".write(to: backupPath, atomically: true, encoding: .utf8)

    let filePath = dir.appendingPathComponent("settings.json")
    try "{{corrupt}}".write(to: filePath, atomically: true, encoding: .utf8)

    let manager = SettingsManager(configDirectory: dir)
    try manager.load()

    #expect(manager.settings.defaultTerminal == .terminal)

    let backupContent = try String(contentsOf: backupPath, encoding: .utf8)
    #expect(backupContent == "{{corrupt}}")
  }

  @Test func loadExistingTauriSettingsFile() throws {
    let dir = try makeTempDir()
    defer { cleanup(dir) }

    // Write a Tauri-format settings.json
    let tauriJSON = """
      {
        "registered_directories": [
          {
            "path": "/Users/owa/projects",
            "parent_open_mode": "editor",
            "parent_editor": "windsurf",
            "parent_search_keyword": "prj",
            "subdirs_open_mode": "editor",
            "subdirs_editor": "windsurf",
            "scan_for_apps": false
          }
        ],
        "custom_commands": [
          {
            "alias": "serve",
            "command": "python -m http.server",
            "working_directory": "/var/www"
          }
        ],
        "default_terminal": "ghostty",
        "cache_update": {
          "update_on_startup": true,
          "auto_update_enabled": true,
          "auto_update_interval_hours": 4
        },
        "excluded_apps": ["Feedback Assistant.app"],
        "main_window_position": { "x": 300, "y": 150 }
      }
      """
    let filePath = dir.appendingPathComponent("settings.json")
    try tauriJSON.write(to: filePath, atomically: true, encoding: .utf8)

    let manager = SettingsManager(configDirectory: dir)
    try manager.load()

    #expect(manager.settings.registeredDirectories.count == 1)
    #expect(manager.settings.registeredDirectories[0].parentEditor == "windsurf")
    #expect(manager.settings.registeredDirectories[0].parentSearchKeyword == "prj")
    #expect(manager.settings.customCommands[0].alias == "serve")
    #expect(manager.settings.defaultTerminal == .ghostty)
    #expect(manager.settings.cacheUpdate.autoUpdateEnabled == true)
    #expect(manager.settings.cacheUpdate.autoUpdateIntervalHours == 4)
    #expect(manager.settings.excludedApps == ["Feedback Assistant.app"])
    #expect(manager.settings.windowPosition?.x == 300)
    #expect(manager.settings.windowPosition?.y == 150)
  }
}
