import EmojiKit
import Foundation
import Testing

@testable import IgniteroCore

// MARK: - EmojiCategoryDisplayName Tests

/// EmojiPickerPanel 起動時クラッシュの回帰テスト。
///
/// 原因（2026-06-25 クラッシュレポート）:
/// `CategoryTabButton.body` の `.help(cat.localizedName)` および
/// `EmojiGrid.sectionTitle` のデフォルト `$0.view` (= `Emoji.GridSectionTitle`)
/// が EmojiKit 内部で `Bundle.module` を参照し、`.app` 配置時に SwiftPM の
/// リソースバンドル解決が失敗して `assertionFailure` → SIGTRAP。
///
/// このテスト群は Bundle.module を踏まない `EmojiCategoryDisplayName` が
/// 全標準カテゴリ・persisted カテゴリ（frequent / recent / favorites）で
/// 空でない表示名を返し、`cat.localizedName` を呼ばなくても運用できることを
/// 保証する。
@Suite("EmojiCategoryDisplayName")
struct EmojiCategoryDisplayNameTests {

  // MARK: - 標準カテゴリ網羅

  @Test("standardGrid の全カテゴリで空でない日本語表示名を返す")
  func standardGridCategoriesHaveJapaneseNames() {
    let categories: [EmojiCategory] = .standardGrid
    for category in categories {
      let text = EmojiCategoryDisplayName.jaTable[category.id]
      #expect(text != nil, "ID \(category.id) の日本語表示名が未登録")
      #expect(text?.isEmpty == false, "ID \(category.id) の日本語表示名が空")
    }
  }

  @Test("standardGrid の全カテゴリで空でない英語表示名を返す")
  func standardGridCategoriesHaveEnglishNames() {
    let categories: [EmojiCategory] = .standardGrid
    for category in categories {
      let text = EmojiCategoryDisplayName.enTable[category.id]
      #expect(text != nil, "ID \(category.id) の英語表示名が未登録")
      #expect(text?.isEmpty == false, "ID \(category.id) の英語表示名が空")
    }
  }

  // MARK: - クラッシュ非発生の保証

  @Test("standardGrid の全カテゴリで text(for:) がクラッシュせず返す")
  func textForDoesNotCrashForAllStandardCategories() {
    let categories: [EmojiCategory] = .standardGrid
    for category in categories {
      let text = EmojiCategoryDisplayName.text(for: category)
      #expect(!text.isEmpty, "ID \(category.id) で空文字が返された")
    }
  }

  @Test("text(forId:) は未知 ID を ID そのまま返す")
  func textForIdReturnsIdForUnknownId() {
    #expect(EmojiCategoryDisplayName.text(forId: "completely_unknown") == "completely_unknown")
  }

  // MARK: - カスタムカテゴリの優先順位

  @Test("custom カテゴリで name が指定されていれば name を優先する")
  func customCategoryPrefersExplicitName() {
    let cat = EmojiCategory.custom(
      id: "my_custom",
      name: "My Custom Category",
      emojis: [],
      iconName: "star"
    )
    #expect(EmojiCategoryDisplayName.text(for: cat) == "My Custom Category")
  }

  @Test("custom カテゴリで name が nil の場合は id ベースで解決する")
  func customCategoryFallsBackToIdLookup() {
    // persisted カテゴリは内部で .custom(id: "frequent", name: nil, ...) として表現される
    let cat = EmojiCategory.persisted(.frequent)
    let text = EmojiCategoryDisplayName.text(for: cat)
    let expected = EmojiCategoryDisplayName.isJapaneseLocale ? "よく使う項目" : "Frequently Used"
    #expect(text == expected)
  }

  // MARK: - 個別の翻訳キー

  @Test("日本語テーブルの主要キーが期待通りの文言を返す")
  func japaneseTableHasExpectedStrings() {
    #expect(EmojiCategoryDisplayName.jaTable["smileysAndPeople"] == "笑顔と人")
    #expect(EmojiCategoryDisplayName.jaTable["frequent"] == "よく使う項目")
    #expect(EmojiCategoryDisplayName.jaTable["search"] == "検索結果")
  }

  @Test("英語テーブルの主要キーが期待通りの文言を返す")
  func englishTableHasExpectedStrings() {
    #expect(EmojiCategoryDisplayName.enTable["smileysAndPeople"] == "Smileys & People")
    #expect(EmojiCategoryDisplayName.enTable["frequent"] == "Frequently Used")
    #expect(EmojiCategoryDisplayName.enTable["search"] == "Search Results")
  }
}
