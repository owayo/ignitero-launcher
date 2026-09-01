import Foundation

/// SwiftPM が生成するリソースバンドルを `Bundle.module` を踏まずに解決する。
///
/// `Bundle.module` を `.app` 配置で使ってはいけない。SwiftPM が生成する
/// `resource_bundle_accessor.swift` の探索先は
///
/// 1. `Bundle.main.bundleURL` 直下（= `.app/` のルート、`Contents/` と同階層）
/// 2. ビルド時に焼き込まれた `.build/<triple>/<config>/` の絶対パス
///
/// の 2 つだけで、`.app/Contents/Resources` は候補に入らない。`.app` のルート直下へ
/// リソースを置くと `codesign` が "unsealed contents present in the bundle root" で
/// 拒否するため、`.app` では 1 を満たせない。つまり `Bundle.module` は
/// 「ビルドディレクトリがそのパスに残っている開発マシン」でしか解決できず、
/// `.build` を消すか他マシンへ配布した瞬間 `fatalError` で SIGTRAP する。
///
/// 実例（2026-09-01）: `.build` の生成物が消えた状態で絵文字検索を実行したところ
/// `EmojiKit/resource_bundle_accessor.swift:12: Fatal error: could not load resource
/// bundle` でアプリ全体がクラッシュした。`Bundle.module` は非 Optional なので
/// 呼び出し側で握ることもできない。
///
/// そのため解決は常にこのヘルパー経由で行い、失敗時は `nil` を返して
/// 呼び出し側が機能を縮退させる（fail-open）。
public enum ResourceBundle {

  /// IgniteroCore 自身のリソースバンドル（`emoji_keywords_ja.json` 等）。
  public static let bundle: Bundle? = resolve(named: "IgniteroLauncher_IgniteroCore.bundle")

  /// EmojiKit のリソースバンドル（絵文字のローカライズ名 `Localizable.strings`）。
  public static let emojiKit: Bundle? = resolve(named: "EmojiKit_EmojiKit.bundle")

  /// 指定名のリソースバンドルを解決する。見つからなければ `nil`。
  ///
  /// - `.app` 配置: `Contents/Resources/` 配下（`Makefile` の `bundle` が配置する）
  /// - 開発ビルド: 実行ファイルと同階層（`swift build` の出力ディレクトリ直下）
  static func resolve(named name: String) -> Bundle? {
    if let resourceURL = Bundle.main.resourceURL,
      let bundle = Bundle(url: resourceURL.appendingPathComponent(name))
    {
      return bundle
    }
    return Bundle(url: Bundle.main.bundleURL.appendingPathComponent(name))
  }
}
