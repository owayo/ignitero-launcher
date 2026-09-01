import EmojiKit
import Foundation
import Testing

@testable import IgniteroCore

// MARK: - ロケール候補

@Suite("EmojiLocalizedNames ロケール候補")
struct EmojiLocalizedNamesLocaleCandidatesTests {

  @Test("地域付き識別子は言語コードへフォールバックする")
  func regionalIdentifierFallsBackToLanguageCode() {
    // EmojiKit のバンドルは `ja.lproj` しか持たないため、`ja_JP` で引けない場合に
    // 言語コード単体で再試行できないと日本語名が一切引けなくなる。
    let candidates = EmojiLocalizedNames.localeCandidates(for: Locale(identifier: "ja_JP"))
    #expect(candidates == ["ja_JP", "ja"])
  }

  @Test("言語コードのみの識別子は重複候補を作らない")
  func languageOnlyIdentifierHasNoDuplicate() {
    let candidates = EmojiLocalizedNames.localeCandidates(for: Locale(identifier: "ja"))
    #expect(candidates == ["ja"])
  }

  @Test("英語ロケールでも識別子と言語コードの両方を候補にする")
  func englishLocaleIncludesBothCandidates() {
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
    let container = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("EmojiLocalizedNamesTests-\(UUID().uuidString)")
    let root = container.appendingPathComponent("Fake_Fake.bundle")
    let lproj = root.appendingPathComponent("\(lang).lproj")
    try FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
    try (entries as NSDictionary).write(
      to: lproj.appendingPathComponent("Localizable.strings"), atomically: true)

    guard let bundle = Bundle(url: root) else {
      throw CocoaError(.fileNoSuchFile)
    }
    return (bundle, { try FileManager.default.removeItem(at: container) })
  }

  @Test("バンドルが解決できない場合は空辞書へ縮退する")
  func unresolvedBundleYieldsEmptyTable() {
    // `Bundle.module` は非 Optional で fatalError するため、代替実装は必ず
    // nil バンドルを受け取っても落ちず空辞書を返さなければならない。
    let table = EmojiLocalizedNames.loadTable(bundle: nil, locale: Locale(identifier: "ja"))
    #expect(table.isEmpty)
  }

  @Test("ロケールが一致する Localizable.strings を辞書として読む")
  func readsMatchingLocaleStrings() throws {
    let (bundle, cleanup) = try makeBundle(lang: "ja", entries: ["😀": "にっこり顔"])
    defer { try? cleanup() }

    let table = EmojiLocalizedNames.loadTable(bundle: bundle, locale: Locale(identifier: "ja"))
    #expect(table["😀"] == "にっこり顔")
  }

  @Test("地域付きロケールでも言語コードの Localizable.strings を読む")
  func readsLanguageCodeStringsForRegionalLocale() throws {
    let (bundle, cleanup) = try makeBundle(lang: "ja", entries: ["😀": "にっこり顔"])
    defer { try? cleanup() }

    let table = EmojiLocalizedNames.loadTable(bundle: bundle, locale: Locale(identifier: "ja_JP"))
    #expect(table["😀"] == "にっこり顔")
  }

  @Test("ロケールが一致しない場合は空辞書を返す")
  func mismatchedLocaleYieldsEmptyTable() throws {
    let (bundle, cleanup) = try makeBundle(lang: "ja", entries: ["😀": "にっこり顔"])
    defer { try? cleanup() }

    let table = EmojiLocalizedNames.loadTable(bundle: bundle, locale: Locale(identifier: "de"))
    #expect(table.isEmpty)
  }
}

// MARK: - EmojiKit のリソースレイアウト前提

/// `EmojiLocalizedNames` は EmojiKit のリソースが「`<lang>.lproj/Localizable.strings`」
/// というレイアウトで、かつ「キー = 絵文字そのもの」であることに依存している。
/// EmojiKit を更新してここが変わるとテーブルが無音で空になり、ローカライズ名検索だけが
/// 静かに死ぬ（クラッシュしないので気づきにくい）。疑似バンドルではなく実際のリソースに
/// 対して前提が崩れていないことを検証する。
@Suite("EmojiKit リソースレイアウトの前提")
struct EmojiKitResourceLayoutTests {

