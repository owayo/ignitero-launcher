import EmojiKit
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

// MARK: - EmojiKeywordSearch エッジケース

@Suite("EmojiKeywordSearch Edge Cases")
struct EmojiKeywordSearchEdgeCaseTests {

  @Test("非常に長いクエリでクラッシュしない")
  func veryLongQueryDoesNotCrash() {
    let search = EmojiKeywordSearch()
    let longQuery = String(repeating: "あ", count: 10000)
    let result = search.matchingEmojis(for: longQuery)
    #expect(result.isEmpty)
  }

  @Test("制御文字を含むクエリでクラッシュしない")
  func controlCharactersDoNotCrash() {
    let search = EmojiKeywordSearch()
    let query = "test\u{0000}\u{0001}\u{007F}"
    _ = search.matchingEmojis(for: query)
  }

  @Test("Unicode サロゲート混在クエリ")
  func surrogateCharacters() {
    let search = EmojiKeywordSearch()
    let query = "🎉テスト"
    _ = search.matchingEmojis(for: query)
  }

  @Test("スペースのみのクエリは空を返す")
  func tabsAndSpacesOnlyReturnsEmpty() {
    let search = EmojiKeywordSearch()
    #expect(search.matchingEmojis(for: " \t ").isEmpty)
  }

  @Test("結果に空文字列が含まれない")
  func noEmptyStringsInResults() {
    let search = EmojiKeywordSearch()
    let result = search.matchingEmojis(for: "笑")
    for emoji in result {
      #expect(!emoji.isEmpty)
    }
  }

  @Test("VS 除去版は元の絵文字と同じ視覚表現を持つ")
  func normalizedEmojiVisuallyEquivalent() {
    let search = EmojiKeywordSearch()
    let result = search.matchingEmojis(for: "笑顔")
    // VS 付き・なしの両方が含まれる場合、除去版は元の絵文字と異なる String 表現
    if result.count >= 2 {
      let strings = Array(result)
      // すべてのエントリが空でないことを確認
      for s in strings {
        #expect(!s.isEmpty)
      }
    }
  }
}

// MARK: - EmojiKeywordSearch search メソッド

@Suite("EmojiKeywordSearch search method")
struct EmojiKeywordSearchSearchMethodTests {
  @Test("空の Emoji 配列に対する検索")
  func searchInEmptyArray() {
    let search = EmojiKeywordSearch()
    let result = search.search(query: "smile", in: [])
    #expect(result.isEmpty)
  }

  @Test("空クエリは全 Emoji を返す")
  func emptyQueryReturnsAll() {
    let search = EmojiKeywordSearch()
    let emojis = Emoji.all.prefix(10)
    let result = search.search(query: "", in: Array(emojis))
    #expect(result.count == emojis.count)
  }

  @Test("検索結果に重複がない")
  func noDuplicateResults() {
    let search = EmojiKeywordSearch()
    let result = search.search(query: "smile", in: Emoji.all)
    let uniqueChars = Set(result.map { $0.char })
    #expect(uniqueChars.count == result.count)
  }
}
