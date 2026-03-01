import AppKit
import Foundation
import SwiftUI
import os

/// アプリケーション全体のコンポーネントを統合し、ライフサイクルを管理するコーディネーター。
///
/// `AppDelegate` → `GlobalShortcutManager` → `WindowManager` → `LauncherPanel` →
/// `LauncherView` → `SearchService` の全フローを接続し、
/// ランチャー表示・検索・起動・設定変更の一連の動作を統括する。
@MainActor
@Observable
public final class AppCoordinator {

  private static let logger = Logger(
    subsystem: "com.ignitero.launcher", category: "AppCoordinator")

  // MARK: - Core Services

  /// 設定の永続化管理
  public let settingsManager: SettingsManager

  /// キャッシュデータベース
  public let cacheDatabase: any CacheDatabaseProtocol

  /// ウィンドウ表示/非表示管理
  public let windowManager: WindowManager

  /// ファジー検索サービス
  public let searchService: SearchService

  /// 計算式評価エンジン
  public let calculatorEngine: CalculatorEngine

  /// IME 制御コントローラ
  public let imeController: any IMEControlling

  /// アプリ/ディレクトリ/コマンド起動サービス
  public let launchService: any Launching

  /// アイコンキャッシュ管理
  public let iconCacheManager: IconCacheManager

  /// アプリケーションスキャナー
  public let appScanner: any AppScannerProtocol

  /// ディレクトリスキャナー
  public let directoryScanner: any DirectoryScannerProtocol

  /// 選択履歴
  public let selectionHistory: SelectionHistory

  // MARK: - App-Level Coordinators

  /// グローバルショートカット管理
  public let globalShortcut: GlobalShortcutManager

  /// メニューバーアクション
  public let menuBarActions: MenuBarActions

  /// キャッシュ初期スキャン/自動更新
  public let cacheBootstrap: CacheBootstrap

  /// アップデートチェッカー
  public let updateChecker: UpdateChecker

  // MARK: - UI Components

  /// ランチャービューモデル
  public let launcherViewModel: LauncherViewModel

  /// 設定ビューモデル
  public let settingsViewModel: SettingsViewModel

  /// ランチャーパネル
  public let launcherPanel: LauncherPanel

  /// エディタピッカーパネル
  public let editorPickerPanel: EditorPickerPanel

  /// ターミナルピッカーパネル
  public let terminalPickerPanel: TerminalPickerPanel

  /// Emoji ピッカーパネル
  public let emojiPickerPanel: EmojiPickerPanel

  /// 起動処理がすべて完了し、操作可能な状態かどうか
  public private(set) var isReady: Bool = false

  // MARK: - Initialization

