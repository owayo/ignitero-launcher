import Foundation
import os

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

  /// 未知の `OpenMode` を `.finder` へ落として読み込む。
  ///
  /// 合成デコーダのままだと未知の rawValue で `DecodingError` を投げ、それが
  /// `SettingsManager.load()` に捕まって「設定ファイル全体をデフォルトへ巻き戻す」
  /// 挙動になる（登録ディレクトリもカスタムコマンドも除外アプリも失われる）。
  /// 「表示しない」は既知の `.none` として保存されるため、未知の値は
  /// 何らかの表示モードだった可能性が高い。ディレクトリが黙って消えるより
  /// Finder で開ける状態に落とす方が復旧しやすい。
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    path = try container.decode(String.self, forKey: .path)
    parentOpenMode = Self.decodeOpenMode(from: container, forKey: .parentOpenMode)
    parentEditor = try container.decodeIfPresent(String.self, forKey: .parentEditor)
    parentSearchKeyword = try container.decodeIfPresent(String.self, forKey: .parentSearchKeyword)
    subdirsOpenMode = Self.decodeOpenMode(from: container, forKey: .subdirsOpenMode)
    subdirsEditor = try container.decodeIfPresent(String.self, forKey: .subdirsEditor)
    scanForApps = try container.decode(Bool.self, forKey: .scanForApps)
  }

  private static func decodeOpenMode(
    from container: KeyedDecodingContainer<CodingKeys>,
    forKey key: CodingKeys
  ) -> OpenMode {
    guard let mode = try? container.decodeIfPresent(OpenMode.self, forKey: key) else {
      return .finder
    }
    return mode
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
  public var updateCache: UpdateCache?

  public init(
    registeredDirectories: [RegisteredDirectory] = [],
    customCommands: [CustomCommand] = [],
    defaultEditor: EditorType = .cursor,
    defaultTerminal: TerminalType = .terminal,
    cacheUpdate: CacheUpdateSettings = CacheUpdateSettings(
      updateOnStartup: true, autoUpdateEnabled: false, autoUpdateIntervalHours: 6),
    excludedApps: [String] = [],
    updateCache: UpdateCache? = nil
  ) {
    self.registeredDirectories = registeredDirectories
    self.customCommands = customCommands
    self.defaultEditor = defaultEditor
    self.defaultTerminal = defaultTerminal
    self.cacheUpdate = cacheUpdate
    self.excludedApps = excludedApps
    self.updateCache = updateCache
  }

  public static var defaultRegisteredDirectories: [RegisteredDirectory] {
    [
      RegisteredDirectory(
        path: FileManager.default.homeDirectoryForCurrentUser
          .appendingPathComponent("Applications/Chrome Apps.localized").path,
        parentOpenMode: .none,
        subdirsOpenMode: .none,
        scanForApps: true
      )
    ]
  }

  public static let `default` = Settings(
    registeredDirectories: Settings.defaultRegisteredDirectories)

  enum CodingKeys: String, CodingKey {
    case registeredDirectories = "registered_directories"
    case customCommands = "custom_commands"
    case defaultEditor = "default_editor"
    case defaultTerminal = "default_terminal"
    case cacheUpdate = "cache_update"
    case excludedApps = "excluded_apps"
    case updateCache = "update_cache"
  }

  /// 未知の rawValue を持つ enum フィールドをデフォルト値へ落として読み込む。
  ///
  /// `decodeIfPresent` が nil を返すのはキー欠落か null のときだけで、キーが存在して
  /// rawValue が未知（新しいビルドで選んだ `cmux` を旧ビルドで読む、設定ファイルの
  /// 手編集ミス等）の場合は `DecodingError.dataCorrupted` を投げる。
  /// この 1 フィールドの失敗が `load()` の `catch is DecodingError` に捕まると
  /// 登録ディレクトリ・カスタムコマンド・除外アプリを含む全設定がデフォルトへ
  /// 巻き戻ってしまうため、enum だけは個別に握りつぶす。
  private static func decodeLenient<T: Decodable>(
    _ type: T.Type,
    from container: KeyedDecodingContainer<CodingKeys>,
    forKey key: CodingKeys,
    default fallback: T
  ) -> T {
    guard let value = try? container.decodeIfPresent(type, forKey: key) else {
      return fallback
    }
    return value
  }

  /// 既存の設定ファイルとの後方互換デコード（新フィールドはデフォルト値で補完）。
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    registeredDirectories =
      try container.decodeIfPresent([RegisteredDirectory].self, forKey: .registeredDirectories)
      ?? Settings.defaultRegisteredDirectories
    customCommands =
      try container.decodeIfPresent([CustomCommand].self, forKey: .customCommands) ?? []
    defaultEditor = Self.decodeLenient(
      EditorType.self, from: container, forKey: .defaultEditor, default: .cursor)
    defaultTerminal = Self.decodeLenient(
      TerminalType.self, from: container, forKey: .defaultTerminal, default: .terminal)
    cacheUpdate =
      try container.decodeIfPresent(CacheUpdateSettings.self, forKey: .cacheUpdate)
      ?? CacheUpdateSettings(
        updateOnStartup: true, autoUpdateEnabled: false, autoUpdateIntervalHours: 6)
    excludedApps =
      try container.decodeIfPresent([String].self, forKey: .excludedApps) ?? []
    updateCache =
      try container.decodeIfPresent(UpdateCache.self, forKey: .updateCache)
  }
}

// MARK: - 設定マネージャ

@MainActor
@Observable
public final class SettingsManager: @unchecked Sendable {
  private static let logger = Logger(
    subsystem: "com.ignitero.launcher", category: "SettingsManager")

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

  /// 設定変更を保存し、保存失敗時はメモリ上の設定を変更前へ戻す。
  ///
  /// - Parameter update: 設定へ適用する変更
  /// - Throws: 設定の保存に失敗した場合
  func updateSettings(_ update: (inout Settings) -> Void) throws {
    let previousSettings = settings
    update(&settings)

    do {
      try save()
    } catch {
      settings = previousSettings
      throw error
    }
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
      // 既存バックアップ削除と新規バックアップ作成は失敗してもデフォルト復元を続けるが、
      // ディスク満杯やパーミッションエラーで証跡が残らない事故を防ぐためログを残す。
      do {
        if fm.fileExists(atPath: backupPath.path) {
          try fm.removeItem(at: backupPath)
        }
        try fm.copyItem(at: filePath, to: backupPath)
      } catch {
        Self.logger.warning(
          "Failed to back up corrupted settings file: \(error.localizedDescription, privacy: .public)"
        )
      }
      settings = .default
    } catch {
      // I/O エラーは呼び出し側へ伝播する
      throw error
    }
  }

  public func addDirectory(_ dir: RegisteredDirectory) throws {
    // path を一意キーとして扱う。SettingsView の一覧は id: \.path で行を識別するため、
    // 同一 path の重複登録を防ぐ。既存エントリがあれば設定を置き換える。
    try updateSettings { settings in
      if let index = settings.registeredDirectories.firstIndex(where: { $0.path == dir.path }) {
        settings.registeredDirectories[index] = dir
      } else {
        settings.registeredDirectories.append(dir)
      }
    }
  }

  public func removeDirectory(path: String) throws {
    try updateSettings { settings in
      settings.registeredDirectories.removeAll { $0.path == path }
    }
  }

  public func addCommand(_ cmd: CustomCommand) throws {
    try updateSettings { settings in
      settings.customCommands.append(cmd)
    }
  }

  public func removeCommand(alias: String) throws {
    try updateSettings { settings in
      settings.customCommands.removeAll { $0.alias == alias }
    }
  }
}
