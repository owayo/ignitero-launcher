import Foundation
import Testing

@testable import IgniteroCore

@Suite("IconCacheManager")
struct IconCacheManagerTests {

  private func makeTempDir() throws -> String {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("ignitero-icon-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.path
  }

  private func cleanup(_ path: String) {
    try? FileManager.default.removeItem(atPath: path)
  }

  @Test func cachedIconPathProducesDeterministicHash() throws {
    let tmpDir = try makeTempDir()
    defer { cleanup(tmpDir) }

    let manager = IconCacheManager(cacheDirectory: tmpDir)
    let path1 = manager.cachedIconPath(for: "/Applications/Safari.app")
    let path2 = manager.cachedIconPath(for: "/Applications/Safari.app")

    #expect(path1 == path2)
    #expect(path1.hasSuffix(".png"))
    #expect(path1.hasPrefix(tmpDir))
  }

  @Test func cachedIconPathDiffersForDifferentApps() throws {
    let tmpDir = try makeTempDir()
    defer { cleanup(tmpDir) }

    let manager = IconCacheManager(cacheDirectory: tmpDir)
    let pathSafari = manager.cachedIconPath(for: "/Applications/Safari.app")
    let pathFinder = manager.cachedIconPath(for: "/System/Applications/Finder.app")

    #expect(pathSafari != pathFinder)
  }

  @Test func cacheIconCreatesCacheDirectoryIfNeeded() throws {
    let tmpDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("ignitero-icon-test-\(UUID().uuidString)")
      .appendingPathComponent("nested")
    defer { cleanup(tmpDir.deletingLastPathComponent().path) }

    let manager = IconCacheManager(cacheDirectory: tmpDir.path)

    #expect(!FileManager.default.fileExists(atPath: tmpDir.path))
    try manager.ensureCacheDirectory()
    #expect(FileManager.default.fileExists(atPath: tmpDir.path))
  }

  @Test func cacheIconSkipsWhenCacheExists() throws {
    let tmpDir = try makeTempDir()
    defer { cleanup(tmpDir) }

    let manager = IconCacheManager(cacheDirectory: tmpDir)
    let appPath = "/Applications/Safari.app"
    let cachedPath = manager.cachedIconPath(for: appPath)

    // 既存のキャッシュファイルを作成
    try "fake-png-data".write(toFile: cachedPath, atomically: true, encoding: .utf8)

    // cacheIcon はスキップして既存パスを返す
    let result = try manager.cacheIcon(from: "/fake/icon.icns", for: appPath)
    #expect(result == cachedPath)

    // ファイル内容が変更されていないことを確認
    let content = try String(contentsOfFile: cachedPath, encoding: .utf8)
    #expect(content == "fake-png-data")
  }

  @Test func cachedIconPathContainsHashFilename() throws {
    let tmpDir = try makeTempDir()
    defer { cleanup(tmpDir) }

    let manager = IconCacheManager(cacheDirectory: tmpDir)
    let path = manager.cachedIconPath(for: "/Applications/Safari.app")
    let filename = (path as NSString).lastPathComponent

    // ハッシュベースのファイル名 (hex文字列 + .png)
    #expect(filename.hasSuffix(".png"))
    let hashPart = String(filename.dropLast(4))  // .png を除去
    #expect(hashPart.count == 32)  // SHA256 の先頭16バイト = 32文字の hex
    #expect(hashPart.allSatisfy { $0.isHexDigit })
  }
}
