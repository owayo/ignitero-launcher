import Foundation
import GRDB

// MARK: - CacheDatabaseProtocol

public protocol CacheDatabaseProtocol: Sendable {
  func isEmpty() throws -> Bool
  func saveApps(_ apps: [AppItem]) throws
  func saveDirectories(_ dirs: [DirectoryItem]) throws
  func clearCache() throws
}

// MARK: - CacheDatabase

public actor CacheDatabase: CacheDatabaseProtocol {
  private let dbQueue: DatabaseQueue

  public init(path: String) throws {
    var config = Configuration()
    config.prepareDatabase { db in
      try db.execute(sql: "PRAGMA journal_mode = WAL")
    }
    let queue = try DatabaseQueue(path: path, configuration: config)
    try Self.runMigrations(on: queue)
    dbQueue = queue
  }

  public init(inMemory: Bool) throws {
    var config = Configuration()
    config.prepareDatabase { db in
      try db.execute(sql: "PRAGMA journal_mode = WAL")
    }
    let queue = try DatabaseQueue(configuration: config)
    try Self.runMigrations(on: queue)
    dbQueue = queue
  }

  private static func runMigrations(on queue: DatabaseQueue) throws {
    var migrator = DatabaseMigrator()
    migrator.registerMigration("v1") { db in
      try db.create(table: "apps", ifNotExists: true) { t in
        t.column("name", .text).notNull()
        t.primaryKey("path", .text)
        t.column("icon_path", .text)
        t.column("original_name", .text)
        t.column("last_updated", .text).notNull()
      }

      try db.create(table: "directories", ifNotExists: true) { t in
        t.column("name", .text).notNull()
        t.primaryKey("path", .text)
        t.column("editor", .text)
        t.column("last_updated", .text).notNull()
      }

      try db.create(table: "metadata", ifNotExists: true) { t in
        t.primaryKey("key", .text)
        t.column("value", .text).notNull()
      }
    }
    try migrator.migrate(queue)
  }

  // MARK: - Apps

  nonisolated public func saveApps(_ apps: [AppItem]) throws {
    try dbQueue.write { db in
      try db.execute(sql: "DELETE FROM apps")
      let now = ISO8601DateFormatter().string(from: Date())
      for app in apps {
        try db.execute(
          sql: """
            INSERT OR REPLACE INTO apps (name, path, icon_path, original_name, last_updated)
            VALUES (?, ?, ?, ?, ?)
            """,
          arguments: [app.name, app.path, app.iconPath, app.originalName, now]
        )
      }
      try db.execute(
        sql: "INSERT OR REPLACE INTO metadata (key, value) VALUES ('last_updated', ?)",
        arguments: [now]
      )
    }
  }

  public func loadApps() throws -> [AppItem] {
    try dbQueue.read { db in
      try AppItem.fetchAll(db)
    }
  }

  // MARK: - Directories

  nonisolated public func saveDirectories(_ dirs: [DirectoryItem]) throws {
    try dbQueue.write { db in
      try db.execute(sql: "DELETE FROM directories")
      let now = ISO8601DateFormatter().string(from: Date())
      for dir in dirs {
        try db.execute(
          sql: """
            INSERT OR REPLACE INTO directories (name, path, editor, last_updated)
            VALUES (?, ?, ?, ?)
            """,
          arguments: [dir.name, dir.path, dir.editor, now]
        )
      }
      try db.execute(
        sql: "INSERT OR REPLACE INTO metadata (key, value) VALUES ('last_updated', ?)",
        arguments: [now]
      )
    }
  }

  public func loadDirectories() throws -> [DirectoryItem] {
    try dbQueue.read { db in
      try DirectoryItem.fetchAll(db)
    }
  }

  // MARK: - Cache Status

  nonisolated public func isEmpty() throws -> Bool {
    try dbQueue.read { db in
      let appCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM apps") ?? 0
      let dirCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM directories") ?? 0
      return appCount == 0 && dirCount == 0
    }
  }

  public func needsUpdate(intervalHours: Int) throws -> Bool {
    try dbQueue.read { db in
      guard
        let value = try String.fetchOne(
          db, sql: "SELECT value FROM metadata WHERE key = 'last_updated'")
      else {
        return true
      }
      guard let lastUpdated = ISO8601DateFormatter().date(from: value) else {
        return true
      }
      let elapsed = Date().timeIntervalSince(lastUpdated)
      return elapsed >= Double(intervalHours) * 3600
    }
  }

  public func setLastUpdated(_ date: Date) throws {
    try dbQueue.write { db in
      let value = ISO8601DateFormatter().string(from: date)
      try db.execute(
        sql: "INSERT OR REPLACE INTO metadata (key, value) VALUES ('last_updated', ?)",
        arguments: [value]
      )
    }
  }

  nonisolated public func clearCache() throws {
    try dbQueue.write { db in
      try db.execute(sql: "DELETE FROM apps")
      try db.execute(sql: "DELETE FROM directories")
      try db.execute(sql: "DELETE FROM metadata")
    }
  }

  // MARK: - Diagnostics

  public func journalMode() throws -> String {
    try dbQueue.read { db in
      let mode = try String.fetchOne(db, sql: "PRAGMA journal_mode")
      return mode ?? "unknown"
    }
  }

  public func tableNames() throws -> [String] {
    try dbQueue.read { db in
      try String.fetchAll(
        db, sql: "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")
    }
  }
}
