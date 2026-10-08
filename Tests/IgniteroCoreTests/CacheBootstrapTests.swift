import Foundation
import Testing

@testable import IgniteroCore

// MARK: - モック CacheDatabase

private struct CacheBootstrapTestError: Error {}

private final class CacheBootstrapMockDB: CacheDatabaseProtocol, @unchecked Sendable {
  var isEmptyResult: Bool
  var saveAppsCalled = false
  var loadAppsCalled = false
  var saveDirectoriesCalled = false
  var loadDirectoriesCalled = false
  var clearCacheCalled = false
  var savedApps: [AppItem] = []
  var loadedApps: [AppItem] = []
  var savedDirectories: [DirectoryItem] = []
  var loadedDirectories: [DirectoryItem] = []
  /// テスト用: saveApps 呼び出し時に投げるエラー
  var saveAppsError: Error?
  /// テスト用: saveDirectories 呼び出し時に投げるエラー
  var saveDirectoriesError: Error?

  init(isEmpty: Bool = true) {
    self.isEmptyResult = isEmpty
  }

  func isEmpty() throws -> Bool {
    isEmptyResult
  }

  func saveApps(_ apps: [AppItem]) throws {
    saveAppsCalled = true
    if let saveAppsError { throw saveAppsError }
    savedApps = apps
  }

  func loadApps() async throws -> [AppItem] {
    loadAppsCalled = true
    return loadedApps
  }

  func saveDirectories(_ dirs: [DirectoryItem]) throws {
    saveDirectoriesCalled = true
    if let saveDirectoriesError { throw saveDirectoriesError }
    savedDirectories = dirs
  }

  func loadDirectories() async throws -> [DirectoryItem] {
    loadDirectoriesCalled = true
    return loadedDirectories
  }

  /// テスト用: 結合保存 API。CacheBootstrap が利用する経路。
  /// 実装側は単一トランザクションだが、モックでは saveApps / saveDirectories の
  /// 順に呼び出してそれぞれの失敗注入と呼び出し記録を流用する。
  func saveAppsAndDirectories(apps: [AppItem], directories: [DirectoryItem]) throws {
    try saveApps(apps)
    try saveDirectories(directories)
  }

  func clearCache() throws {
    clearCacheCalled = true
  }
}

// MARK: - モック AppScanner

private struct CacheBootstrapMockAppScanner: AppScannerProtocol {
  let apps: [AppItem]

  init(apps: [AppItem] = []) {
    self.apps = apps
  }

  func scanApplications(excludedApps: [String]) throws -> [AppItem] {
    apps
  }
}

// MARK: - モック DirectoryScanner

private struct CacheBootstrapMockDirScanner: DirectoryScannerProtocol {
  let result: ScanResult

  init(result: ScanResult = ScanResult(directories: [], apps: [])) {
    self.result = result
  }

  func scan(directories: [RegisteredDirectory]) throws -> ScanResult {
    result
  }
}

// MARK: - テスト

@Suite("CacheBootstrap")
@MainActor
struct CacheBootstrapTests {

  // MARK: - ヘルパー

  private func makeSettingsManager(
    updateOnStartup: Bool = true,
    autoUpdateEnabled: Bool = false,
    autoUpdateIntervalHours: Int = 6
  ) -> SettingsManager {
    let manager = SettingsManager(
      configDirectory: FileManager.default.temporaryDirectory
        .appendingPathComponent("ignitero-test-\(UUID().uuidString)"))
    manager.settings.cacheUpdate = CacheUpdateSettings(
      updateOnStartup: updateOnStartup,
      autoUpdateEnabled: autoUpdateEnabled,
      autoUpdateIntervalHours: autoUpdateIntervalHours
    )
    return manager
  }

  // MARK: - 初期スキャンテスト

