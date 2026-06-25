import EmojiKit
import Foundation

/// `EmojiCategory.localizedName` の代替として、`Bundle.module` を一切踏まず
/// にカテゴリ表示名を返すユーティリティ。
///
/// EmojiKit の `Localizable.localizedName` はデフォルト引数で `Bundle.module`
/// を参照しており、SwiftPM のリソースバンドルを `.app` 配置で解決できないと
/// `assertionFailure` で SIGTRAP し、UI 評価が始まった瞬間にアプリ全体を
/// クラッシュさせる（`KeyboardShortcuts.Shortcut.description` と同型の罠）。
///
/// このヘルパーは標準カテゴリ・persisted カテゴリの ID から日本語/英語の
/// 表示名を直接返すため、Bundle.module の遅延初期化を一切起動しない。
public enum EmojiCategoryDisplayName {

  /// 日本語ロケールかどうか。`Locale.current` の言語コード先頭判定で、
  /// ja, ja-JP, ja_JP_POSIX 等のいずれもカバーする。
  static var isJapaneseLocale: Bool {
    let identifier = Locale.current.identifier
    return identifier.lowercased().hasPrefix("ja")
  }

  /// `EmojiCategory` から表示名を取得する。
  public static func text(for category: EmojiCategory) -> String {
    if case .custom(_, let name, _, _) = category, let name, !name.isEmpty {
      // カスタムカテゴリで明示的に name が指定されていればそれを優先する。
      // `.persisted(.frequent)` 等は name=nil で来るため id ベースで解決する。
      return name
    }
    return text(forId: category.id)
  }

  /// カテゴリ ID から表示名を取得する。未知の ID は ID をそのまま返す。
  public static func text(forId id: String) -> String {
    let table = isJapaneseLocale ? jaTable : enTable
    return table[id] ?? id
  }

  // MARK: - Tables

  /// 標準 + persisted カテゴリの日本語表示名。
  /// EmojiKit `ja.lproj/Localizable.strings` から借用しているため
  /// EmojiKit 側で文言が変わった際にこちらも追従する。
  static let jaTable: [String: String] = [
    "smileysAndPeople": "笑顔と人",
    "animalsAndNature": "動物と自然",
    "foodAndDrink": "食べ物と飲み物",
    "activity": "活動",
    "travelAndPlaces": "旅行と場所",
    "objects": "物",
    "symbols": "記号",
    "flags": "旗",
    "favorites": "お気に入り",
    "frequent": "よく使う項目",
    "recent": "最近使用した項目",
    "search": "検索結果",
  ]

  /// 標準 + persisted カテゴリの英語表示名。
  static let enTable: [String: String] = [
    "smileysAndPeople": "Smileys & People",
    "animalsAndNature": "Animals & Nature",
    "foodAndDrink": "Food & Drink",
    "activity": "Activity",
    "travelAndPlaces": "Travel & Places",
    "objects": "Objects",
    "symbols": "Symbols",
    "flags": "Flags",
    "favorites": "Favorites",
    "frequent": "Frequently Used",
    "recent": "Recently Used",
    "search": "Search Results",
  ]
}
