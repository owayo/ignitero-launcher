import Foundation
import ServiceManagement

// MARK: - SettingsTab

/// 設定画面のタブ種別。
public enum SettingsTab: String, CaseIterable, Sendable {
  case general
  case directories
  case commands
  case excludedApps
}

// MARK: - SettingsChange

/// 設定変更の種別。変更内容に応じてランチャー側で必要な反映処理が異なる。
public enum SettingsChange: Sendable, Equatable {
  /// ViewModel の再読み込みのみで反映できる変更（エディタ/ターミナル/コマンド）
  case reloadOnly
  /// キャッシュ再スキャンが必要な変更（ディレクトリ/除外アプリ）
  case cacheInvalidated
  /// 自動更新タイマーの再起動が必要な変更（キャッシュ更新設定）
  case updateScheduleChanged
}

// MARK: - SettingsViewModel

/// 設定画面のビューモデル。
///
/// `SettingsManager` をラップし、設定の読み書きロジックを提供する。
/// SwiftUI ビューはこの ViewModel を介して設定を操作する。
@MainActor
@Observable
public final class SettingsViewModel {

  // MARK: - Dependencies

  /// 設定の永続化を担う SettingsManager
  public let settingsManager: SettingsManager

  // MARK: - Callbacks

  /// 設定が保存された後に呼ばれるコールバック
  public var onSettingsChanged: ((SettingsChange) -> Void)?

  // MARK: - State

  /// 現在選択中のタブ
  public var selectedTab: SettingsTab = .general

  /// 除外アプリタブで表示する全アプリ一覧（外部から設定）
  public var allApps: [AppItem] = []

  /// インストール済みエディタ一覧（外部から設定）
  public var installedEditors: [EditorInfo] = []

  /// インストール済みターミナル一覧（外部から設定）
  public var installedTerminals: [TerminalInfo] = []

  // MARK: - Computed Properties

  /// 現在の設定（SettingsManager のプロキシ）
  public var settings: Settings {
    settingsManager.settings
  }

  /// アプリケーションバージョン
  public var version: String {
    Ignitero.version
  }

  // MARK: - Initialization

  /// SettingsViewModel を初期化する。
  ///
  /// - Parameter settingsManager: 設定の永続化を担う SettingsManager
  public init(settingsManager: SettingsManager) {
    self.settingsManager = settingsManager
  }

  // MARK: - Launch at Login

  /// ログイン時に起動するかどうか（SMAppService の状態を反映）。
  public var launchAtLogin: Bool {
    SMAppService.mainApp.status == .enabled
  }

  /// ログイン時起動の有効/無効を切り替える。
  ///
  /// - Parameter enabled: `true` で有効化、`false` で無効化
  /// - Throws: SMAppService の register/unregister に失敗した場合
  public func setLaunchAtLogin(_ enabled: Bool) throws {
    if enabled {
      try SMAppService.mainApp.register()
    } else {
      try SMAppService.mainApp.unregister()
    }
  }

  // MARK: - General Tab

  /// デフォルトエディタを変更する。
  ///
  /// - Parameter editor: 新しいデフォルトエディタ
  /// - Throws: 設定の保存に失敗した場合
  public func setDefaultEditor(_ editor: EditorType) throws {
    settingsManager.settings.defaultEditor = editor
    try settingsManager.save()
    onSettingsChanged?(.reloadOnly)
  }

  /// デフォルトターミナルを変更する。
  ///
  /// - Parameter terminal: 新しいデフォルトターミナル
  /// - Throws: 設定の保存に失敗した場合
  public func setDefaultTerminal(_ terminal: TerminalType) throws {
    settingsManager.settings.defaultTerminal = terminal
    try settingsManager.save()
    onSettingsChanged?(.reloadOnly)
  }

  /// キャッシュ更新設定を変更する。
  ///
  /// - Parameter cacheSettings: 新しいキャッシュ更新設定
  /// - Throws: 設定の保存に失敗した場合
  public func setCacheUpdateSettings(_ cacheSettings: CacheUpdateSettings) throws {
    settingsManager.settings.cacheUpdate = cacheSettings
    try settingsManager.save()
    onSettingsChanged?(.updateScheduleChanged)
  }

  // MARK: - Directory Tab