  @Test("Initial scan runs when cache is empty")
  @MainActor
  func initialScanRunsWhenCacheIsEmpty() async throws {
    let mockDB = CacheBootstrapMockDB(isEmpty: true)
    let mockAppScanner = CacheBootstrapMockAppScanner(apps: [
      AppItem(name: "Safari", path: "/Applications/Safari.app")
    ])
    let mockDirScanner = CacheBootstrapMockDirScanner(
      result: ScanResult(
        directories: [DirectoryItem(name: "project", path: "/Users/dev/project")],
        apps: []
      ))
    let settings = makeSettingsManager(updateOnStartup: false)

    let bootstrap = CacheBootstrap(
      settingsManager: settings,
      cacheDatabase: mockDB,
      appScanner: mockAppScanner,
      directoryScanner: mockDirScanner
    )

    await bootstrap.performInitialScan()

    #expect(mockDB.saveAppsCalled == true)
    #expect(mockDB.saveDirectoriesCalled == true)
  }

  @Test("Initial scan runs when updateOnStartup is true")
  @MainActor
  func initialScanRunsWhenUpdateOnStartupIsTrue() async throws {
    let mockDB = CacheBootstrapMockDB(isEmpty: false)
    let mockAppScanner = CacheBootstrapMockAppScanner(apps: [
      AppItem(name: "Safari", path: "/Applications/Safari.app")
    ])
    let mockDirScanner = CacheBootstrapMockDirScanner()
    let settings = makeSettingsManager(updateOnStartup: true)

    let bootstrap = CacheBootstrap(
      settingsManager: settings,
      cacheDatabase: mockDB,
      appScanner: mockAppScanner,
      directoryScanner: mockDirScanner
    )

    await bootstrap.performInitialScan()

    #expect(mockDB.saveAppsCalled == true)
  }

  @Test("Initial scan skips when cache not empty AND updateOnStartup is false")
  @MainActor
  func initialScanSkipsWhenCacheNotEmptyAndUpdateOnStartupFalse() async throws {
    let mockDB = CacheBootstrapMockDB(isEmpty: false)
    let mockAppScanner = CacheBootstrapMockAppScanner()
    let mockDirScanner = CacheBootstrapMockDirScanner()
    let settings = makeSettingsManager(updateOnStartup: false)

    let bootstrap = CacheBootstrap(
      settingsManager: settings,
      cacheDatabase: mockDB,
      appScanner: mockAppScanner,
      directoryScanner: mockDirScanner
    )

    await bootstrap.performInitialScan()

    #expect(mockDB.saveAppsCalled == false)
    #expect(mockDB.saveDirectoriesCalled == false)
  }

  // MARK: - キャッシュ再構築 テスト

  @Test("rebuildCache always runs scan")
  @MainActor
  func rebuildCacheAlwaysRunsScan() async throws {
    let mockDB = CacheBootstrapMockDB(isEmpty: false)
    let testApps = [
      AppItem(name: "Xcode", path: "/Applications/Xcode.app")
    ]
    let mockAppScanner = CacheBootstrapMockAppScanner(apps: testApps)
    let mockDirScanner = CacheBootstrapMockDirScanner(
      result: ScanResult(
        directories: [DirectoryItem(name: "src", path: "/src")],
        apps: []
      ))
    let settings = makeSettingsManager(updateOnStartup: false)

    let bootstrap = CacheBootstrap(
      settingsManager: settings,
      cacheDatabase: mockDB,
      appScanner: mockAppScanner,
      directoryScanner: mockDirScanner
    )

    await bootstrap.rebuildCache()

    // saveApps/saveDirectories が DELETE+INSERT で置換するため
    // 事前の clearCache は行わない（スキャン失敗時の空キャッシュ防止）
    #expect(mockDB.clearCacheCalled == false)
    #expect(mockDB.saveAppsCalled == true)
    #expect(mockDB.saveDirectoriesCalled == true)
  }

