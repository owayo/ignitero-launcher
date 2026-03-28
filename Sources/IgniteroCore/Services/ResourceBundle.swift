import Foundation

public enum ResourceBundle {
  /// SPM の `Bundle.module` は `.app` バンドル構造では正しいパスを解決できないため、
  /// `Bundle.main.resourceURL`（Contents/Resources/）も検索する。
  public static let bundle: Bundle = {
    let bundleName = "IgniteroLauncher_IgniteroCore.bundle"

    // .app/Contents/Resources/ 内を検索（macOS .app バンドル構造）
    if let resourceURL = Bundle.main.resourceURL,
      let bundle = Bundle(url: resourceURL.appendingPathComponent(bundleName))
    {
      return bundle
    }

    // SPM デフォルト: Bundle.main.bundleURL 直下（開発ビルド時）
    let mainPath = Bundle.main.bundleURL.appendingPathComponent(bundleName)
    if let bundle = Bundle(url: mainPath) {
      return bundle
    }

    // フォールバック: SPM 生成の Bundle.module
    return Bundle.module
  }()
}