  /// AppCoordinator を初期化し、全コンポーネントを接続する。
  ///
  /// - Parameters:
  ///   - settingsManager: 設定管理（テスト時に差し替え可能）
  ///   - cacheDatabase: キャッシュ DB（テスト時に差し替え可能）
  ///   - imeController: IME 制御（テスト時に差し替え可能）
  ///   - launchService: 起動サービス（テスト時に差し替え可能）
  ///   - appScanner: アプリスキャナー（テスト時に差し替え可能）
  ///   - directoryScanner: ディレクトリスキャナー（テスト時に差し替え可能）
  ///   - selectionHistory: 選択履歴（テスト時に差し替え可能）
  ///   - urlSession: HTTP セッション（テスト時に差し替え可能）
  public init(
    settingsManager: SettingsManager? = nil,
    cacheDatabase: (any CacheDatabaseProtocol)? = nil,
    imeController: (any IMEControlling)? = nil,
    launchService: (any Launching)? = nil,
    appScanner: (any AppScannerProtocol)? = nil,
    directoryScanner: (any DirectoryScannerProtocol)? = nil,
    selectionHistory: SelectionHistory? = nil,
    urlSession: (any URLSessionProtocol)? = nil,
    shortcutDebounceInterval: Duration = .milliseconds(300)
  ) {
    // Core services
    let settings = settingsManager ?? SettingsManager()
    self.settingsManager = settings

    if let db = cacheDatabase {
      self.cacheDatabase = db
    } else {
      let dbPath = Self.defaultDatabasePath()
      do {
        self.cacheDatabase = try CacheDatabase(path: dbPath)
      } catch {
        Self.logger.error("Failed to open cache database: \(error.localizedDescription)")
        // Fallback to in-memory database
        do {
          self.cacheDatabase = try CacheDatabase(inMemory: true)
        } catch {
          fatalError("Failed to create in-memory cache database: \(error)")
        }
      }
    }

    self.searchService = SearchService()
    self.calculatorEngine = CalculatorEngine()
    self.imeController = imeController ?? IMEController()
    self.launchService = launchService ?? LaunchService()
    self.iconCacheManager = IconCacheManager()

    let scanner = appScanner ?? AppScanner(iconCacheManager: self.iconCacheManager)
    self.appScanner = scanner

    let dirScanner = directoryScanner ?? DirectoryScanner()
    self.directoryScanner = dirScanner

    let history =
      selectionHistory
      ?? SelectionHistory(filePath: Self.defaultHistoryPath())
    self.selectionHistory = history

    // Window Manager
    let wm = WindowManager()
    self.windowManager = wm

    // Global Shortcut
    self.globalShortcut = GlobalShortcutManager(
      windowManager: wm,
      imeController: self.imeController,
      debounceInterval: shortcutDebounceInterval
    )

    // Menu Bar Actions
    self.menuBarActions = MenuBarActions(
      windowManager: wm,
      settingsManager: settings,
      appScanner: scanner,
      directoryScanner: dirScanner
    )

    // Cache Bootstrap
    self.cacheBootstrap = CacheBootstrap(
      settingsManager: settings,
      cacheDatabase: self.cacheDatabase,
      appScanner: scanner,
      directoryScanner: dirScanner
    )

    // Update Checker
    self.updateChecker = UpdateChecker(
      session: urlSession ?? URLSession.shared,
      settingsManager: settings
    )

    // View Models
    let launcherVM = LauncherViewModel(
      searchService: self.searchService,
      calculatorEngine: self.calculatorEngine
    )
    self.launcherViewModel = launcherVM

    let settingsVM = SettingsViewModel(settingsManager: settings)
    // インストール済みエディタ/ターミナルを設定
    if let ls = self.launchService as? LaunchService {
      settingsVM.installedEditors = ls.availableEditors().filter { $0.installed }
      settingsVM.installedTerminals = ls.availableTerminals().filter { $0.installed }
    }
    self.settingsViewModel = settingsVM

    // Panels
    self.launcherPanel = LauncherPanel()
    self.editorPickerPanel = EditorPickerPanel()
    self.terminalPickerPanel = TerminalPickerPanel()
    self.emojiPickerPanel = EmojiPickerPanel()

    // Wire launcher panel to window manager
    wm.launcherPanel = self.launcherPanel

    // ランチャー表示時に前回の検索をクリアし、検索フィールドにフォーカスを要求する
    // 設定変更時にランチャーのデータを再読み込み
    settingsViewModel.onSettingsChanged = { [weak self] in
      self?.reloadDataFromSettings()
    }

    wm.onShowLauncher = { [weak self] in
      guard let self else { return }
      self.launcherViewModel.clearSearch()
      self.windowManager.resizeForResults(count: 0)
      self.launcherViewModel.focusTrigger += 1
    }

    // モニター経由の自動非表示時に検索もクリアする
    wm.onAutoDismiss = { [weak self] in
      self?.launcherViewModel.clearSearch()
    }

    // キーイベントモニターのハンドラ設定
    wm.onKeyEvent = { [weak self] event -> Bool in
      guard let self else { return false }
      return self.handleLauncherKeyEvent(event)
    }

    // ピッカーを全て閉じるコールバック（ショートカットでトグル時に使用）
    wm.onCloseAllPickers = { [weak self] in
      guard let self else { return }
      self.editorPickerPanel.dismissPanel()
      self.terminalPickerPanel.dismiss()
      self.emojiPickerPanel.dismissPanel()
    }
  }

  // MARK: - Lifecycle