  @Test("rebuildCache saves scanned apps to database")
  @MainActor
  func rebuildCacheSavesScannedApps() async throws {
    let mockDB = CacheBootstrapMockDB(isEmpty: false)
    let testApps = [
      AppItem(name: "Safari", path: "/Applications/Safari.app"),
      AppItem(name: "Xcode", path: "/Applications/Xcode.app"),
    ]
    let mockAppScanner = CacheBootstrapMockAppScanner(apps: testApps)
    let testDirs = [DirectoryItem(name: "project", path: "/project")]
    let mockDirScanner = CacheBootstrapMockDirScanner(
      result: ScanResult(
        directories: testDirs,
        apps: [AppItem(name: "DirApp", path: "/project/DirApp.app")]
      ))
    let settings = makeSettingsManager(updateOnStartup: false)

    let bootstrap = CacheBootstrap(
      settingsManager: settings,
      cacheDatabase: mockDB,
      appScanner: mockAppScanner,
      directoryScanner: mockDirScanner
    )

    await bootstrap.rebuildCache()

    // 両方のスキャナーが返したアプリを統合する
    #expect(mockDB.savedApps.count == 3)
    #expect(mockDB.savedApps.contains { $0.name == "Safari" })
    #expect(mockDB.savedApps.contains { $0.name == "DirApp" })
    #expect(mockDB.savedDirectories.count == 1)
    #expect(mockDB.savedDirectories[0].name == "project")
  }

  @Test("saveApps が失敗した場合は onScanCompleted を呼ばずに false を返す")
  @MainActor
  func saveAppsFailureSkipsOnScanCompleted() async throws {
    let mockDB = CacheBootstrapMockDB(isEmpty: true)
    mockDB.saveAppsError = CacheBootstrapTestError()
    let mockAppScanner = CacheBootstrapMockAppScanner(apps: [
      AppItem(name: "App", path: "/Applications/App.app")
    ])
    let mockDirScanner = CacheBootstrapMockDirScanner()
    let settings = makeSettingsManager(updateOnStartup: true)

    let bootstrap = CacheBootstrap(
      settingsManager: settings,
      cacheDatabase: mockDB,
      appScanner: mockAppScanner,
      directoryScanner: mockDirScanner
    )

    var notifiedAppsCount: Int?
    bootstrap.onScanCompleted = { apps in
      notifiedAppsCount = apps.count
    }

    let result = await bootstrap.performInitialScan()
    #expect(result == false)
    // 保存失敗時は完了通知を行わない（ViewModel の再読込で古いキャッシュと
    // スキャン結果の整合性が崩れるのを防ぐ）
    #expect(notifiedAppsCount == nil)
  }

  @Test("saveDirectories が失敗した場合も onScanCompleted を呼ばずに false を返す")
  @MainActor
  func saveDirectoriesFailureSkipsOnScanCompleted() async throws {
    let mockDB = CacheBootstrapMockDB(isEmpty: true)
    mockDB.saveDirectoriesError = CacheBootstrapTestError()
    let mockAppScanner = CacheBootstrapMockAppScanner(apps: [
      AppItem(name: "App", path: "/Applications/App.app")
    ])
    let mockDirScanner = CacheBootstrapMockDirScanner()
    let settings = makeSettingsManager(updateOnStartup: true)

    let bootstrap = CacheBootstrap(
      settingsManager: settings,
      cacheDatabase: mockDB,
      appScanner: mockAppScanner,
      directoryScanner: mockDirScanner
    )

    var notified = false
    bootstrap.onScanCompleted = { _ in
      notified = true
    }

    let result = await bootstrap.performInitialScan()
    #expect(result == false)
    #expect(notified == false)
  }

  // MARK: - isScanningフラグのテスト