  /// ビルド済みのリソースバンドル、無ければ checkouts のリソース原本を返す。
  static func emojiKitResourceRoot() -> URL? {
    if let bundle = ResourceBundle.emojiKit { return bundle.bundleURL }

    let fm = FileManager.default
    let buildDir = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // IgniteroCoreTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // リポジトリルート
      .appendingPathComponent(".build")

    func hasJapaneseLproj(_ url: URL) -> Bool {
      fm.fileExists(atPath: url.appendingPathComponent("ja.lproj").path)
    }

    // .build/<triple>/<config>/EmojiKit_EmojiKit.bundle
    if let entries = try? fm.contentsOfDirectory(at: buildDir, includingPropertiesForKeys: nil) {
      for entry in entries {
        for config in ["debug", "release"] {
          let candidate = entry.appendingPathComponent(config)
            .appendingPathComponent("EmojiKit_EmojiKit.bundle")
          if hasJapaneseLproj(candidate) { return candidate }
        }
      }
    }

    // ビルド前のリソース原本
    let checkout = buildDir.appendingPathComponent("checkouts/EmojiKit/Sources/EmojiKit/Resources")
    return hasJapaneseLproj(checkout) ? checkout : nil
  }

  @Test("ja.lproj/Localizable.strings が絵文字そのものをキーにしている")
  func japaneseStringsAreKeyedByEmojiChar() throws {
    let root = try #require(
      Self.emojiKitResourceRoot(),
      "EmojiKit のリソースが見つからない。`swift build` 済みか、EmojiKit のリソース構成が変わっていないか確認する")
    let url = root.appendingPathComponent("ja.lproj").appendingPathComponent("Localizable.strings")
    let dict = try #require(
      NSDictionary(contentsOf: url) as? [String: String],
      "ja.lproj/Localizable.strings を [String: String] として読めない（String Catalog へ移行した可能性）")

    #expect(dict["😀"] != nil, "キーが絵文字そのものでなくなった可能性がある")
    #expect(dict.count > 1000, "ローカライズ名の件数が想定より少ない（実測 1,885 件）")
  }

  @Test("実リソースから日本語のローカライズ名を引ける")
  func loadsJapaneseNameFromRealResources() throws {
    let root = try #require(Self.emojiKitResourceRoot())
    let bundle = try #require(Bundle(url: root))

    let table = EmojiLocalizedNames.loadTable(bundle: bundle, locale: Locale(identifier: "ja_JP"))
    #expect(table["😀"]?.isEmpty == false)
  }

  @Test("実リソース由来のローカライズ名で一致判定できる")
  func matchesByLocalizedNameFromRealResources() throws {
    let root = try #require(Self.emojiKitResourceRoot())
    let bundle = try #require(Bundle(url: root))
    let table = EmojiLocalizedNames.loadTable(bundle: bundle, locale: Locale(identifier: "ja_JP"))
    let name = try #require(table["😀"])

    // ローカライズ名の一部で一致すること（Unicode 名は英語なので日本語では一致しない）。
    #expect(name.localizedCaseInsensitiveContains(String(name.prefix(2))))
  }
}

// MARK: - ResourceBundle

@Suite("ResourceBundle の解決")
struct ResourceBundleResolveTests {

  @Test("存在しないバンドル名では nil を返す")
  func missingBundleResolvesToNil() {
    // `Bundle.module` はここで fatalError していた。解決失敗は必ず nil で返す。
    #expect(ResourceBundle.resolve(named: "NotExisting_NotExisting.bundle") == nil)
  }
}

// MARK: - Bundle.module を踏まない一致判定

@Suite("EmojiKeywordSearch.standardMatches")
struct EmojiStandardMatchesTests {

  @Test("絵文字そのものと完全一致する")
  func matchesExactChar() {
    #expect(EmojiKeywordSearch.standardMatches(Emoji("😀"), query: "😀"))
  }

  @Test("Unicode 名の部分一致で真を返す")
  func matchesUnicodeNameSubstring() {
    // ローカライズ名テーブルが空でも Unicode 名だけで検索が成立することを保証する
    // （バンドル未解決時の縮退動作）。
    #expect(EmojiKeywordSearch.standardMatches(Emoji("😀"), query: "grinning"))
  }

  @Test("Unicode 名の大文字小文字を無視する")
  func matchesUnicodeNameCaseInsensitively() {
    #expect(EmojiKeywordSearch.standardMatches(Emoji("😀"), query: "GRINNING"))
  }

  @Test("無関係なクエリでは偽を返す")
  func doesNotMatchUnrelatedQuery() {
    #expect(!EmojiKeywordSearch.standardMatches(Emoji("😀"), query: "zzzzzunmatched"))
  }

  @Test("全絵文字を走査しても Bundle.module を踏まずに完走する")
  func scansAllEmojisWithoutTouchingBundleModule() {
    // EmojiKit の `Emoji.matches(_:)` はこの全走査の途中で `Bundle.module` を
    // 初期化して SIGTRAP した（2026-09-01）。代替実装は全件走っても落ちない。
    for emoji in Emoji.all {
      _ = EmojiKeywordSearch.standardMatches(emoji, query: "face")
    }
  }
}
