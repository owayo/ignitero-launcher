import EmojiKit
import Foundation
import Testing

@testable import IgniteroCore

// MARK: - ロケール候補

@Suite("EmojiLocalizedNames ロケール候補")
struct EmojiLocalizedNamesLocaleCandidatesTests {

  @Test func 地域付き識別子は言語コードへフォールバックする() {
    // EmojiKit のバンドルは `ja.lproj` しか持たないため、`ja_JP` で引けない場合に
    // 言語コード単体で再試行できないと日本語名が一切引けなくなる。
    let candidates = EmojiLocalizedNames.localeCandidates(for: Locale(identifier: "ja_JP"))
    #expect(candidates == ["ja_JP", "ja"])
  }

  @Test func 言語コードのみの識別子は重複を作らない() {
    let candidates = EmojiLocalizedNames.localeCandidates(for: Locale(identifier: "ja"))
    #expect(candidates == ["ja"])
  }

  @Test func 未知のロケールでも候補を返す() {
    let candidates = EmojiLocalizedNames.localeCandidates(for: Locale(identifier: "en_US"))
    #expect(candidates.first == "en_US")
    #expect(candidates.contains("en"))
  }
}

// MARK: - テーブルのロード

@Suite("EmojiLocalizedNames テーブルのロード")
struct EmojiLocalizedNamesLoadTableTests {

  /// `<lang>.lproj/Localizable.strings` を持つ疑似リソースバンドルを一時ディレクトリに作る。
  private func makeBundle(
    lang: String,
    entries: [String: String]
  ) throws -> (bundle: Bundle, cleanup: () throws -> Void) {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("EmojiLocalizedNamesTests-\(UUID().uuidString)")
      .appendingPathComponent("Fake_Fake.bundle")
    let lproj = root.appendingPathComponent("\(lang).lproj")
    try FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
    try (entries as NSDictionary).write(
      to: lproj.appendingPathComponent("Localizable.strings"), atomically: true)

    guard let bundle = Bundle(url: root) else {
      throw CocoaError(.fileNoSuchFile)
    }
    return (
      bundle,
      {
        try FileManager.default.removeItem(at: root.deletingLastPathComponent())
      }
    )
  }

  @Test func バンドルが解決できない場合は空辞書へ縮退する() {
    // `Bundle.module` は非 Optional で fatalError するため、代替実装は必ず
    // nil バンドルを受け取っても落ちず空辞書を返さなければならない。
    let table = EmojiLocalizedNames.loadTable(bundle: nil, locale: Locale(identifier: "ja"))
    #expect(table.isEmpty)
  }

  @Test func ロケール一致する strings を辞書として読む() throws {
    let (bundle, cleanup) = try makeBundle(lang: "ja", entries: ["😀": "にっこり顔"])
    defer { try? cleanup() }

    let table = EmojiLocalizedNames.loadTable(bundle: bundle, locale: Locale(identifier: "ja"))
    #expect(table["😀"] == "にっこり顔")
  }

  @Test func 地域付きロケールでも言語コードの strings を読む() throws {
    let (bundle, cleanup) = try makeBundle(lang: "ja", entries: ["😀": "にっこり顔"])
    defer { try? cleanup() }

    let table = EmojiLocalizedNames.loadTable(bundle: bundle, locale: Locale(identifier: "ja_JP"))
    #expect(table["😀"] == "にっこり顔")
  }

  @Test func ロケールが一致しない場合は空辞書を返す() throws {
    let (bundle, cleanup) = try makeBundle(lang: "ja", entries: ["😀": "にっこり顔"])
    defer { try? cleanup() }

    let table = EmojiLocalizedNames.loadTable(bundle: bundle, locale: Locale(identifier: "de"))
    #expect(table.isEmpty)
  }
}

// MARK: - ResourceBundle

@Suite("ResourceBundle の解決")
struct ResourceBundleResolveTests {

  @Test func 存在しないバンドル名では nil を返す() {
    // `Bundle.module` はここで fatalError していた。解決失敗は必ず nil で返す。
    #expect(ResourceBundle.resolve(named: "NotExisting_NotExisting.bundle") == nil)
  }
}

// MARK: - Bundle.module を踏まない一致判定

@Suite("EmojiKeywordSearch.standardMatches")
struct EmojiStandardMatchesTests {

  @Test func 絵文字そのものと完全一致する() {
    #expect(EmojiKeywordSearch.standardMatches(Emoji("😀"), query: "😀"))
  }

  @Test func Unicode 名の部分一致で真を返す() {
    // ローカライズ名テーブルが空でも Unicode 名だけで検索が成立することを保証する
    // （バンドル未解決時の縮退動作）。
    #expect(EmojiKeywordSearch.standardMatches(Emoji("😀"), query: "grinning"))
  }

  @Test func Unicode 名の大文字小文字を無視する() {
    #expect(EmojiKeywordSearch.standardMatches(Emoji("😀"), query: "GRINNING"))
  }

  @Test func 無関係なクエリでは偽を返す() {
    #expect(!EmojiKeywordSearch.standardMatches(Emoji("😀"), query: "zzzzzunmatched"))
  }

  @Test func 全絵文字に対して Bundle_module を踏まず判定できる() {
    // EmojiKit の `Emoji.matches(_:)` はこの全走査の途中で `Bundle.module` を
    // 初期化して SIGTRAP した（2026-09-01）。代替実装が全件走っても落ちないこと。
    for emoji in Emoji.all {
      _ = EmojiKeywordSearch.standardMatches(emoji, query: "face")
    }
  }
}