  @Test("isScanning flag toggles correctly during scan")
  @MainActor
  func isScanningFlagTogglesCorrectly() async throws {
    let mockDB = CacheBootstrapMockDB(isEmpty: true)
    let mockAppScanner = CacheBootstrapMockAppScanner(apps: [
      AppItem(name: "App", path: "/Applications/App.app")
    ])
    let mockDirScanner = CacheBootstrapMockDirScanner()
    let settings = makeSettingsManager(updateOnStartup: true)

    let bootstrap = CacheBootstrap(
      settingsManager: settings,
      cacheDatabase: mockDB,
      appScanner: mockAppScanner,
      directoryScanner: mockDirScanner
    )

    #expect(bootstrap.isScanning == false)

    await bootstrap.performInitialScan()

    // スキャン完了後はisScanningがfalseになる
    #expect(bootstrap.isScanning == false)
  }

  @Test("lastScanDate is set after scan")
  @MainActor
  func lastScanDateIsSetAfterScan() async throws {
    let mockDB = CacheBootstrapMockDB(isEmpty: true)
    let mockAppScanner = CacheBootstrapMockAppScanner(apps: [
      AppItem(name: "App", path: "/Applications/App.app")
    ])
    let mockDirScanner = CacheBootstrapMockDirScanner()
    let settings = makeSettingsManager(updateOnStartup: true)

    let bootstrap = CacheBootstrap(
      settingsManager: settings,
      cacheDatabase: mockDB,
      appScanner: mockAppScanner,
      directoryScanner: mockDirScanner
    )

    #expect(bootstrap.lastScanDate == nil)

    await bootstrap.performInitialScan()

    #expect(bootstrap.lastScanDate != nil)
  }

  // saveApps が失敗した経路でも defer 内で lastScanDate を更新してしまうと、
  // メニュー表示などで「直前に成功した」かのように振る舞ってしまう。
  // 失敗時には lastScanDate が更新されないことを保証する回帰テスト。
  @Test("saveApps が失敗した場合は lastScanDate が更新されない")
  @MainActor
  func lastScanDateRemainsUnchangedOnSaveAppsFailure() async throws {
    let mockDB = CacheBootstrapMockDB(isEmpty: true)
    mockDB.saveAppsError = CacheBootstrapTestError()
    let mockAppScanner = CacheBootstrapMockAppScanner(apps: [
      AppItem(name: "App", path: "/Applications/App.app")
    ])
    let mockDirScanner = CacheBootstrapMockDirScanner()
    let settings = makeSettingsManager(updateOnStartup: true)

    let bootstrap = CacheBootstrap(
      settingsManager: settings,
      cacheDatabase: mockDB,
      appScanner: mockAppScanner,
      directoryScanner: mockDirScanner
    )

    #expect(bootstrap.lastScanDate == nil)
    let result = await bootstrap.performInitialScan()
    #expect(result == false)
    #expect(bootstrap.lastScanDate == nil)
  }

  @Test("saveDirectories が失敗した場合も lastScanDate が更新されない")
  @MainActor
  func lastScanDateRemainsUnchangedOnSaveDirectoriesFailure() async throws {
    let mockDB = CacheBootstrapMockDB(isEmpty: true)
    mockDB.saveDirectoriesError = CacheBootstrapTestError()
    let mockAppScanner = CacheBootstrapMockAppScanner(apps: [
      AppItem(name: "App", path: "/Applications/App.app")
    ])
    let mockDirScanner = CacheBootstrapMockDirScanner()
    let settings = makeSettingsManager(updateOnStartup: true)

    let bootstrap = CacheBootstrap(
      settingsManager: settings,
      cacheDatabase: mockDB,
      appScanner: mockAppScanner,
      directoryScanner: mockDirScanner
    )

    #expect(bootstrap.lastScanDate == nil)
    let result = await bootstrap.performInitialScan()
    #expect(result == false)
    #expect(bootstrap.lastScanDate == nil)
  }

  // MARK: - 自動更新 テスト