  /// アプリケーション起動時の初期化フローを実行する。
  ///
  /// 1. 設定の読み込み
  /// 2. 選択履歴の読み込み
  /// 3. グローバルショートカットの登録
  /// 4. ランチャーパネルへの SwiftUI ビュー設定
  /// 5. 初期キャッシュスキャン
  /// 6. アップデートチェック
  /// 7. 自動更新タイマーの開始（有効な場合）
  public func start() async {
    // 1. Load settings
    do {
      try settingsManager.load()
      Self.logger.info("Settings loaded")
    } catch {
      Self.logger.error("Failed to load settings: \(error.localizedDescription)")
    }

    // 2. Load selection history
    do {
      try selectionHistory.load()
      Self.logger.info("Selection history loaded")
    } catch {
      Self.logger.error("Failed to load selection history: \(error.localizedDescription)")
    }

    // 3. Set up global shortcut
    globalShortcut.setup()
    Self.logger.info("Global shortcut registered")

    // 4. Set up launcher panel with LauncherView
    setupLauncherView()

    // 5. Perform initial cache scan
    await cacheBootstrap.performInitialScan()
    await loadCacheDataIntoViewModel()
    Self.logger.info("Initial cache scan completed")

    // 6. Check for updates
    await checkForUpdates()

    // 7. Start auto-update timer if enabled
    cacheBootstrap.startAutoUpdate()

    // 起動完了
    isReady = true
    Self.logger.info("App coordinator started")
  }

  /// アプリケーション終了時のクリーンアップを実行する。
  ///
  /// ショートカットの解除、自動更新の停止、状態の保存を行う。
  public func shutdown() {
    // Tear down shortcuts
    globalShortcut.teardown()

    // Stop auto-update
    cacheBootstrap.stopAutoUpdate()

    // Save selection history
    do {
      try selectionHistory.save()
    } catch {
      Self.logger.error("Failed to save selection history: \(error.localizedDescription)")
    }

    // Save window position
    windowManager.savePanelPosition()

    // Save settings
    do {
      try settingsManager.save()
    } catch {
      Self.logger.error("Failed to save settings: \(error.localizedDescription)")
    }

    Self.logger.info("App coordinator shut down")
  }

  // MARK: - Launcher Flow

  /// 検索結果を選択実行する。
  ///
  /// 結果の種別に応じてアプリ起動、ディレクトリオープン、コマンド実行を行い、
  /// 選択履歴を記録してランチャーを非表示にする。
  /// - Parameter result: 実行する検索結果
  public func executeResult(_ result: SearchResult) {
    // Record selection history
    selectionHistory.record(
      keyword: launcherViewModel.searchQuery,
      path: result.path
    )

    // Update history in view model
    launcherViewModel.history = selectionHistory.allEntries

    // Instant actions (synchronous — run while app is still active)
    switch result.kind {
    case .webSearch:
      if let url = URL(string: result.path) {
        NSWorkspace.shared.open(url)
      }
      dismissLauncher()
      return
    case .emoji:
      dismissLauncher()
      showEmojiPicker()
      return
    case .colorPicker:
      dismissLauncher()
      Task {
        try? await Task.sleep(nanoseconds: 300_000_000)
        self.showColorPicker()
      }
      return
    default:
      break
    }

    // Async actions (app, directory, command)
    Task {
      do {
        switch result.kind {
        case .app:
          try await launchService.launchApp(at: result.path)
        case .directory:
          let editorType = result.editor.flatMap { EditorType(rawValue: $0) }
          try await launchService.openDirectory(result.path, editor: editorType)
        case .command:
          if let command = result.command {
            let terminal = settingsManager.settings.defaultTerminal
            try await launchService.executeCommand(
              command,
              workingDirectory: result.workingDirectory,
              terminal: terminal
            )
          }
        default:
          break
        }
      } catch {
        Self.logger.error("Failed to execute result: \(error.localizedDescription)")
      }
    }

    // Clear search and dismiss
    dismissLauncher()
  }

