import EmojiKit
import Foundation
import os

/// emojibase ベースの日本語絵文字キーワード検索。
///
/// バンドルリソース `emoji_keywords_ja.json` を読み込み、
/// 絵文字文字列 → キーワード配列のマッピングで検索を行う。
/// EmojiKit の `localizedName` 検索では対応できない
/// 「いいね」→ 👍 のような日本語キーワード検索を提供する。
public final class EmojiKeywordSearch: Sendable {

  private static let logger = Logger(
    subsystem: "com.ignitero.launcher", category: "EmojiKeywordSearch")

  /// emoji 文字列 → キーワード配列
  private let keywords: [String: [String]]

  public init() {
    guard
      let url = ResourceBundle.bundle?.url(forResource: "emoji_keywords_ja", withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let dict = try? JSONDecoder().decode([String: [String]].self, from: data)
    else {
      // 読めないとキーワード検索（「いいね」→ 👍 等）が黙って消えるため記録する。
      Self.logger.warning(
        """
        emoji_keywords_ja.json を読めなかった。絵文字検索は Unicode 名と\
        ローカライズ名のみで継続する。.app の Contents/Resources に\
        IgniteroLauncher_IgniteroCore.bundle があるか確認する (make verify-bundle)。
        """)
      self.keywords = [:]
      return
    }
    self.keywords = dict
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

      // 辞書引きで済むキーワード検索を先に判定し、真なら Unicode 名の
      // ICU 変換（`unicodeName`）をスキップする。
      let keywordMatch =
        keywordMatches.contains(char)
        || keywordMatches.contains(char.removingVariationSelectors())

      if keywordMatch || Self.standardMatches(emoji, query: q) {
        seen.insert(char)
        result.append(emoji)
      }
    }
    return result
  }

  /// EmojiKit `Emoji.matches(_:in:)` 相当の一致判定を、`Bundle.module` を
  /// 踏まずに行う。
  ///
  /// EmojiKit の実装は最後に `localizedName(in:)` を呼ぶが、これはデフォルト引数の
  /// `Bundle.module` を解決しに行き、`.app` 配置では `fatalError` で SIGTRAP して
  /// アプリ全体を落とす（実例と理由は ``ResourceBundle`` のコメント参照）。
  /// ローカライズ名は ``EmojiLocalizedNames`` の辞書から引き、辞書が空の場合は
  /// Unicode 名までの判定で縮退する。
  static func standardMatches(_ emoji: Emoji, query: String) -> Bool {
    if emoji.char == query { return true }
    if emoji.unicodeName.localizedCaseInsensitiveContains(query) { return true }
    guard let localizedName = EmojiLocalizedNames.name(for: emoji.char) else { return false }
    return localizedName.localizedCaseInsensitiveContains(query)
  }
}

extension String {
  /// Variation Selector (U+FE0E, U+FE0F) を除去した文字列を返す。
  func removingVariationSelectors() -> String {
    unicodeScalars.filter { $0.value != 0xFE0E && $0.value != 0xFE0F }
      .map(String.init).joined()
  }
}