  @Test("startAutoUpdate creates task when autoUpdateEnabled")
  @MainActor
  func startAutoUpdateCreatesTask() async throws {
    let mockDB = CacheBootstrapMockDB(isEmpty: false)
    let mockAppScanner = CacheBootstrapMockAppScanner()
    let mockDirScanner = CacheBootstrapMockDirScanner()
    let settings = makeSettingsManager(
      autoUpdateEnabled: true,
      autoUpdateIntervalHours: 1
    )

    let bootstrap = CacheBootstrap(
      settingsManager: settings,
      cacheDatabase: mockDB,
      appScanner: mockAppScanner,
      directoryScanner: mockDirScanner
    )

    bootstrap.startAutoUpdate()

    #expect(bootstrap.autoUpdateTask != nil)

    bootstrap.stopAutoUpdate()
  }

  @Test("startAutoUpdate does not create task when autoUpdateEnabled is false")
  @MainActor
  func startAutoUpdateDoesNotCreateTaskWhenDisabled() async throws {
    let mockDB = CacheBootstrapMockDB(isEmpty: false)
    let mockAppScanner = CacheBootstrapMockAppScanner()
    let mockDirScanner = CacheBootstrapMockDirScanner()
    let settings = makeSettingsManager(
      autoUpdateEnabled: false,
      autoUpdateIntervalHours: 1
    )

    let bootstrap = CacheBootstrap(
      settingsManager: settings,
      cacheDatabase: mockDB,
      appScanner: mockAppScanner,
      directoryScanner: mockDirScanner
    )

    bootstrap.startAutoUpdate()

    #expect(bootstrap.autoUpdateTask == nil)
  }

  @Test("stopAutoUpdate cancels task")
  @MainActor
  func stopAutoUpdateCancelsTask() async throws {
    let mockDB = CacheBootstrapMockDB(isEmpty: false)
    let mockAppScanner = CacheBootstrapMockAppScanner()
    let mockDirScanner = CacheBootstrapMockDirScanner()
    let settings = makeSettingsManager(
      autoUpdateEnabled: true,
      autoUpdateIntervalHours: 1
    )

    let bootstrap = CacheBootstrap(
      settingsManager: settings,
      cacheDatabase: mockDB,
      appScanner: mockAppScanner,
      directoryScanner: mockDirScanner
    )

    bootstrap.startAutoUpdate()
    #expect(bootstrap.autoUpdateTask != nil)

    bootstrap.stopAutoUpdate()
    #expect(bootstrap.autoUpdateTask == nil)
  }

  // MARK: - インターバルクランプテスト

  @Test("autoUpdateIntervalNanoseconds は 0 時間を 1 時間にクランプする")
  func intervalClampZeroToOne() {
    let ns = CacheBootstrap.autoUpdateIntervalNanoseconds(hours: 0)
    #expect(ns == 1 * 3600 * 1_000_000_000)
  }

  @Test("autoUpdateIntervalNanoseconds は負の値を 1 時間にクランプする")
  func intervalClampNegativeToOne() {
    let ns = CacheBootstrap.autoUpdateIntervalNanoseconds(hours: -100)
    #expect(ns == 1 * 3600 * 1_000_000_000)
  }

  @Test("autoUpdateIntervalNanoseconds は正常値をそのまま変換する")
  func intervalNormalValue() {
    let ns = CacheBootstrap.autoUpdateIntervalNanoseconds(hours: 6)
    #expect(ns == 6 * 3600 * 1_000_000_000)
  }

  @Test("autoUpdateIntervalNanoseconds は 8760 を超える値を 8760 にクランプする")
  func intervalClampLargeValue() {
    let ns = CacheBootstrap.autoUpdateIntervalNanoseconds(hours: 100_000)
    #expect(ns == 8760 * 3600 * 1_000_000_000)
  }

  @Test("autoUpdateIntervalNanoseconds は境界値 1 を正しく変換する")
  func intervalBoundaryOne() {
    let ns = CacheBootstrap.autoUpdateIntervalNanoseconds(hours: 1)
    #expect(ns == 3_600_000_000_000)
  }

