import Foundation
import Testing

@testable import IgniteroCore

@Suite("DirectoryPathResolver")
struct DirectoryPathResolverTests {

  /// `URL.deletingLastPathComponent()` は `..` を解決しないため、末尾が `..` の URL では
  /// 同じ URL を返し続ける（不動点）。正規化なしで遡上すると while ループが停止せず、
  /// 設定画面のフォルダ選択ボタンからメインスレッドで呼ばれてアプリごと固まる。
  /// このテストは「戻ってくること」自体が検証対象（回帰するとハングする）。
  @Test("実在しない要素と .. を含むパスでも停止する")
  func terminatesForDotDotPath() {
    let url = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/../foo")
    _ = DirectoryPathResolver.existingAncestor(of: url)
  }

  @Test("末尾が .. のパスでも停止する")
  func terminatesForTrailingDotDot() {
    let url = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/..")
    _ = DirectoryPathResolver.existingAncestor(of: url)
  }

  @Test("実在する最も近い祖先を返す")
  func returnsNearestExistingAncestor() throws {
    let base = FileManager.default.temporaryDirectory
      .appendingPathComponent("ignitero-resolver-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }

    let missing = base.appendingPathComponent("missing").appendingPathComponent("child")
    let resolved = DirectoryPathResolver.existingAncestor(of: missing)
    #expect(resolved?.standardizedFileURL.path == base.standardizedFileURL.path)
  }

  @Test(".. を畳んでから祖先を探す")
  func resolvesDotDotBeforeWalkingUp() throws {
    let base = FileManager.default.temporaryDirectory
      .appendingPathComponent("ignitero-resolver-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }

    // base/missing/../child → base/child（base は実在、child は実在しない）
    let url =
      base
      .appendingPathComponent("missing")
      .appendingPathComponent("..")
      .appendingPathComponent("child")
    let resolved = DirectoryPathResolver.existingAncestor(of: url)
    #expect(resolved?.standardizedFileURL.path == base.standardizedFileURL.path)
  }

  @Test("ルート直下の実在しないパスではルートを返す")
  func returnsRootForTopLevelMissingPath() {
    let url = URL(fileURLWithPath: "/missing-\(UUID().uuidString)")
    #expect(DirectoryPathResolver.existingAncestor(of: url)?.path == "/")
  }
}