  /// ランチャーパネルのキーダウンイベントを処理する。
  ///
  /// TextField がキーを消費する前にインターセプトし、
  /// 矢印キー・Escape・左右キー（エディタ/ターミナルピッカー）を処理する。
  /// - Parameter event: キーダウンイベント
  /// - Returns: イベントを消費した場合は `true`
  private func handleLauncherKeyEvent(_ event: NSEvent) -> Bool {
    Self.logger.debug(
      "Key event: keyCode=\(event.keyCode), modifiers=\(event.modifierFlags.rawValue)")
    switch event.keyCode {
    case 126:  // Up arrow
      launcherViewModel.moveSelectionUp()
      HapticService.selectionChanged()
      return true
    case 125:  // Down arrow
      launcherViewModel.moveSelectionDown()
      HapticService.selectionChanged()
      return true
    case 53:  // Escape
      dismissLauncher()
      return true
    case 123:  // Left arrow
      Self.logger.debug(
        "Left arrow: results=\(self.launcherViewModel.searchResults.count), index=\(self.launcherViewModel.selectedIndex)"
      )
      if let action = launcherViewModel.handleSpecialKey(.left, modifiers: event.modifierFlags) {
        Self.logger.debug("Left arrow action: \(String(describing: action))")
        handleSpecialKeyAction(action)
        return true
      }
      Self.logger.debug("Left arrow: no action (no directory selected?)")
      return false
    case 124:  // Right arrow
      Self.logger.debug(
        "Right arrow: results=\(self.launcherViewModel.searchResults.count), index=\(self.launcherViewModel.selectedIndex)"
      )
      if let action = launcherViewModel.handleSpecialKey(.right, modifiers: event.modifierFlags) {
        Self.logger.debug("Right arrow action: \(String(describing: action))")
        handleSpecialKeyAction(action)
        return true
      }
      Self.logger.debug("Right arrow: no action (no directory selected?)")
      return false
    default:
      return false
    }
  }

  /// SpecialKeyAction を実行する。
  private func handleSpecialKeyAction(_ action: SpecialKeyAction) {
    switch action {
    case .dismiss:
      dismissLauncher()
    case .execute:
      if let result = launcherViewModel.confirmSelection() {
        executeResult(result)
      }
    case .copyCalculator:
      launcherViewModel.copyCalculatorResult()
    case .openInTerminal:
      if let result = launcherViewModel.confirmSelection() {
        openInTerminal(result.path)
      }
    case .showEditorPicker:
      if let result = launcherViewModel.confirmSelection() {
        let currentEditor = result.editor.flatMap { EditorType(rawValue: $0) }
        showEditorPicker(for: result.path, currentEditor: currentEditor)
      }
    case .showTerminalPicker:
      if let result = launcherViewModel.confirmSelection() {
        showTerminalPicker(for: result.path)
      }
    }
  }

  /// ランチャーを非表示にし、検索状態をクリアする。
  public func dismissLauncher() {
    launcherViewModel.clearSearch()
    windowManager.resizeForResults(count: 0)
    windowManager.hideLauncher()
  }