  @Test("autoUpdateIntervalNanoseconds は境界値 8760 を正しく変換する")
  func intervalBoundaryMax() {
    let ns = CacheBootstrap.autoUpdateIntervalNanoseconds(hours: 8760)
    #expect(ns == 8760 * 3600 * 1_000_000_000)
  }

  @Test("autoUpdateIntervalNanoseconds は Int.max でもオーバーフローしない")
  func intervalIntMaxNoOverflow() {
    let ns = CacheBootstrap.autoUpdateIntervalNanoseconds(hours: Int.max)
    // 8760 にクランプされるためオーバーフローしない
    #expect(ns == 8760 * 3600 * 1_000_000_000)
  }

  @Test("startAutoUpdate replaces existing task")
  @MainActor
  func startAutoUpdateReplacesExistingTask() async throws {
    let mockDB = CacheBootstrapMockDB(isEmpty: false)
    let mockAppScanner = CacheBootstrapMockAppScanner()
    let mockDirScanner = CacheBootstrapMockDirScanner()
    let settings = makeSettingsManager(
      autoUpdateEnabled: true,
      autoUpdateIntervalHours: 1
    )

    let bootstrap = CacheBootstrap(
      settingsManager: settings,
      cacheDatabase: mockDB,
      appScanner: mockAppScanner,
      directoryScanner: mockDirScanner
    )

    bootstrap.startAutoUpdate()
    let firstTask = bootstrap.autoUpdateTask

    bootstrap.startAutoUpdate()
    let secondTask = bootstrap.autoUpdateTask

    #expect(firstTask != nil)
    #expect(secondTask != nil)

    bootstrap.stopAutoUpdate()
  }

  // MARK: - 登録ディレクトリ由来アプリのマージ

  @Test("登録ディレクトリ由来のアプリにも除外フィルタが適用される")
  @MainActor
  func directoryAppsRespectExcludedApps() async throws {
    let mockDB = CacheBootstrapMockDB(isEmpty: true)
    let mockAppScanner = CacheBootstrapMockAppScanner()
    let mockDirScanner = CacheBootstrapMockDirScanner(
      result: ScanResult(
        directories: [],
        apps: [
          AppItem(name: "Excluded", path: "/Users/dev/tools/Excluded.app"),
          AppItem(name: "Kept", path: "/Users/dev/tools/Kept.app"),
        ]
      ))
    let settings = makeSettingsManager()
    settings.settings.excludedApps = ["Excluded"]

    let bootstrap = CacheBootstrap(
      settingsManager: settings,
      cacheDatabase: mockDB,
      appScanner: mockAppScanner,
      directoryScanner: mockDirScanner
    )

    await bootstrap.rebuildCache()

    #expect(mockDB.savedApps.map(\.path) == ["/Users/dev/tools/Kept.app"])
  }

  @Test("アプリスキャンと同一パスの登録ディレクトリ由来アプリは情報の揃った側を残す")
  @MainActor
  func scannedAppWinsOverDirectoryAppWithSamePath() async throws {
    let mockDB = CacheBootstrapMockDB(isEmpty: true)
    // アプリスキャン側はアイコンとローカライズ名を持つ
    let mockAppScanner = CacheBootstrapMockAppScanner(apps: [
      AppItem(
        name: "メモ", path: "/Users/dev/Applications/Notes.app",
        iconPath: "/cache/notes.png", originalName: "Notes")
    ])
    // 登録ディレクトリ側は .app のファイル名しか持たない
    let mockDirScanner = CacheBootstrapMockDirScanner(
      result: ScanResult(
        directories: [],
        apps: [AppItem(name: "Notes", path: "/Users/dev/Applications/Notes.app")]
      ))
    let settings = makeSettingsManager()

    let bootstrap = CacheBootstrap(
      settingsManager: settings,
      cacheDatabase: mockDB,
      appScanner: mockAppScanner,
      directoryScanner: mockDirScanner
    )

    await bootstrap.rebuildCache()

    #expect(mockDB.savedApps.count == 1)
    #expect(mockDB.savedApps.first?.name == "メモ")
    #expect(mockDB.savedApps.first?.iconPath == "/cache/notes.png")
    #expect(mockDB.savedApps.first?.originalName == "Notes")
  }

