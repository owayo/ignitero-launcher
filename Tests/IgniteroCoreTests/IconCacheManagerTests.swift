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

  @Test("並行 cacheIcon でも生成された PNG は壊れない（アトミック書き込み）")
  func concurrentCacheIconProducesValidPNG() async throws {
    let tmpDir = try makeTempDir()
    defer { cleanup(tmpDir) }

    // 既存システムアイコン (.icns) のパス。Finder アイコンが安定して存在する。
    let icnsPath = "/System/Applications/Utilities/Terminal.app/Contents/Resources/Terminal.icns"
    guard FileManager.default.fileExists(atPath: icnsPath) else {
      // CI 等で利用できない場合はスキップ相当
      return
    }

    let manager = IconCacheManager(cacheDirectory: tmpDir)
    let appPath = "/Applications/Concurrent.app"
    let outputPath = manager.cachedIconPath(for: appPath)

    // 並行して 8 回呼び出し、同じ出力パスへの書き込みが破綻しないことを確認する
    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<8 {
        group.addTask {
          _ = try? manager.cacheIcon(from: icnsPath, for: appPath)
        }
      }
    }

    // 出力ファイルが存在し、PNG として読めること（途中切り詰めや空ファイルになっていないこと）
    #expect(FileManager.default.fileExists(atPath: outputPath))
    let data = try Data(contentsOf: URL(fileURLWithPath: outputPath))
    #expect(data.count > 0)
    // PNG マジックナンバー (89 50 4E 47 0D 0A 1A 0A)
    let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    #expect(data.prefix(pngMagic.count) == Data(pngMagic))
  }
}
