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

  try await db.saveApps(apps)
  let loaded = try await db.loadApps()

  #expect(loaded.count == 2)
  #expect(loaded.contains { $0.name == "Safari" && $0.path == "/Applications/Safari.app" })
  #expect(loaded.contains { $0.name == "Finder" && $0.path == "/System/Applications/Finder.app" })
}

@Test func cacheDatabaseSaveAppsOverwritesExisting() async throws {
  let db = try CacheDatabase.inMemory()
  let initial = [AppItem(name: "Safari", path: "/Applications/Safari.app")]
  try await db.saveApps(initial)

  let updated = [AppItem(name: "Safari Updated", path: "/Applications/Safari.app")]
  try await db.saveApps(updated)

  let loaded = try await db.loadApps()
  #expect(loaded.count == 1)
  #expect(loaded[0].name == "Safari Updated")
}

@Test func cacheDatabaseAppWithOptionalFields() async throws {
  let db = try CacheDatabase.inMemory()
  let app = AppItem(name: "Test", path: "/test.app", iconPath: nil, originalName: nil)
  try await db.saveApps([app])
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

  try await db.saveDirectories(dirs)
  let loaded = try await db.loadDirectories()

  #expect(loaded.count == 2)
  #expect(loaded.contains { $0.name == "project-a" && $0.editor == "vscode" })
  #expect(loaded.contains { $0.name == "project-b" && $0.editor == nil })
}

@Test func cacheDatabaseSaveDirectoriesOverwritesExisting() async throws {
  let db = try CacheDatabase.inMemory()
  let initial = [DirectoryItem(name: "project", path: "/project", editor: "vscode")]
  try await db.saveDirectories(initial)

  let updated = [DirectoryItem(name: "project", path: "/project", editor: "cursor")]
  try await db.saveDirectories(updated)

  let loaded = try await db.loadDirectories()
  #expect(loaded.count == 1)
  #expect(loaded[0].editor == "cursor")
}

@Test func cacheDatabaseIsEmptyWhenNew() async throws {
  let db = try CacheDatabase.inMemory()
  let empty = try await db.isEmpty()
  #expect(empty == true)
}

@Test func cacheDatabaseIsNotEmptyAfterSavingApps() async throws {
  let db = try CacheDatabase.inMemory()
  try await db.saveApps([AppItem(name: "Safari", path: "/Applications/Safari.app")])
  let empty = try await db.isEmpty()
  #expect(empty == false)
}

@Test func cacheDatabaseIsNotEmptyAfterSavingDirectories() async throws {
  let db = try CacheDatabase.inMemory()
  try await db.saveDirectories([DirectoryItem(name: "proj", path: "/proj")])
  let empty = try await db.isEmpty()
  #expect(empty == false)
}

