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

  // MARK: - Rebuild Cache Tests

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

    // Apps from both scanners are combined
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

  // MARK: - isScanning Flag Tests

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

    // After scan completes, isScanning should be false
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

  // MARK: - Auto Update Tests

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
}
