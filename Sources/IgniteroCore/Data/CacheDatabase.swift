import Foundation
import GRDB

// MARK: - CacheDatabaseProtocol関連

public protocol CacheDatabaseProtocol: Sendable {
  func isEmpty() throws -> Bool
  func saveApps(_ apps: [AppItem]) throws
  func loadApps() async throws -> [AppItem]
  func saveDirectories(_ dirs: [DirectoryItem]) throws
  func loadDirectories() async throws -> [DirectoryItem]
  // アプリとディレクトリの両方を 1 つのトランザクションで置換する。
  // 片方だけ成功して片方が失敗した場合に、apps と directories の世代がずれた
  // 不整合キャッシュが残らないようにするために使う。
  func saveAppsAndDirectories(apps: [AppItem], directories: [DirectoryItem]) throws
  func clearCache() throws
}

// MARK: - CacheDatabase関連

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

  /// インメモリ DB を生成する（テスト・キャッシュ無効時のフォールバック用）。
  ///
  /// 以前は `init(inMemory: Bool)` だったが、引数を一切参照しておらず
  /// `inMemory: false` を渡しても常にインメモリ DB が返る「嘘の API」だった。
  /// 永続化するかどうかはパスの有無で決まるため、ファクトリで意図を型に表す。
  public static func inMemory() throws -> CacheDatabase {
    try CacheDatabase(inMemoryMarker: ())
  }

  private init(inMemoryMarker: Void) throws {
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

  // MARK: - アプリ

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

  // MARK: - ディレクトリ

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

  // MARK: - 一括保存

  /// アプリとディレクトリを 1 つの SQLite トランザクション内で置換する。
  /// 個別の `saveApps` / `saveDirectories` を続けて呼ぶと、片方の `write` が
  /// 成功してもう片方が失敗した瞬間に「新しい apps + 古い directories」という
  /// 不整合キャッシュが残ってしまう。そのため、スキャン結果の置換ではこちらを使う。
  nonisolated public func saveAppsAndDirectories(
    apps: [AppItem],
    directories: [DirectoryItem]
  ) throws {
    try dbQueue.write { db in
      let now = ISO8601DateFormatter().string(from: Date())

      try db.execute(sql: "DELETE FROM apps")
      for app in apps {
        try db.execute(
          sql: """
            INSERT OR REPLACE INTO apps (name, path, icon_path, original_name, last_updated)
            VALUES (?, ?, ?, ?, ?)
            """,
          arguments: [app.name, app.path, app.iconPath, app.originalName, now]
        )
      }

      try db.execute(sql: "DELETE FROM directories")
      for dir in directories {
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

  // MARK: - キャッシュ状態

  nonisolated public func isEmpty() throws -> Bool {
    try dbQueue.read { db in
      let appCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM apps") ?? 0
      let dirCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM directories") ?? 0
      return appCount == 0 && dirCount == 0
    }
  }

  nonisolated public func clearCache() throws {
    try dbQueue.write { db in
      try db.execute(sql: "DELETE FROM apps")
      try db.execute(sql: "DELETE FROM directories")
      try db.execute(sql: "DELETE FROM metadata")
    }
  }

  // MARK: - 診断

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