@Test func cacheDatabaseClearCache() async throws {
  let db = try CacheDatabase.inMemory()
  try await db.saveApps([AppItem(name: "Safari", path: "/Applications/Safari.app")])
  try await db.saveDirectories([DirectoryItem(name: "proj", path: "/proj")])

  try await db.clearCache()

  let empty = try await db.isEmpty()
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
  try await db.saveAppsAndDirectories(
    apps: [
      AppItem(name: "OldApp", path: "/Applications/OldApp.app")
    ],
    directories: [
      DirectoryItem(name: "old-dir", path: "/Users/dev/old", editor: "vscode")
    ]
  )

  // まったく異なる世代のデータで置換
  try await db.saveAppsAndDirectories(
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

@Test func cacheDatabaseSaveAppsAndDirectoriesHandlesEmptyArrays() async throws {
  let db = try CacheDatabase.inMemory()
  try await db.saveAppsAndDirectories(apps: [], directories: [])
  let empty = try await db.isEmpty()
  #expect(empty == true)
}

// MARK: - Finder 指定（opens_in_finder）

@Test func cacheDatabasePersistsOpensInFinderThroughBothSavePaths() async throws {
  let db = try CacheDatabase.inMemory()
  let directories = [
    DirectoryItem(name: "finder-dir", path: "/Users/dev/finder", opensInFinder: true),
    DirectoryItem(name: "default-editor-dir", path: "/Users/dev/default"),
    DirectoryItem(name: "zed-dir", path: "/Users/dev/zed", editor: "zed"),
  ]

  // スキャン経路（結合保存）
  try await db.saveAppsAndDirectories(apps: [], directories: directories)
  var loaded = try await db.loadDirectories()
  #expect(loaded.first { $0.path == "/Users/dev/finder" }?.opensInFinder == true)
  #expect(loaded.first { $0.path == "/Users/dev/default" }?.opensInFinder == false)
  #expect(loaded.first { $0.path == "/Users/dev/zed" }?.opensInFinder == false)

  // 単体置換の経路
  try await db.saveDirectories(directories.reversed())
  loaded = try await db.loadDirectories()
  #expect(Set(loaded.map(\.path)) == Set(directories.map(\.path)))
  #expect(loaded.first { $0.path == "/Users/dev/finder" }?.opensInFinder == true)
  #expect(loaded.first { $0.path == "/Users/dev/finder" }?.editor == nil)
}

/// v1 のキャッシュは Finder 指定を持たないため、v2 のマイグレーションで列を足したうえで
/// 空にし、次回起動時の「キャッシュが空なら必ずスキャン」で作り直させる。
@Test func cacheDatabaseMigratesV1CacheByAddingColumnAndClearingRows() async throws {
  let dbPath = FileManager.default.temporaryDirectory
    .appendingPathComponent("test_cache_v1_\(UUID().uuidString).db").path
  defer {
    for suffix in ["", "-wal", "-shm"] {
      try? FileManager.default.removeItem(atPath: dbPath + suffix)
    }
  }

  // v1 のスキーマとデータを持つ DB を用意する（マイグレーション記録も v1 まで）
  do {
    let queue = try DatabaseQueue(path: dbPath)
    var migrator = DatabaseMigrator()
    migrator.registerMigration("v1") { db in
      try db.create(table: "apps") { t in
        t.column("name", .text).notNull()
        t.primaryKey("path", .text)
        t.column("icon_path", .text)
        t.column("original_name", .text)
        t.column("last_updated", .text).notNull()
      }
      try db.create(table: "directories") { t in
        t.column("name", .text).notNull()
        t.primaryKey("path", .text)
        t.column("editor", .text)
        t.column("last_updated", .text).notNull()
      }
      try db.create(table: "metadata") { t in
        t.primaryKey("key", .text)
        t.column("value", .text).notNull()
      }
    }
    try migrator.migrate(queue)
    try await queue.write { db in
      try db.execute(
        sql: "INSERT INTO apps (name, path, last_updated) VALUES ('A', '/Applications/A.app', 'x')")
      try db.execute(
        sql: "INSERT INTO directories (name, path, editor, last_updated) VALUES ('d', '/d', NULL, 'x')")
    }
    try queue.close()
  }

  let db = try CacheDatabase(path: dbPath)
  #expect(try await db.isEmpty())

  // 新しい列で保存・読込できる
  try await db.saveAppsAndDirectories(
    apps: [], directories: [DirectoryItem(name: "d", path: "/d", opensInFinder: true)])
  let loaded = try await db.loadDirectories()
  #expect(loaded.count == 1)
  #expect(loaded.first?.opensInFinder == true)
}

@Test func cacheDatabaseMigrationDoesNotClearAgainOnReopen() async throws {
  let dbPath = FileManager.default.temporaryDirectory
    .appendingPathComponent("test_cache_reopen_\(UUID().uuidString).db").path
  defer {
    for suffix in ["", "-wal", "-shm"] {
      try? FileManager.default.removeItem(atPath: dbPath + suffix)
    }
  }

  do {
    let db = try CacheDatabase(path: dbPath)
    try await db.saveAppsAndDirectories(
      apps: [AppItem(name: "A", path: "/Applications/A.app")],
      directories: [DirectoryItem(name: "d", path: "/d", opensInFinder: true)])
  }

  // 2 回目以降の起動ではマイグレーションが走らず、キャッシュは保持される
  let reopened = try CacheDatabase(path: dbPath)
  #expect(try await reopened.isEmpty() == false)
  #expect(try await reopened.loadDirectories().first?.opensInFinder == true)
}
