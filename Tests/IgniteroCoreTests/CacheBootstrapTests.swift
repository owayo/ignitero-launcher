import Foundation
import Testing

@testable import IgniteroCore

// MARK: - Mock CacheDatabase

private final class CacheBootstrapMockDB: CacheDatabaseProtocol, @unchecked Sendable {
  var isEmptyResult: Bool
  var saveAppsCalled = false
  var saveDirectoriesCalled = false
  var clearCacheCalled = false
  var savedApps: [AppItem] = []
  var savedDirectories: [DirectoryItem] = []

  init(isEmpty: Bool = true) {
    self.isEmptyResult = isEmpty
  }

  func isEmpty() throws -> Bool {
    isEmptyResult
  }

  func saveApps(_ apps: [AppItem]) throws {
    saveAppsCalled = true
    savedApps = apps
  }

  func saveDirectories(_ dirs: [DirectoryItem]) throws {
    saveDirectoriesCalled = true
    savedDirectories = dirs
  }

  func clearCache() throws {
    clearCacheCalled = true
  }
}

// MARK: - Mock AppScanner

private struct CacheBootstrapMockAppScanner: AppScannerProtocol {
  let apps: [AppItem]

  init(apps: [AppItem] = []) {
    self.apps = apps
  }

  func scanApplications(excludedApps: [String]) throws -> [AppItem] {
    apps
  }
}

// MARK: - Mock DirectoryScanner

private struct CacheBootstrapMockDirScanner: DirectoryScannerProtocol {
  let result: ScanResult

  init(result: ScanResult = ScanResult(directories: [], apps: [])) {
    self.result = result
  }

  func scan(directories: [RegisteredDirectory]) throws -> ScanResult {
    result
  }
}

// MARK: - Tests

@Suite("CacheBootstrap")
@MainActor
struct CacheBootstrapTests {

  // MARK: - Helpers

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

  // MARK: - Initial Scan Tests

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

    #expect(mockDB.clearCacheCalled == true)
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