  @Test("登録ディレクトリ内で同一パスが重複しても 1 件だけ保存される")
  @MainActor
  func duplicateDirectoryAppsAreDeduplicated() async throws {
    let mockDB = CacheBootstrapMockDB(isEmpty: true)
    let mockAppScanner = CacheBootstrapMockAppScanner()
    let mockDirScanner = CacheBootstrapMockDirScanner(
      result: ScanResult(
        directories: [],
        apps: [
          AppItem(name: "Tool", path: "/Users/dev/tools/Tool.app"),
          AppItem(name: "Tool", path: "/Users/dev/tools/Tool.app"),
        ]
      ))
    let settings = makeSettingsManager()

    let bootstrap = CacheBootstrap(
      settingsManager: settings,
      cacheDatabase: mockDB,
      appScanner: mockAppScanner,
      directoryScanner: mockDirScanner
    )

    await bootstrap.rebuildCache()

    #expect(mockDB.savedApps.count == 1)
  }

  @Test("除外設定が空なら登録ディレクトリ由来のアプリはすべて保存される")
  @MainActor
  func directoryAppsKeptWhenNoExclusions() async throws {
    let mockDB = CacheBootstrapMockDB(isEmpty: true)
    let mockAppScanner = CacheBootstrapMockAppScanner(apps: [
      AppItem(name: "Safari", path: "/Applications/Safari.app")
    ])
    let mockDirScanner = CacheBootstrapMockDirScanner(
      result: ScanResult(
        directories: [],
        apps: [AppItem(name: "Tool", path: "/Users/dev/tools/Tool.app")]
      ))
    let settings = makeSettingsManager()

    let bootstrap = CacheBootstrap(
      settingsManager: settings,
      cacheDatabase: mockDB,
      appScanner: mockAppScanner,
      directoryScanner: mockDirScanner
    )

    await bootstrap.rebuildCache()

    #expect(
      Set(mockDB.savedApps.map(\.path))
        == ["/Applications/Safari.app", "/Users/dev/tools/Tool.app"])
  }
}

// MARK: - モック: 1 回目のスキャンを止めておける AppScanner

/// スキャン中に届く再構築要求を再現するため、1 回目の scanApplications を release() まで止める。
private final class GatedAppScanner: AppScannerProtocol, @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, Never>?
  private var calls = 0
  let apps: [AppItem]

  init(apps: [AppItem]) {
    self.apps = apps
  }

  var callCount: Int { lock.withLock { calls } }
  var isWaiting: Bool { lock.withLock { continuation != nil } }

  func scanApplications(excludedApps: [String]) async throws -> [AppItem] {
    let call = lock.withLock { () -> Int in
      calls += 1
      return calls
    }
    if call == 1 {
      await withCheckedContinuation { continuation in
        lock.withLock { self.continuation = continuation }
      }
    }
    return apps
  }

  func release() {
    let pending = lock.withLock { () -> CheckedContinuation<Void, Never>? in
      defer { continuation = nil }
      return continuation
    }
    pending?.resume()
  }
}

@MainActor
private func waitForCondition(
  timeout: Duration = .seconds(5), _ condition: () -> Bool
) async -> Bool {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: timeout)
  while clock.now < deadline {
    if condition() { return true }
    await Task.yield()
  }
  return condition()
}

@Suite("CacheBootstrap スキャン中の要求と設定の読込失敗")
@MainActor
struct CacheBootstrapRescanTests {