  /// ディレクトリを追加する。
  ///
  /// - Parameters:
  ///   - path: ディレクトリパス
  ///   - parentOpenMode: 親ディレクトリのオープンモード
  ///   - subdirsOpenMode: サブディレクトリのオープンモード
  ///   - scanForApps: アプリスキャンを行うかどうか
  /// - Throws: 設定の保存に失敗した場合
  public func addDirectory(
    path: String,
    parentOpenMode: OpenMode,
    subdirsOpenMode: OpenMode,
    scanForApps: Bool
  ) throws {
    let dir = RegisteredDirectory(
      path: path,
      parentOpenMode: parentOpenMode,
      subdirsOpenMode: subdirsOpenMode,
      scanForApps: scanForApps
    )
    try settingsManager.addDirectory(dir)
    onSettingsChanged?(.cacheInvalidated)
  }

  /// 指定インデックスのディレクトリを削除する。
  ///
  /// - Parameter index: 削除するディレクトリのインデックス
  /// - Throws: 設定の保存に失敗した場合
  public func removeDirectory(at index: Int) throws {
    guard settingsManager.settings.registeredDirectories.indices.contains(index) else { return }
    settingsManager.settings.registeredDirectories.remove(at: index)
    try settingsManager.save()
    onSettingsChanged?(.cacheInvalidated)
  }

  /// 指定インデックスのディレクトリを更新する。
  ///
  /// - Parameters:
  ///   - index: 更新するディレクトリのインデックス
  ///   - directory: 新しいディレクトリ設定
  /// - Throws: 設定の保存に失敗した場合
  public func updateDirectory(at index: Int, _ directory: RegisteredDirectory) throws {
    guard settingsManager.settings.registeredDirectories.indices.contains(index) else { return }
    settingsManager.settings.registeredDirectories[index] = directory
    try settingsManager.save()
    onSettingsChanged?(.cacheInvalidated)
  }

  // MARK: - Command Tab

  /// カスタムコマンドを追加する。
  ///
  /// - Parameters:
  ///   - alias: コマンドのエイリアス
  ///   - command: 実行するコマンド
  ///   - workingDirectory: 作業ディレクトリ（省略可）
  /// - Throws: 設定の保存に失敗した場合
  public func addCommand(
    alias: String,
    command: String,
    workingDirectory: String?
  ) throws {
    let cmd = CustomCommand(
      alias: alias,
      command: command,
      workingDirectory: workingDirectory
    )
    try settingsManager.addCommand(cmd)
    onSettingsChanged?(.reloadOnly)
  }

  /// 指定インデックスのコマンドを削除する。
  ///
  /// - Parameter index: 削除するコマンドのインデックス
  /// - Throws: 設定の保存に失敗した場合
  public func removeCommand(at index: Int) throws {
    guard settingsManager.settings.customCommands.indices.contains(index) else { return }
    settingsManager.settings.customCommands.remove(at: index)
    try settingsManager.save()
    onSettingsChanged?(.reloadOnly)
  }

  /// 指定インデックスのコマンドを更新する。
  ///
  /// - Parameters:
  ///   - index: 更新するコマンドのインデックス
  ///   - command: 新しいコマンド設定
  /// - Throws: 設定の保存に失敗した場合
  public func updateCommand(at index: Int, _ command: CustomCommand) throws {
    guard settingsManager.settings.customCommands.indices.contains(index) else { return }
    settingsManager.settings.customCommands[index] = command
    try settingsManager.save()
    onSettingsChanged?(.reloadOnly)
  }

  // MARK: - Excluded Apps Tab

  /// アプリの除外状態をトグルする。
  ///
  /// 除外リストに含まれている場合は削除し、含まれていない場合は追加する。
  /// - Parameter appName: アプリ表示名またはバンドル名（例: "Safari" / "Safari.app"）
  /// - Throws: 設定の保存に失敗した場合
  public func toggleExcludedApp(_ appName: String) throws {
    if let index = settingsManager.settings.excludedApps.firstIndex(of: appName) {
      settingsManager.settings.excludedApps.remove(at: index)
    } else {
      settingsManager.settings.excludedApps.append(appName)
    }
    try settingsManager.save()
    onSettingsChanged?(.cacheInvalidated)
  }

  /// アプリが除外リストに含まれているかどうかを返す。
  ///
  /// - Parameter appName: アプリ表示名またはバンドル名（例: "Safari" / "Safari.app"）
  /// - Returns: 除外リストに含まれている場合は `true`
  public func isAppExcluded(_ appName: String) -> Bool {
    settingsManager.settings.excludedApps.contains(appName)
  }
}
