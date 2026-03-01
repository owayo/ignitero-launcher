import EmojiKit
import Foundation

/// emojibase ベースの日本語絵文字キーワード検索。
///
/// バンドルリソース `emoji_keywords_ja.json` を読み込み、
/// 絵文字文字列 → キーワード配列のマッピングで検索を行う。
/// EmojiKit の `localizedName` 検索では対応できない
/// 「いいね」→ 👍 のような日本語キーワード検索を提供する。
public final class EmojiKeywordSearch: Sendable {

  /// emoji 文字列 → キーワード配列
  private let keywords: [String: [String]]

  /// 正規化済みの emoji 文字列 → 元の emoji 文字列 のマッピング
  ///
  /// emojibase のデータには Variation Selector (U+FE0F) 付きの
  /// 文字列が含まれるため、VS を除去した文字列でもルックアップ可能にする。
  private let normalizedLookup: [String: String]

  public init() {
    guard let url = Bundle.module.url(forResource: "emoji_keywords_ja", withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let dict = try? JSONDecoder().decode([String: [String]].self, from: data)
    else {
      self.keywords = [:]
      self.normalizedLookup = [:]
      return
    }
    self.keywords = dict

    // Variation Selector 除去版のルックアップを構築
    var lookup: [String: String] = [:]
    for key in dict.keys {
      let normalized = key.removingVariationSelectors()
      lookup[normalized] = key
    }
    self.normalizedLookup = lookup
  }

  /// クエリにマッチする絵文字の集合を返す。
  ///
  /// キーワード辞書の各エントリについて、キーワードのいずれかが
  /// クエリを部分一致（大文字小文字無視）で含むかを判定する。
  /// - Parameter query: 検索クエリ
  /// - Returns: マッチした絵文字文字列の Set
  public func matchingEmojis(for query: String) -> Set<String> {
    let q = query.trimmingCharacters(in: .whitespaces)
    guard !q.isEmpty else { return [] }

    var result: Set<String> = []
    for (emoji, tags) in keywords {
      if tags.contains(where: { $0.localizedCaseInsensitiveContains(q) }) {
        // VS 除去版も追加（EmojiKit 側のマッチング用）
        result.insert(emoji)
        result.insert(emoji.removingVariationSelectors())
      }
    }
    return result
  }

  /// EmojiKit の Emoji 配列からクエリにマッチするものを返す。
  ///
  /// EmojiKit 標準の localizedName 検索と、本クラスのキーワード検索を
  /// 組み合わせた結果を返す。
  /// - Parameters:
  ///   - query: 検索クエリ
  ///   - emojis: 検索対象の Emoji 配列
  /// - Returns: マッチした Emoji 配列（重複なし、元の順序を保持）
  public func search(query: String, in emojis: [Emoji]) -> [Emoji] {
    let q = query.trimmingCharacters(in: .whitespaces)
    guard !q.isEmpty else { return emojis }

    let keywordMatches = matchingEmojis(for: q)

    var seen: Set<String> = []
    var result: [Emoji] = []

    for emoji in emojis {
      let char = emoji.char
      guard !seen.contains(char) else { continue }

      // EmojiKit 標準の検索（Unicode名 + ローカライズ名）
      let standardMatch = emoji.matches(q)
      // キーワード辞書の検索
      let keywordMatch =
        keywordMatches.contains(char)
        || keywordMatches.contains(char.removingVariationSelectors())

      if standardMatch || keywordMatch {
        seen.insert(char)
        result.append(emoji)
      }
    }
    return result
  }
}

extension String {
  /// Variation Selector (U+FE0E, U+FE0F) を除去した文字列を返す。
  func removingVariationSelectors() -> String {
    unicodeScalars.filter { $0.value != 0xFE0E && $0.value != 0xFE0F }
      .map(String.init).joined()
  }
}