  private func makeSettingsManager() -> SettingsManager {
    SettingsManager(
      configDirectory: FileManager.default.temporaryDirectory
        .appendingPathComponent("ignitero-rescan-\(UUID().uuidString)"))
  }

  @Test("スキャン中の再構築要求は捨てずに、終了後に最新の設定でもう一度スキャンする")
  func rebuildDuringScanRescansWithLatestSettings() async throws {
    let mockDB = CacheBootstrapMockDB(isEmpty: false)
    let scanner = GatedAppScanner(apps: [
      AppItem(name: "Keep", path: "/Applications/Keep.app"),
      AppItem(name: "Drop", path: "/Applications/Drop.app"),
    ])
    let settings = makeSettingsManager()
    let bootstrap = CacheBootstrap(
      settingsManager: settings,
      cacheDatabase: mockDB,
      appScanner: scanner,
      directoryScanner: CacheBootstrapMockDirScanner()
    )

    let first = Task { await bootstrap.rebuildCache() }
    #expect(await waitForCondition { scanner.isWaiting })
    #expect(bootstrap.isScanning)

    // 1 回目のスキャン（開始時点の設定のコピーで走っている）の最中に除外設定を変える
    settings.settings.excludedApps = ["/Applications/Drop.app"]
    await bootstrap.rebuildCache()  // 予約だけして戻る

    scanner.release()
    await first.value

    #expect(scanner.callCount == 2)
    // 最後に保存されたのは変更後の設定によるスキャン結果
    #expect(mockDB.savedApps.map(\.path) == ["/Applications/Keep.app"])
    #expect(bootstrap.isScanning == false)
  }

  @Test("スキャン中に要求が何度届いても再スキャンは 1 回にまとめる")
  func multipleRequestsDuringScanCoalesce() async throws {
    let mockDB = CacheBootstrapMockDB(isEmpty: false)
    let scanner = GatedAppScanner(apps: [])
    let bootstrap = CacheBootstrap(
      settingsManager: makeSettingsManager(),
      cacheDatabase: mockDB,
      appScanner: scanner,
      directoryScanner: CacheBootstrapMockDirScanner()
    )

    let first = Task { await bootstrap.rebuildCache() }
    #expect(await waitForCondition { scanner.isWaiting })
    await bootstrap.rebuildCache()
    await bootstrap.rebuildCache()
    await bootstrap.rebuildCache()
    scanner.release()
    await first.value

    #expect(scanner.callCount == 2)
  }

  @Test("設定ファイルを読めない間はスキャンせず、既存キャッシュを保持する")
  func scanIsSkippedWhileSettingsFailedToLoad() async throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("ignitero-rescan-unreadable-\(UUID().uuidString)")
    // settings.json の代わりに同名ディレクトリを置き、I/O エラーで読めない状態にする
    try FileManager.default.createDirectory(
      at: dir.appendingPathComponent("settings.json"), withIntermediateDirectories: true)
    let settings = SettingsManager(configDirectory: dir)
    #expect(throws: (any Error).self) { try settings.load() }
    #expect(settings.loadFailed)

    let mockDB = CacheBootstrapMockDB(isEmpty: true)
    let bootstrap = CacheBootstrap(
      settingsManager: settings,
      cacheDatabase: mockDB,
      appScanner: CacheBootstrapMockAppScanner(apps: [
        AppItem(name: "Safari", path: "/Applications/Safari.app")
      ]),
      directoryScanner: CacheBootstrapMockDirScanner()
    )

    // キャッシュが空でも（通常なら必ずスキャンする）既定設定では置き換えない
    let didScan = await bootstrap.performInitialScan()
    await bootstrap.rebuildCache()

    #expect(didScan == false)
    #expect(mockDB.saveAppsCalled == false)
    #expect(mockDB.saveDirectoriesCalled == false)
    #expect(bootstrap.lastScanDate == nil)
  }
}
