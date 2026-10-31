import AppKit
import Foundation
import Testing

@testable import IgniteroCore

/// ブランドアイコンの読み込み。テストではブランドのロゴではなく、汎用の図形の SVG を使う。
@Suite("Provider logo store")
@MainActor
struct ProviderLogoStoreTests {
  private static let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // IgniteroCoreTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // リポジトリのルート

  /// 正規化後と同じ形 (width/height を viewBox と同じ数値で持つ) の汎用の図形。
  private static func shapeSVG(width: String = "24", height: String = "24") -> String {
    """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(width) \(height)" \
    width="\(width)" height="\(height)"><path d="M2 2h20v15H2z" fill="#000000"/></svg>
    """
  }

  private func temporaryDirectory(_ files: [String: String]) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ProviderLogoStoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for (name, contents) in files {
      try Data(contents.utf8).write(to: directory.appendingPathComponent(name))
    }
    return directory
  }

  @Test func loadsTemplateImagesThatActuallyDraw() throws {
    let directory = try temporaryDirectory([
      "openai.svg": Self.shapeSVG(), "pixellab.svg": Self.shapeSVG(width: "24", height: "19.2"),
    ])
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ProviderLogoStore(directory: directory)
    // Codex は OpenAI のマークを読む。
    let codex = try #require(store.image(for: .codex))
    #expect(codex.isTemplate)
    #expect(codex.size == NSSize(width: 24, height: 24))
    #expect(ProviderLogoStore.coverage(of: codex) > 0.3)
    // 正方形でない viewBox も縦横比を保つ。
    let pixellab = try #require(store.image(for: .pixellab))
    #expect(abs(pixellab.size.width / pixellab.size.height - 24 / 19.2) < 0.001)
  }

  @Test func missingOrBrokenFilesFallBackToNil() throws {
    let directory = try temporaryDirectory(["claude.svg": "not an svg"])
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ProviderLogoStore(directory: directory)
    #expect(store.image(for: .claude) == nil)
    #expect(store.image(for: .grok) == nil)
    #expect(ProviderLogoStore(directory: nil).image(for: .claude) == nil)
  }

  @Test func resultsAreRememberedWithoutRereadingFiles() throws {
    let directory = try temporaryDirectory(["grok.svg": Self.shapeSVG()])
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ProviderLogoStore(directory: directory)
    let first = try #require(store.image(for: .grok))
    #expect(store.image(for: .antigravity) == nil)
    // 描画のたびにファイルを読まない: 後から消しても置いても結果は変わらない。
    try FileManager.default.removeItem(at: directory.appendingPathComponent("grok.svg"))
    try Data(Self.shapeSVG().utf8).write(to: directory.appendingPathComponent("antigravity.svg"))
    #expect(store.image(for: .grok) === first)
    #expect(store.image(for: .antigravity) == nil)
  }

  /// 取得元の lock がすべてのプロバイダを網羅し、リポジトリに置く自作のアイコンが描けること。
  /// ダウンロードする SVG はコミットしないため、ここでは lock の記載だけを確かめる。
  @Test func lockFileCoversEveryProviderLogo() throws {
    let lockURL = Self.repositoryRoot.appendingPathComponent("Resources/provider-logos.lock.json")
    let lock = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: lockURL)) as? [String: Any])
    let version = try #require(lock["version"] as? String)
    let baseURL = try #require(lock["base_url"] as? String)
    #expect(baseURL.contains("@\(version)/"), "取得元の URL は版を固定する")
    let files = try #require(lock["files"] as? [String: String])
    let local = try #require(lock["local"] as? [String])
    for hash in files.values {
      #expect(hash.count == 64 && hash.allSatisfy(\.isHexDigit))
    }
    let listed = Set(files.keys).union(local)
    let expected = Set(AIUsageProvider.allCases.map { "\($0.logoResourceName).svg" })
    #expect(listed == expected)
    #expect(Set(files.keys).isDisjoint(with: local))

    let license = try #require(lock["license"] as? String)
    #expect(
      FileManager.default.fileExists(
        atPath: Self.repositoryRoot.appendingPathComponent(license).path))

    let localStore = ProviderLogoStore(
      directory: Self.repositoryRoot.appendingPathComponent("Resources/ProviderLogos"))
    for name in local {
      let provider = try #require(
        AIUsageProvider.allCases.first { "\($0.logoResourceName).svg" == name })
      let image = try #require(localStore.image(for: provider), "\(name)")
      #expect(ProviderLogoStore.coverage(of: image) > 0.05, "\(name)")
    }
  }
}
