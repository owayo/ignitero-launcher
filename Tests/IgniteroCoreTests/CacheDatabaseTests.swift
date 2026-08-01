import Foundation
import GRDB
import Testing

@testable import IgniteroCore

@Test func cacheDatabaseCreatesTablesOnInit() async throws {
  let db = try CacheDatabase.inMemory()
  // テーブルが作成されていることを確認
  let tableNames = try await db.tableNames()
  #expect(tableNames.contains("apps"))
  #expect(tableNames.contains("directories"))
  #expect(tableNames.contains("metadata"))
}

@Test func cacheDatabaseSaveAndLoadApps() async throws {
  let db = try CacheDatabase.inMemory()
  let apps = [
    AppItem(
      name: "Safari", path: "/Applications/Safari.app", iconPath: "/icons/safari.png",
      originalName: "Safari"),
    AppItem(name: "Finder", path: "/System/Applications/Finder.app"),
  ]

  try db.saveApps(apps)
  let loaded = try await db.loadApps()

  #expect(loaded.count == 2)
  #expect(loaded.contains { $0.name == "Safari" && $0.path == "/Applications/Safari.app" })
  #expect(loaded.contains { $0.name == "Finder" && $0.path == "/System/Applications/Finder.app" })
}

@Test func cacheDatabaseSaveAppsOverwritesExisting() async throws {
  let db = try CacheDatabase.inMemory()
  let initial = [AppItem(name: "Safari", path: "/Applications/Safari.app")]
  try db.saveApps(initial)

  let updated = [AppItem(name: "Safari Updated", path: "/Applications/Safari.app")]
  try db.saveApps(updated)

  let loaded = try await db.loadApps()
  #expect(loaded.count == 1)
  #expect(loaded[0].name == "Safari Updated")
}

@Test func cacheDatabaseAppWithOptionalFields() async throws {
  let db = try CacheDatabase.inMemory()
  let app = AppItem(name: "Test", path: "/test.app", iconPath: nil, originalName: nil)
  try db.saveApps([app])
  let loaded = try await db.loadApps()
  #expect(loaded.count == 1)
  #expect(loaded[0].iconPath == nil)
  #expect(loaded[0].originalName == nil)
}

@Test func cacheDatabaseSaveAndLoadDirectories() async throws {
  let db = try CacheDatabase.inMemory()
  let dirs = [
    DirectoryItem(name: "project-a", path: "/Users/dev/project-a", editor: "vscode"),
    DirectoryItem(name: "project-b", path: "/Users/dev/project-b"),
  ]

  try db.saveDirectories(dirs)
  let loaded = try await db.loadDirectories()

  #expect(loaded.count == 2)
  #expect(loaded.contains { $0.name == "project-a" && $0.editor == "vscode" })
  #expect(loaded.contains { $0.name == "project-b" && $0.editor == nil })
}

@Test func cacheDatabaseSaveDirectoriesOverwritesExisting() async throws {
  let db = try CacheDatabase.inMemory()
  let initial = [DirectoryItem(name: "project", path: "/project", editor: "vscode")]
  try db.saveDirectories(initial)

  let updated = [DirectoryItem(name: "project", path: "/project", editor: "cursor")]
  try db.saveDirectories(updated)

  let loaded = try await db.loadDirectories()
  #expect(loaded.count == 1)
  #expect(loaded[0].editor == "cursor")
}

@Test func cacheDatabaseIsEmptyWhenNew() throws {
  let db = try CacheDatabase.inMemory()
  let empty = try db.isEmpty()
  #expect(empty == true)
}

@Test func cacheDatabaseIsNotEmptyAfterSavingApps() throws {
  let db = try CacheDatabase.inMemory()
  try db.saveApps([AppItem(name: "Safari", path: "/Applications/Safari.app")])
  let empty = try db.isEmpty()
  #expect(empty == false)
}

@Test func cacheDatabaseIsNotEmptyAfterSavingDirectories() throws {
  let db = try CacheDatabase.inMemory()
  try db.saveDirectories([DirectoryItem(name: "proj", path: "/proj")])
  let empty = try db.isEmpty()
  #expect(empty == false)
}

@Test func cacheDatabaseClearCache() throws {
  let db = try CacheDatabase.inMemory()
  try db.saveApps([AppItem(name: "Safari", path: "/Applications/Safari.app")])
  try db.saveDirectories([DirectoryItem(name: "proj", path: "/proj")])

  try db.clearCache()

  let empty = try db.isEmpty()
  #expect(empty == true)
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

// MARK: - saveAppsAndDirectories の結合保存

@Test func cacheDatabaseSaveAppsAndDirectoriesReplacesBoth() async throws {
  let db = try CacheDatabase.inMemory()

  // 初期データ
  try db.saveAppsAndDirectories(
    apps: [
      AppItem(name: "OldApp", path: "/Applications/OldApp.app")
    ],
    directories: [
      DirectoryItem(name: "old-dir", path: "/Users/dev/old", editor: "vscode")
    ]
  )

  // まったく異なる世代のデータで置換
  try db.saveAppsAndDirectories(
    apps: [
      AppItem(name: "NewApp", path: "/Applications/NewApp.app", iconPath: "/i.png")
    ],
    directories: [
      DirectoryItem(name: "new-dir", path: "/Users/dev/new", editor: "cursor")
    ]
  )

  let apps = try await db.loadApps()
  let dirs = try await db.loadDirectories()

  #expect(apps.count == 1)
  #expect(apps.first?.name == "NewApp")
  #expect(dirs.count == 1)
  #expect(dirs.first?.editor == "cursor")
}

@Test func cacheDatabaseSaveAppsAndDirectoriesHandlesEmptyArrays() throws {
  let db = try CacheDatabase.inMemory()
  try db.saveAppsAndDirectories(apps: [], directories: [])
  let empty = try db.isEmpty()
  #expect(empty == true)
}
