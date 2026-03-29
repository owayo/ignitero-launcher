import Foundation

// MARK: - 列挙型

public enum TerminalType: String, Codable, Sendable, CaseIterable {
  case terminal
  case iterm2
  case ghostty
  case warp
  case cmux
}

public enum OpenMode: String, Codable, Sendable, CaseIterable {
  case none
  case finder
  case editor
}

// MARK: - データモデル

public struct RegisteredDirectory: Codable, Sendable, Equatable {
  public var path: String
  public var parentOpenMode: OpenMode
  public var parentEditor: String?
  public var parentSearchKeyword: String?
  public var subdirsOpenMode: OpenMode
  public var subdirsEditor: String?
  public var scanForApps: Bool

  public init(
    path: String,
    parentOpenMode: OpenMode,
    parentEditor: String? = nil,
    parentSearchKeyword: String? = nil,
    subdirsOpenMode: OpenMode,
    subdirsEditor: String? = nil,
    scanForApps: Bool
  ) {
    self.path = path
    self.parentOpenMode = parentOpenMode
    self.parentEditor = parentEditor
    self.parentSearchKeyword = parentSearchKeyword
    self.subdirsOpenMode = subdirsOpenMode
    self.subdirsEditor = subdirsEditor
    self.scanForApps = scanForApps
  }

  enum CodingKeys: String, CodingKey {
    case path
    case parentOpenMode = "parent_open_mode"
    case parentEditor = "parent_editor"
    case parentSearchKeyword = "parent_search_keyword"
    case subdirsOpenMode = "subdirs_open_mode"
    case subdirsEditor = "subdirs_editor"
    case scanForApps = "scan_for_apps"
  }
}

public struct CustomCommand: Codable, Sendable, Equatable, Identifiable {
  public let id: UUID
  public var alias: String
  public var command: String
  public var workingDirectory: String?

  public init(id: UUID = UUID(), alias: String, command: String, workingDirectory: String? = nil) {
    self.id = id
    self.alias = alias
    self.command = command
    self.workingDirectory = workingDirectory
  }

  /// 選択履歴や検索結果で利用する、カスタムコマンド固有の識別子。
  public var historyIdentifier: String {
    "command://\(id.uuidString.lowercased())"
  }

  enum CodingKeys: String, CodingKey {
    case id
    case alias
    case command
    case workingDirectory = "working_directory"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    self.alias = try container.decode(String.self, forKey: .alias)
    self.command = try container.decode(String.self, forKey: .command)
    self.workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory)
  }
}

public struct CacheUpdateSettings: Codable, Sendable, Equatable {
  public var updateOnStartup: Bool
  public var autoUpdateEnabled: Bool
  public var autoUpdateIntervalHours: Int

  public init(updateOnStartup: Bool, autoUpdateEnabled: Bool, autoUpdateIntervalHours: Int) {
    self.updateOnStartup = updateOnStartup
    self.autoUpdateEnabled = autoUpdateEnabled
    self.autoUpdateIntervalHours = autoUpdateIntervalHours
  }

  enum CodingKeys: String, CodingKey {
    case updateOnStartup = "update_on_startup"
    case autoUpdateEnabled = "auto_update_enabled"
    case autoUpdateIntervalHours = "auto_update_interval_hours"
  }
}

public struct WindowPosition: Codable, Sendable, Equatable {
  public var x: Double
  public var y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

public struct UpdateCache: Codable, Sendable, Equatable {
  public var latestVersion: String?
  public var checkedAt: Date?
  public var dismissedVersion: String?
  public var downloadURL: String?

  public init(
    latestVersion: String? = nil, checkedAt: Date? = nil, dismissedVersion: String? = nil,
    downloadURL: String? = nil
  ) {
    self.latestVersion = latestVersion
    self.checkedAt = checkedAt
    self.dismissedVersion = dismissedVersion
    self.downloadURL = downloadURL
  }

  enum CodingKeys: String, CodingKey {
    case latestVersion = "latest_version"
    case checkedAt = "checked_at"
    case dismissedVersion = "dismissed_version"
    case downloadURL = "download_url"
  }
}

// MARK: - 設定

public struct Settings: Codable, Sendable {
  public var registeredDirectories: [RegisteredDirectory]
  public var customCommands: [CustomCommand]
  public var defaultEditor: EditorType
  public var defaultTerminal: TerminalType
  public var cacheUpdate: CacheUpdateSettings
  public var excludedApps: [String]
  public var windowPosition: WindowPosition?
  public var updateCache: UpdateCache?

