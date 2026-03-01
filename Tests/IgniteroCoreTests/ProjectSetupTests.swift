import Fuse
import GRDB
import KeyboardShortcuts
import Testing

@testable import IgniteroCore

@Test func projectVersion() {
  #expect(Ignitero.version == "27.0.0")
}

@Test func grdbDependencyAvailable() {
  // GRDB が正しくインポートされ DatabaseQueue 型が利用可能
  #expect(DatabaseQueue.self == DatabaseQueue.self)
}

@Test func fuseDependencyAvailable() {
  // Fuse がインポートされ検索エンジン型が利用可能
  #expect(Fuse.self == Fuse.self)
}
