import Foundation
import GRDB
import Testing

@testable import IgniteroCore

@Test func cacheDatabaseCreatesTablesOnInit() async throws {
  let db = try CacheDatabase(inMemory: true)
  // テーブルが作成されていることを確認
  let tableNames = try await db.tableNames()
  #expect(tableNames.contains("apps"))
  #expect(tableNames.contains("directories"))
  #expect(tableNames.contains("metadata"))
}

@Test func cacheDatabaseSaveAndLoadApps() async throws {
  let db = try CacheDatabase(inMemory: true)
  let apps = [
    AppItem(
      name: "Safari", path: "/Applications/Safari.app", iconPath: "/icons/safari.png",
      originalName: "Safari"),
    AppItem(name: "Finder", path: "/System/Applications/Finder.app"),
  ]

  try await db.saveApps(apps)
  let loaded = try await db.loadApps()

  #expect(loaded.count == 2)
  #expect(loaded.contains { $0.name == "Safari" && $0.path == "/Applications/Safari.app" })
  #expect(loaded.contains { $0.name == "Finder" && $0.path == "/System/Applications/Finder.app" })
}

@Test func cacheDatabaseSaveAppsOverwritesExisting() async throws {
  let db = try CacheDatabase(inMemory: true)
  let initial = [AppItem(name: "Safari", path: "/Applications/Safari.app")]
  try await db.saveApps(initial)

  let updated = [AppItem(name: "Safari Updated", path: "/Applications/Safari.app")]
  try await db.saveApps(updated)

  let loaded = try await db.loadApps()
  #expect(loaded.count == 1)
  #expect(loaded[0].name == "Safari Updated")
}

@Test func cacheDatabaseAppWithOptionalFields() async throws {
  let db = try CacheDatabase(inMemory: true)
  let app = AppItem(name: "Test", path: "/test.app", iconPath: nil, originalName: nil)
  try await db.saveApps([app])
  let loaded = try await db.loadApps()
  #expect(loaded.count == 1)
  #expect(loaded[0].iconPath == nil)
  #expect(loaded[0].originalName == nil)
}

@Test func cacheDatabaseSaveAndLoadDirectories() async throws {
  let db = try CacheDatabase(inMemory: true)
  let dirs = [
    DirectoryItem(name: "project-a", path: "/Users/dev/project-a", editor: "vscode"),
    DirectoryItem(name: "project-b", path: "/Users/dev/project-b"),
  ]

  try await db.saveDirectories(dirs)
  let loaded = try await db.loadDirectories()

  #expect(loaded.count == 2)
  #expect(loaded.contains { $0.name == "project-a" && $0.editor == "vscode" })
  #expect(loaded.contains { $0.name == "project-b" && $0.editor == nil })
}

@Test func cacheDatabaseSaveDirectoriesOverwritesExisting() async throws {
  let db = try CacheDatabase(inMemory: true)
  let initial = [DirectoryItem(name: "project", path: "/project", editor: "vscode")]
  try await db.saveDirectories(initial)

  let updated = [DirectoryItem(name: "project", path: "/project", editor: "cursor")]
  try await db.saveDirectories(updated)

  let loaded = try await db.loadDirectories()
  #expect(loaded.count == 1)
  #expect(loaded[0].editor == "cursor")
}

@Test func cacheDatabaseIsEmptyWhenNew() async throws {
  let db = try CacheDatabase(inMemory: true)
  let empty = try await db.isEmpty()
  #expect(empty == true)
}

@Test func cacheDatabaseIsNotEmptyAfterSavingApps() async throws {
  let db = try CacheDatabase(inMemory: true)
  try await db.saveApps([AppItem(name: "Safari", path: "/Applications/Safari.app")])
  let empty = try await db.isEmpty()
  #expect(empty == false)
}

@Test func cacheDatabaseIsNotEmptyAfterSavingDirectories() async throws {
  let db = try CacheDatabase(inMemory: true)
  try await db.saveDirectories([DirectoryItem(name: "proj", path: "/proj")])
  let empty = try await db.isEmpty()
  #expect(empty == false)
}

@Test func cacheDatabaseNeedsUpdateWhenNoLastUpdated() async throws {
  let db = try CacheDatabase(inMemory: true)
  let needs = try await db.needsUpdate(intervalHours: 1)
  #expect(needs == true)
}

@Test func cacheDatabaseNeedsUpdateWhenExpired() async throws {
  let db = try CacheDatabase(inMemory: true)
  // 2時間前のタイムスタンプを設定
  let twoHoursAgo = Date().addingTimeInterval(-2 * 3600)
  try await db.setLastUpdated(twoHoursAgo)
  let needs = try await db.needsUpdate(intervalHours: 1)
  #expect(needs == true)
}

@Test func cacheDatabaseDoesNotNeedUpdateWhenRecent() async throws {
  let db = try CacheDatabase(inMemory: true)
  // 現在のタイムスタンプを設定
  try await db.setLastUpdated(Date())
  let needs = try await db.needsUpdate(intervalHours: 1)
  #expect(needs == false)
}

@Test func cacheDatabaseClearCache() async throws {
  let db = try CacheDatabase(inMemory: true)
  try await db.saveApps([AppItem(name: "Safari", path: "/Applications/Safari.app")])
  try await db.saveDirectories([DirectoryItem(name: "proj", path: "/proj")])
  try await db.setLastUpdated(Date())

  try await db.clearCache()

  let empty = try await db.isEmpty()
  #expect(empty == true)
  let needs = try await db.needsUpdate(intervalHours: 1)
  #expect(needs == true)
}

@Test func cacheDatabaseWALModeEnabled() async throws {
  let tempDir = FileManager.default.temporaryDirectory
  let dbPath = tempDir.appendingPathComponent("test_wal_\(UUID().uuidString).db").path
  defer { try? FileManager.default.removeItem(atPath: dbPath) }

  let db = try CacheDatabase(path: dbPath)
  let journalMode = try await db.journalMode()
  #expect(journalMode == "wal")
}

@Test func cacheDatabaseFileBasedInit() throws {
  let tempDir = FileManager.default.temporaryDirectory
  let dbPath = tempDir.appendingPathComponent("test_cache_\(UUID().uuidString).db").path
  defer { try? FileManager.default.removeItem(atPath: dbPath) }

  let _ = try CacheDatabase(path: dbPath)
  #expect(FileManager.default.fileExists(atPath: dbPath))
}
