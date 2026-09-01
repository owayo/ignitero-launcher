import Carbon.HIToolbox
import EmojiKit
import Foundation
import KeyboardShortcuts

/// `.app` としてパッケージされた状態でリソース解決が成立しているかを検証する自己診断。
///
/// `Bundle.module` は `.app` では解決できない（理由は ``ResourceBundle`` のコメント参照）。
/// にもかかわらず開発マシンではビルドディレクトリの絶対パスで偶然解決できてしまうため、
/// この種の破損は「`.build` を消したときと配布物でだけクラッシュする」という形で現れる。
/// ユニットテストは SwiftPM の環境で走るので再現できない。
///
/// そこで `.app` を実際に起動し、ビルドディレクトリのリソースバンドルを退避した状態で
/// 検証する（`make smoke-resources`）。過去にクラッシュした経路（絵文字検索・
/// ショートカット表示・絵文字カテゴリ名）をすべて通す。
@MainActor
public enum ResourceSelfTest {

  /// 検証を実行し、すべて成功したら `true` を返す。結果は標準出力へ書く。
  ///
  /// `ShortcutDisplayFormatter` が MainActor 隔離のため全体を MainActor で実行する。
  public static func run() -> Bool {
    var failures: [String] = []

    func check(_ name: String, _ body: () -> String?) {
      if let reason = body() {
        failures.append(name)
        print("FAIL: \(name) — \(reason)")
      } else {
        print("ok  : \(name)")
      }
    }

    check("EmojiKit のリソースバンドルを解決できる") {
      ResourceBundle.emojiKit == nil ? "ResourceBundle.emojiKit が nil" : nil
    }

    check("IgniteroCore のリソースバンドルを解決できる") {
      ResourceBundle.bundle == nil ? "ResourceBundle.bundle が nil" : nil
    }

    check("絵文字のローカライズ名テーブルを読める") {
      EmojiLocalizedNames.table.isEmpty ? "テーブルが空" : nil
    }

    check("絵文字キーワード辞書を読める") {
      EmojiKeywordSearch().matchingEmojis(for: "いいね").isEmpty
        ? "「いいね」に一致する絵文字が無い" : nil
    }

    check("全絵文字を Bundle.module を踏まずに走査できる") {
      // 2026-09-01 にここで SIGTRAP した（EmojiKit の Emoji.matches 経由）。
      EmojiKeywordSearch().search(query: "face", in: Emoji.all).isEmpty ? "検索結果が空" : nil
    }

    check("ショートカット表示文字列を生成できる") {
      // Option+Space。KeyboardShortcuts の description は Bundle.module を踏んで落ちる。
      let shortcut = KeyboardShortcuts.Shortcut(
        carbonKeyCode: kVK_Space, carbonModifiers: optionKey)
      return ShortcutDisplayFormatter.string(for: shortcut).isEmpty ? "表示文字列が空" : nil
    }

    check("絵文字カテゴリの表示名を取得できる") {
      let categories: [EmojiCategory] = .standardGrid
      for category in categories where EmojiCategoryDisplayName.text(for: category).isEmpty {
        return "表示名が空: \(category.id)"
      }
      return categories.isEmpty ? "カテゴリが空" : nil
    }

    if failures.isEmpty {
      print("--- resource self-test: すべて成功 ---")
      return true
    }
    print("--- resource self-test: \(failures.count) 件失敗 ---")
    return false
  }
}