  public init(
    registeredDirectories: [RegisteredDirectory] = [],
    customCommands: [CustomCommand] = [],
    defaultEditor: EditorType = .cursor,
    defaultTerminal: TerminalType = .terminal,
    cacheUpdate: CacheUpdateSettings = CacheUpdateSettings(
      updateOnStartup: true, autoUpdateEnabled: false, autoUpdateIntervalHours: 6),
    excludedApps: [String] = [],
    windowPosition: WindowPosition? = nil,
    updateCache: UpdateCache? = nil
  ) {
    self.registeredDirectories = registeredDirectories
    self.customCommands = customCommands
    self.defaultEditor = defaultEditor
    self.defaultTerminal = defaultTerminal
    self.cacheUpdate = cacheUpdate
    self.excludedApps = excludedApps
    self.windowPosition = windowPosition
    self.updateCache = updateCache
  }

  public static let `default` = Settings()

  enum CodingKeys: String, CodingKey {
    case registeredDirectories = "registered_directories"
    case customCommands = "custom_commands"
    case defaultEditor = "default_editor"
    case defaultTerminal = "default_terminal"
    case cacheUpdate = "cache_update"
    case excludedApps = "excluded_apps"
    case windowPosition = "main_window_position"
    case updateCache = "update_cache"
  }

  /// 既存の設定ファイルとの後方互換デコード（新フィールドはデフォルト値で補完）。
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    registeredDirectories =
      try container.decodeIfPresent([RegisteredDirectory].self, forKey: .registeredDirectories)
      ?? []
    customCommands =
      try container.decodeIfPresent([CustomCommand].self, forKey: .customCommands) ?? []
    defaultEditor =
      try container.decodeIfPresent(EditorType.self, forKey: .defaultEditor) ?? .cursor
    defaultTerminal =
      try container.decodeIfPresent(TerminalType.self, forKey: .defaultTerminal) ?? .terminal
    cacheUpdate =
      try container.decodeIfPresent(CacheUpdateSettings.self, forKey: .cacheUpdate)
      ?? CacheUpdateSettings(
        updateOnStartup: true, autoUpdateEnabled: false, autoUpdateIntervalHours: 6)
    excludedApps =
      try container.decodeIfPresent([String].self, forKey: .excludedApps) ?? []
    windowPosition =
      try container.decodeIfPresent(WindowPosition.self, forKey: .windowPosition)
    updateCache =
      try container.decodeIfPresent(UpdateCache.self, forKey: .updateCache)
  }
}

// MARK: - 設定マネージャ

@Observable
public final class SettingsManager: @unchecked Sendable {
  public var settings: Settings

  private let configDirectory: URL
  private let fileName = "settings.json"

  private var filePath: URL {
    configDirectory.appendingPathComponent(fileName)
  }

  public init(configDirectory: URL? = nil) {
    self.configDirectory =
      configDirectory
      ?? FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".config/ignitero-launcher")
    self.settings = .default
  }

  public func save() throws {
    let fm = FileManager.default
    if !fm.fileExists(atPath: configDirectory.path) {
      try fm.createDirectory(at: configDirectory, withIntermediateDirectories: true)
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(settings)
    try data.write(to: filePath, options: .atomic)
  }

  public func load() throws {
    let fm = FileManager.default
    guard fm.fileExists(atPath: filePath.path) else {
      settings = .default
      return
    }

    do {
      let data = try Data(contentsOf: filePath)
      settings = try JSONDecoder().decode(Settings.self, from: data)
    } catch is DecodingError {
      // JSON が破損: バックアップを作成しデフォルト値に復元
      let backupPath = configDirectory.appendingPathComponent("\(fileName).backup")
      try? fm.removeItem(at: backupPath)
      try? fm.copyItem(at: filePath, to: backupPath)
      settings = .default
    } catch {
      // I/O エラーは呼び出し側へ伝播する
      throw error
    }
  }

  public func addDirectory(_ dir: RegisteredDirectory) throws {
    settings.registeredDirectories.append(dir)
    try save()
  }

  public func removeDirectory(path: String) throws {
    settings.registeredDirectories.removeAll { $0.path == path }
    try save()
  }

  public func addCommand(_ cmd: CustomCommand) throws {
    settings.customCommands.append(cmd)
    try save()
  }

  public func removeCommand(alias: String) throws {
    settings.customCommands.removeAll { $0.alias == alias }
    try save()
  }
}
