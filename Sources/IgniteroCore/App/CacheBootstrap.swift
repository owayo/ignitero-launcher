import Foundation
import os

@MainActor
@Observable
public final class CacheBootstrap {
  private static let logger = Logger(
    subsystem: "com.ignitero.launcher", category: "CacheBootstrap")

  // MARK: - Dependencies

  private let settingsManager: SettingsManager
  private let cacheDatabase: any CacheDatabaseProtocol
  private let appScanner: any AppScannerProtocol
  private let directoryScanner: any DirectoryScannerProtocol

  // MARK: - Observable Properties

  public private(set) var isScanning: Bool = false
  public var autoUpdateTask: Task<Void, Never>?
  public private(set) var lastScanDate: Date?

  // MARK: - Initialization

  public init(
    settingsManager: SettingsManager,
    cacheDatabase: any CacheDatabaseProtocol,
    appScanner: any AppScannerProtocol,
    directoryScanner: any DirectoryScannerProtocol
  ) {
    self.settingsManager = settingsManager
    self.cacheDatabase = cacheDatabase
    self.appScanner = appScanner
    self.directoryScanner = directoryScanner
  }

  // MARK: - Initial Scan

  /// 起動時のキャッシュ構築を実行する。
  /// キャッシュが空、または起動時更新設定が有効な場合にスキャンを実行する。
  public func performInitialScan() async {
    let shouldScan: Bool
    do {
      let cacheIsEmpty = try cacheDatabase.isEmpty()
      let updateOnStartup = settingsManager.settings.cacheUpdate.updateOnStartup
      shouldScan = cacheIsEmpty || updateOnStartup
    } catch {
      Self.logger.error("Failed to check cache status: \(error.localizedDescription)")
      return
    }

    guard shouldScan else {
      Self.logger.info("Cache is populated and updateOnStartup is disabled; skipping initial scan")
      return
    }

    await runScan()
  }

  // MARK: - Auto Update

  /// 自動更新が有効な場合、設定された間隔でバックグラウンドキャッシュ更新を開始する。
  public func startAutoUpdate() {
    let settings = settingsManager.settings.cacheUpdate
    guard settings.autoUpdateEnabled else {
      Self.logger.info("Auto update is disabled; not starting background task")
      return
    }

    // 既存のタスクをキャンセル
    stopAutoUpdate()

    let intervalSeconds = UInt64(max(settings.autoUpdateIntervalHours, 1)) * 3600
    let intervalNanoseconds = intervalSeconds * 1_000_000_000

    autoUpdateTask = Task { [weak self] in
      while !Task.isCancelled {
        do {
          try await Task.sleep(nanoseconds: intervalNanoseconds)
        } catch {
          // スリープ中にタスクがキャンセルされた
          break
        }

        guard !Task.isCancelled else { break }

        await self?.runScan()
      }
    }

    Self.logger.info(
      "Auto update started with interval: \(settings.autoUpdateIntervalHours) hours")
  }

  /// バックグラウンド自動更新を停止する。
  public func stopAutoUpdate() {
    autoUpdateTask?.cancel()
    autoUpdateTask = nil
  }

  // MARK: - Rebuild Cache

  /// 強制的にキャッシュを再構築する（メニューバーアクションから呼び出される）。
  public func rebuildCache() async {
    do {
      try cacheDatabase.clearCache()
    } catch {
      Self.logger.error("Failed to clear cache: \(error.localizedDescription)")
    }
    await runScan()
  }

  // MARK: - Private

  /// アプリスキャンとディレクトリスキャンを実行し、結果をデータベースに保存する。
  private func runScan() async {
    isScanning = true
    // UIがローディング状態を描画できるようメインランループに制御を返す
    await Task.yield()
    defer {
      isScanning = false
      lastScanDate = Date()
    }

    let settings = settingsManager.settings

    // アプリスキャン
    var allApps: [AppItem] = []
    do {
      let scannedApps = try appScanner.scanApplications(excludedApps: settings.excludedApps)
      allApps.append(contentsOf: scannedApps)
    } catch {
      Self.logger.error("App scan failed: \(error.localizedDescription)")
    }

    // ディレクトリスキャン
    var allDirectories: [DirectoryItem] = []
    do {
      let scanResult = try directoryScanner.scan(directories: settings.registeredDirectories)
      allDirectories = scanResult.directories
      allApps.append(contentsOf: scanResult.apps)
    } catch {
      Self.logger.error("Directory scan failed: \(error.localizedDescription)")
    }

    // データベースに保存
    do {
      try cacheDatabase.saveApps(allApps)
      try cacheDatabase.saveDirectories(allDirectories)
    } catch {
      Self.logger.error("Failed to save scan results: \(error.localizedDescription)")
    }

    Self.logger.info(
      "Scan completed: \(allApps.count) apps, \(allDirectories.count) directories")
  }
}
