import Foundation
import Fuse
import GRDB
import KeyboardShortcuts
import Testing

@testable import IgniteroCore

/// ソースツリーの `Resources/Info.plist` を指す URL。
///
/// バージョンの正本はこのファイルの `CFBundleShortVersionString` ただ 1 つで、
/// リリースワークフローが bump するのもここだけ。テスト側に具体的な値を書くと
/// それが 2 つ目の正本になってしまうため、書式の妥当性だけを検証する。
private func sourceInfoPlistURL() -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // IgniteroCoreTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // リポジトリルート
    .appendingPathComponent("Resources/Info.plist")
}

@Test func projectVersionIsDefinedOnlyInInfoPlist() throws {
  let data = try Data(contentsOf: sourceInfoPlistURL())
  let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
  let dictionary = try #require(object as? [String: Any])
  let version = try #require(dictionary["CFBundleShortVersionString"] as? String)

  // release.yml が生成するのは YY.M.連番 形式。数値 3 要素であることを担保する。
  let components = version.split(separator: ".")
  #expect(components.count == 3)
  #expect(components.allSatisfy { Int($0) != nil })
}

@Test func grdbDependencyAvailable() {
  // GRDB が正しくインポートされ DatabaseQueue 型が利用可能
  #expect(DatabaseQueue.self == DatabaseQueue.self)
}

@Test func fuseDependencyAvailable() {
  // Fuse がインポートされ検索エンジン型が利用可能
  #expect(Fuse.self == Fuse.self)
}