  /// カラーピッカーを表示し、選択色の HEX をクリップボードにコピーする。
  private func showColorPicker() {
    NSColorSampler().show { selectedColor in
      guard let selectedColor else { return }
      guard let color = selectedColor.usingColorSpace(.sRGB) else { return }
      let r = Int(color.redComponent * 255)
      let g = Int(color.greenComponent * 255)
      let b = Int(color.blueComponent * 255)
      let hex = String(format: "#%02X%02X%02X", r, g, b)
      Task { @MainActor in
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hex, forType: .string)
      }
    }
  }

  /// Emoji ピッカーを表示し、選択された絵文字をクリップボードにコピーする。
  private func showEmojiPicker() {
    emojiPickerPanel.show { emoji in
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(emoji, forType: .string)
      HapticService.confirmed()
    }
    emojiPickerPanel.onDismiss = { [weak self] in
      self?.emojiPickerPanel.onDismiss = nil
    }
  }

  /// デフォルトターミナルで指定ディレクトリを開く。
  ///
  /// - Parameter path: ディレクトリパス
  public func openInTerminal(_ path: String) {
    let terminal = settingsManager.settings.defaultTerminal
    Task {
      do {
        try await launchService.openInTerminal(path, terminal: terminal)
      } catch {
        Self.logger.error("Failed to open in terminal: \(error.localizedDescription)")
      }
    }
    dismissLauncher()
  }

  /// エディタピッカーを表示する。
  ///
  /// Tauri と同様のフロー: ランチャーを隠す → ピッカーを最前面に表示。
  /// - Parameters:
  ///   - directoryPath: 開くディレクトリのパス
  ///   - currentEditor: 初期選択するエディタ（ディレクトリに紐づくエディタ）
  public func showEditorPicker(for directoryPath: String, currentEditor: EditorType? = nil) {
    let allEditors = (launchService as? LaunchService)?.availableEditors() ?? []
    let editors = allEditors.filter { $0.installed }
    let frame = launcherPanel.frame

    // デフォルト選択: ディレクトリに紐づくエディタ → 設定のデフォルトエディタの順でフォールバック
    let defaultIndex =
      currentEditor.flatMap { editor in
        editors.firstIndex { $0.id == editor }
      } ?? editors.firstIndex { $0.id == settingsManager.settings.defaultEditor }

    // ピッカーを先に表示（hidesOnDeactivate 対策: キーウィンドウを維持）
    windowManager.showPicker()
    editorPickerPanel.show(
      relativeTo: frame, editors: editors, directoryPath: directoryPath,
      defaultIndex: defaultIndex)

    // ピッカーがキーウィンドウになった後にランチャーを隠す
    windowManager.hideLauncher()

    // ピッカー閉じた時のコールバック
    editorPickerPanel.onDismiss = { [weak self] in
      self?.windowManager.hidePicker()
    }

    // EditorPickerPanel の確定監視を設定
    setupEditorPickerObservation(directoryPath: directoryPath)
  }

  /// ターミナルピッカーを表示する。
  ///
  /// Tauri と同様のフロー: ランチャーを隠す → ピッカーを最前面に表示。
  /// - Parameter directoryPath: 開くディレクトリのパス
  public func showTerminalPicker(for directoryPath: String) {
    let allTerminals = (launchService as? LaunchService)?.availableTerminals() ?? []
    let terminals = allTerminals.filter { $0.installed }
    let frame = launcherPanel.frame

    // デフォルト選択: 設定のデフォルトターミナルのインデックスを特定
    let defaultTerminal = settingsManager.settings.defaultTerminal
    let defaultIndex = terminals.firstIndex { $0.id == defaultTerminal } ?? 0

    // ピッカーを先に表示（hidesOnDeactivate 対策: キーウィンドウを維持）
    windowManager.showPicker()
    terminalPickerPanel.show(relativeTo: frame, terminals: terminals, defaultIndex: defaultIndex)

    // ピッカーがキーウィンドウになった後にランチャーを隠す
    windowManager.hideLauncher()
    Self.logger.info("showTerminalPicker: panel visible=\(self.terminalPickerPanel.isVisible)")

    // TerminalPickerPanel のコールバック設定
    terminalPickerPanel.onSelect = { [weak self] terminal in
      guard let self else { return }
      Task {
        do {
          try await self.launchService.openInTerminal(directoryPath, terminal: terminal)
        } catch {
          Self.logger.error(
            "Failed to open in terminal picker: \(error.localizedDescription)")
        }
      }
      self.windowManager.hidePicker()
    }

    terminalPickerPanel.onDismiss = { [weak self] in
      self?.windowManager.hidePicker()
    }
  }

  // MARK: - Settings Integration

  /// 設定変更後にキャッシュデータを再読み込みする。
  ///
  /// 設定画面でディレクトリやコマンドが変更された際に呼び出す。
  public func reloadDataFromSettings() {
    launcherViewModel.commands = settingsManager.settings.customCommands
    let terminalType = settingsManager.settings.defaultTerminal
    launcherViewModel.defaultTerminalName = LaunchService.displayName(for: terminalType)
  }

  // MARK: - Private Helpers

  /// ランチャーパネルに LauncherView を設定する。
  private func setupLauncherView() {
    let view = LauncherView(
      viewModel: launcherViewModel,
      onExecute: { [weak self] result in
        self?.executeResult(result)
      },
      onDismiss: { [weak self] in
        self?.dismissLauncher()
      },
      onShowEditorPicker: { [weak self] path in
        self?.showEditorPicker(for: path)
      },
      onShowTerminalPicker: { [weak self] path in
        self?.showTerminalPicker(for: path)
      },
      onOpenInTerminal: { [weak self] path in
        self?.openInTerminal(path)
      },
      onResultsCountChanged: { [weak self] count in
        self?.windowManager.resizeForResults(count: count)
      },
      onRefreshCache: { [weak self] in
        guard let self else { return }
        Task { @MainActor in
          await self.rebuildCacheAndReload()
        }
      },
      onOpenSettings: { [weak self] in
        self?.menuBarActions.openSettings()
      }
    )

    launcherPanel.setContentView(view)

    // Restore window position
    windowManager.restorePanelPosition()

    // Set initial size
    let frame = NSRect(
      x: launcherPanel.frame.origin.x,
      y: launcherPanel.frame.origin.y,
      width: WindowManager.width,
      height: WindowManager.minHeight
    )
    launcherPanel.setFrame(frame, display: true)
  }

  /// キャッシュを再構築し、ビューモデルにデータを再読み込みする。
  public func rebuildCacheAndReload() async {
    launcherViewModel.isScanning = true
    await cacheBootstrap.rebuildCache()
    await loadCacheDataIntoViewModel()
    launcherViewModel.isScanning = false
  }

  /// キャッシュデータをビューモデルに読み込む。
  private func loadCacheDataIntoViewModel() async {
    if let db = cacheDatabase as? CacheDatabase {
      do {
        let apps = try await db.loadApps()
        let directories = try await db.loadDirectories()
        launcherViewModel.apps = apps
        launcherViewModel.directories = directories
      } catch {
        Self.logger.error("Failed to load cache data: \(error.localizedDescription)")
      }
    }

    // Load commands from settings
    launcherViewModel.commands = settingsManager.settings.customCommands

    // Load history
    launcherViewModel.history = selectionHistory.allEntries

    // Load editor icon paths
    let editors = launchService.availableEditors()
    var iconPaths: [String: String] = [:]
    for editor in editors where editor.installed {
      if let iconPath = editor.iconPath {
        iconPaths[editor.id.rawValue] = iconPath
      }
    }
    launcherViewModel.editorIconPaths = iconPaths

    // Load default terminal display name
    let terminalType = settingsManager.settings.defaultTerminal
    launcherViewModel.defaultTerminalName = LaunchService.displayName(for: terminalType)

    // Load all apps (without exclusion filter) for settings excluded apps tab
    do {
      let allApps = try appScanner.scanApplications(excludedApps: [])
      settingsViewModel.allApps = allApps
    } catch {
      Self.logger.error("Failed to scan apps for settings: \(error.localizedDescription)")
    }
  }

  /// アップデートチェックを実行する。
  private func checkForUpdates() async {
    let result = await updateChecker.checkForUpdate(currentVersion: Ignitero.version)
    if let result {
      launcherViewModel.showUpdateBanner(version: result.latestVersion)
    }
  }

  /// エディタピッカーの確定監視を設定する。
  private func setupEditorPickerObservation(directoryPath: String) {
    // エディタピッカーの状態変化を polling で監視するタスク
    Task { @MainActor [weak self] in
      guard let self else { return }
      let state = self.editorPickerPanel.pickerState

      // 確定またはキャンセルまで待機
      while !state.isDismissed && state.confirmedEditor == nil {
        try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
      }

      if let editor = state.confirmedEditor {
        Task {
          do {
            try await self.launchService.openDirectory(directoryPath, editor: editor)
          } catch {
            Self.logger.error(
              "Failed to open in editor: \(error.localizedDescription)")
          }
        }
      }

      self.windowManager.hidePicker()
      if state.confirmedEditor != nil {
        // エディタ確定時はランチャーの検索もクリア
        self.launcherViewModel.clearSearch()
        self.windowManager.resizeForResults(count: 0)
      }
    }
  }

  // MARK: - Default Paths

  /// デフォルトのデータベースファイルパスを返す。
  private static func defaultDatabasePath() -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let dir = home.appendingPathComponent(".cache/ignitero-launcher")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("cache.db").path
  }

  /// デフォルトの選択履歴ファイルパスを返す。
  private static func defaultHistoryPath() -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let dir = home.appendingPathComponent(".config/ignitero-launcher")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("selection_history.json").path
  }
}
