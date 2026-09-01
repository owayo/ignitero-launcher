import Foundation
import os

/// 絵文字のローカライズ名テーブル。EmojiKit の `Emoji.localizedName(in:)` の代替。
///
/// EmojiKit 側の `Localizable.localizedName(in:)` はデフォルト引数で `Bundle.module`
/// を参照するため、`.app` 配置では `fatalError` で SIGTRAP する
/// （理由と実例は ``ResourceBundle`` のコメント参照）。ここでは
/// `EmojiKit_EmojiKit.bundle` を ``ResourceBundle`` 経由で自前解決し、
/// ロケール別の `Localizable.strings`（キー = 絵文字、値 = ローカライズ名、
/// 日本語は 1,885 件）を辞書として一度だけ読み込む。
///
/// バンドルやロケールを解決できなければ空辞書となり、ローカライズ名による一致判定
/// だけが無効化される。絵文字検索そのものは Unicode 名と
/// ``EmojiKeywordSearch`` のキーワード辞書で継続する。
///
/// 副産物として、EmojiKit の実装が絵文字 1 件ごとに `Bundle(path:)` と
/// `NSLocalizedString` を呼んでいたのに対し、こちらは辞書引き 1 回で済む。
public enum EmojiLocalizedNames {

  private static let logger = Logger(
    subsystem: "com.ignitero.launcher", category: "EmojiLocalizedNames")

  /// 絵文字 → 現在ロケールのローカライズ名。解決できない場合は空。
  ///
  /// 空になると絵文字検索からローカライズ名の一致が黙って消えるため、
  /// 初期化時（プロセスで 1 回）に warning を残す。
  public static let table: [String: String] = {
    let loaded = loadTable()
    if loaded.isEmpty {
      logger.warning(
        """
        EmojiKit のローカライズ名テーブルを読めなかった (locale: \(Locale.current.identifier, privacy: .public))。\
        絵文字検索は Unicode 名とキーワード辞書のみで継続する。\
        .app の Contents/Resources に EmojiKit_EmojiKit.bundle があるか確認する (make verify-bundle)。
        """)
    }
    return loaded
  }()

  /// 指定した絵文字のローカライズ名。テーブルに無ければ `nil`。
  public static func name(for char: String) -> String? {
    table[char]
  }

  // MARK: - ロード

  /// ロケール別 `Localizable.strings` を辞書として読み込む。
  ///
  /// - Parameters:
  ///   - bundle: EmojiKit のリソースバンドル。`nil` なら空辞書を返す。
  ///   - locale: 対象ロケール。
  static func loadTable(
    bundle: Bundle? = ResourceBundle.emojiKit,
    locale: Locale = .current
  ) -> [String: String] {
    guard let bundle else { return [:] }
    for name in localeCandidates(for: locale) {
      guard let path = bundle.path(forResource: name, ofType: "lproj"),
        let lproj = Bundle(path: path),
        let url = lproj.url(forResource: "Localizable", withExtension: "strings"),
        let dict = NSDictionary(contentsOf: url) as? [String: String]
      else { continue }
      return dict
    }
    return [:]
  }

  /// `.lproj` の探索順を返す。
  ///
  /// EmojiKit のバンドルは `ja.lproj` / `zh-hans.lproj` のように言語コード基準で
  /// 構成されているため、`ja_JP` のような完全な識別子で引けないケースを
  /// 言語コード単体でフォールバックする（EmojiKit `Bundle+Locale` と同じ順序）。
  static func localeCandidates(for locale: Locale) -> [String] {
    var candidates = [locale.identifier]
    if let language = locale.language.languageCode?.identifier,
      language != locale.identifier
    {
      candidates.append(language)
    }
    return candidates
  }
}
