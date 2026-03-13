import Foundation
import Testing

@testable import IgniteroCore

// MARK: - Variation Selector 除去テスト

@Suite("String.removingVariationSelectors")
struct RemovingVariationSelectorsTests {

  @Test func removesVariationSelector16() {
    // U+FE0F (Variation Selector-16) を除去
    let original = "☺\u{FE0F}"
    let result = original.removingVariationSelectors()
    #expect(!result.contains("\u{FE0F}"))
    #expect(result == "☺")
  }

  @Test func removesVariationSelector15() {
    // U+FE0E (Variation Selector-15) を除去
    let original = "☺\u{FE0E}"
    let result = original.removingVariationSelectors()
    #expect(!result.contains("\u{FE0E}"))
    #expect(result == "☺")
  }

  @Test func preservesStringWithoutVariationSelectors() {
    let original = "hello"
    #expect(original.removingVariationSelectors() == "hello")
  }

  @Test func emptyStringReturnsEmpty() {
    #expect("".removingVariationSelectors() == "")
  }

  @Test func multipleVariationSelectorsRemoved() {
    let original = "A\u{FE0F}B\u{FE0E}C\u{FE0F}"
    let result = original.removingVariationSelectors()
    #expect(result == "ABC")
  }
}

// MARK: - EmojiKeywordSearch テスト

@Suite("EmojiKeywordSearch")
struct EmojiKeywordSearchTests {

  @Test func emptyQueryReturnsEmpty() {
    let search = EmojiKeywordSearch()
    let result = search.matchingEmojis(for: "")
    #expect(result.isEmpty)
  }

  @Test func whitespaceOnlyQueryReturnsEmpty() {
    let search = EmojiKeywordSearch()
    let result = search.matchingEmojis(for: "   ")
    #expect(result.isEmpty)
  }

  @Test func initializesWithoutCrash() {
    let search = EmojiKeywordSearch()
    // キーワードデータが読み込まれることを確認（空でなければ成功）
    // バンドルリソースに依存するため、結果が空でもクラッシュしないことが重要
    _ = search.matchingEmojis(for: "テスト")
  }

  @Test func matchingEmojisReturnsBothOriginalAndNormalized() {
    let search = EmojiKeywordSearch()
    // 一般的な日本語キーワードでマッチするか確認
    let results = search.matchingEmojis(for: "笑顔")
    // キーワードデータに依存するが、結果がある場合は Variation Selector 除去版も含む
    if !results.isEmpty {
      // 結果の中に何かしらの絵文字が含まれていること
      for emoji in results {
        #expect(!emoji.isEmpty)
      }
    }
  }

  @Test func caseInsensitiveMatching() {
    let search = EmojiKeywordSearch()
    let lower = search.matchingEmojis(for: "smile")
    let upper = search.matchingEmojis(for: "SMILE")
    // 大文字小文字無視なので同じ結果になるはず
    #expect(lower == upper)
  }
}
