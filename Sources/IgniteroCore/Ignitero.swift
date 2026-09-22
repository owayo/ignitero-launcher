import Foundation

/// Ignitero Launcher コアモジュール
public enum Ignitero: Sendable {

  /// アプリケーションのバージョン。`.app` として起動していない場合は `nil`。
  ///
  /// 正本は `Resources/Info.plist` の `CFBundleShortVersionString` ただ 1 つ。
  /// リリースワークフロー（`.github/workflows/release.yml`）が bump するのもここだけなので、
  /// Swift 側にも定数を置くと更新漏れで two-source-of-truth になる。
  /// 実際に `Ignitero.version = "27.0.0"` と Info.plist の `26.6.0` が食い違い、
  /// アップデート判定が「手元の方が新しい」と誤認して通知が出なくなっていた。
  ///
  /// 取得できないときに `"0.0.0"` や `"unknown"` へ潰さないのは、それらを
  /// バージョン比較へ渡すと「毎回更新通知が出る」「二度と出ない」のどちらかに
  /// 静かに倒れるため。不明は不明のまま表現し、呼び出し側が更新確認自体を諦める。
  public static let version: String? = resolveVersion(from: .main)

  /// 指定バンドルの `CFBundleShortVersionString` を読む。未設定・空文字なら `nil`。
  static func resolveVersion(from bundle: Bundle) -> String? {
    guard let raw = bundle.infoDictionary?["CFBundleShortVersionString"] as? String else {
      return nil
    }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
