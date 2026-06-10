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

  // MARK: - Callbacks

  /// スキャン完了（DB 保存後）に呼ばれるコールバック。
  /// 自動更新を含む全スキャン経路でビューモデルへの再読込を一本化するために使う。
  /// 引数は除外フィルタ適用前の全アプリ一覧（設定画面の除外アプリ一覧用）。
  public var onScanCompleted: (@MainActor ([AppItem]) async -> Void)?

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
  /// - Returns: スキャンが完了しキャッシュが更新された場合は `true`
  ///   （呼び出し側はキャッシュからの再読込要否の判断に使う）
  @discardableResult
  public func performInitialScan() async -> Bool {
    let shouldScan: Bool
    do {
      let cacheIsEmpty = try cacheDatabase.isEmpty()
      let updateOnStartup = settingsManager.settings.cacheUpdate.updateOnStartup
      shouldScan = cacheIsEmpty || updateOnStartup
    } catch {
      Self.logger.error("Failed to check cache status: \(error.localizedDescription)")
      return false
    }

    guard shouldScan else {
      Self.logger.info("Cache is populated and updateOnStartup is disabled; skipping initial scan")
      return false
    }

    return await runScan()
  }

  // MARK: - Auto Update

  /// 自動更新が有効な場合、設定された間隔でバックグラウンドキャッシュ更新を開始する。
  ///
  /// 既存のタイマーは常に停止してから設定を反映するため、
  /// 設定変更後の再呼び出しで「有効→無効」「間隔変更」のどちらも反映される。
  public func startAutoUpdate() {
    // 設定にかかわらず既存のタスクを止め、現在の設定でやり直す
    stopAutoUpdate()

    let settings = settingsManager.settings.cacheUpdate
    guard settings.autoUpdateEnabled else {
      Self.logger.info("Auto update is disabled; not starting background task")
      return
    }

    let intervalNanoseconds = Self.autoUpdateIntervalNanoseconds(
      hours: settings.autoUpdateIntervalHours)

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
  ///
  /// saveApps/saveDirectories が DELETE+INSERT を同一トランザクションで行うため、
  /// 事前の clearCache は不要（スキャン失敗時に空キャッシュが残る事故も防げる）。
  public func rebuildCache() async {
    await runScan()
  }

  // MARK: - Internal

  /// 自動更新インターバル（時間）をナノ秒に変換する。
  /// オーバーフロー防止のため 1〜8760 時間（1年）にクランプする。
  nonisolated static func autoUpdateIntervalNanoseconds(hours: Int) -> UInt64 {
    let clamped = UInt64(max(min(hours, 8760), 1))
    return clamped * 3600 * 1_000_000_000
  }

  // MARK: - Private

  /// アプリスキャンとディレクトリスキャンを実行し、結果をデータベースに保存する。
  /// - Returns: スキャンが完了しキャッシュが更新された場合は `true`
  @discardableResult
  private func runScan() async -> Bool {
    guard !isScanning else {
      Self.logger.info("Scan already in progress; skipping")
      return false
    }
    isScanning = true
    defer {
      isScanning = false
      lastScanDate = Date()
    }

    let settings = settingsManager.settings

    // アプリスキャン（除外フィルタ前の全アプリ。設定画面の除外アプリ一覧にも使う）
    // スキャンはバックグラウンドで実行されるため、メインスレッドはブロックされない。
    let scannedAllApps: [AppItem]
    do {
      scannedAllApps = try await appScanner.scanApplications(excludedApps: [])
    } catch {
      // 失敗時は既存キャッシュを保持する（空配列で上書きしない）
      Self.logger.error("App scan failed: \(error.localizedDescription)")
      return false
    }

    // ランチャー用に除外フィルタを適用する
    var allApps = scannedAllApps.filter {
      !appScanner.isExcluded($0, excludedApps: settings.excludedApps)
    }

    // ディレクトリスキャン
    let allDirectories: [DirectoryItem]
    do {
      let scanResult = try directoryScanner.scan(directories: settings.registeredDirectories)
      allDirectories = scanResult.directories
      allApps.append(contentsOf: scanResult.apps)
    } catch {
      // 失敗時は既存キャッシュを保持する
      Self.logger.error("Directory scan failed: \(error.localizedDescription)")
      return false
    }

    // データベースに保存（saveApps/saveDirectories は DELETE+INSERT を
    // 同一トランザクションで行うため、置換はアトミック）
    do {
      try cacheDatabase.saveApps(allApps)
      try cacheDatabase.saveDirectories(allDirectories)
    } catch {
      Self.logger.error("Failed to save scan results: \(error.localizedDescription)")
    }

    Self.logger.info(
      "Scan completed: \(allApps.count) apps, \(allDirectories.count) directories")

    // 全スキャン経路（起動時・自動更新・手動再構築）共通で完了を通知する
    await onScanCompleted?(scannedAllApps)
    return true
  }
}
