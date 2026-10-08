import Foundation
import Testing

@testable import IgniteroCore

// MARK: - InfoPlist.strings の形式ごとの読み込み

/// 実アプリの `InfoPlist.strings` は UTF-8 テキストだけでなく、UTF-16（BOM 付き）の
/// テキストや、Xcode がコンパイルしたバイナリ plist の形でも配布される
/// （例: UTF-16 は Kindle / IINA、XML は cmux で確認）。どの形式でもローカライズ名を読めること。
@Suite("AppScanner InfoPlist.strings の形式")
struct AppScannerLocalizationFormatTests {

  private let strings = """
    /* ローカライズ名 */
    "CFBundleDisplayName" = "表示名テスト";
    "CFBundleName" = "名前テスト";
    """

  /// `<tmp>/<name>.app/Contents/Resources/ja.lproj/InfoPlist.strings` を書き出してアプリのパスを返す
  private func makeApp(writing write: (String) throws -> Void) throws -> (app: String, root: String)
  {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("ignitero-lproj-\(UUID().uuidString)").path
    let app = (root as NSString).appendingPathComponent("Sample.app")
    let lproj = (app as NSString).appendingPathComponent("Contents/Resources/ja.lproj")
    try FileManager.default.createDirectory(atPath: lproj, withIntermediateDirectories: true)
    try write((lproj as NSString).appendingPathComponent("InfoPlist.strings"))
    return (app, root)
  }

  @Test("UTF-16（BOM 付き）のテキストを読める")
  func readsUTF16WithBOM() throws {
    let (app, root) = try makeApp { path in
      try strings.write(toFile: path, atomically: true, encoding: .utf16)
    }
    defer { try? FileManager.default.removeItem(atPath: root) }

    #expect(AppScanner().localizedNameFromLproj(for: app, locale: "ja") == "表示名テスト")
  }

  @Test("バイナリ plist にコンパイルされた形式を読める")
  func readsBinaryPlist() throws {
    let (app, root) = try makeApp { path in
      let data = try PropertyListSerialization.data(
        fromPropertyList: ["CFBundleName": "バイナリ名"], format: .binary, options: 0)
      try data.write(to: URL(fileURLWithPath: path))
    }
    defer { try? FileManager.default.removeItem(atPath: root) }

    #expect(AppScanner().localizedNameFromLproj(for: app, locale: "ja") == "バイナリ名")
  }

  /// 別の行の構文が壊れていて plist として読めない場合も、目的のキーの行だけ拾う
  @Test("一部の行が壊れたテキストでも目的のキーを読める")
  func fallsBackToLineParsingWhenPlistParsingFails() throws {
    let broken = """
      "CFBundleDisplayName" = "壊れていても読める";
      "BrokenKey" = "閉じ引用符が無い;
      """
    let (app, root) = try makeApp { path in
      try broken.write(toFile: path, atomically: true, encoding: .utf8)
    }
    defer { try? FileManager.default.removeItem(atPath: root) }

    #expect(
      NSDictionary(contentsOfFile: app + "/Contents/Resources/ja.lproj/InfoPlist.strings") == nil)
    #expect(AppScanner().localizedNameFromLproj(for: app, locale: "ja") == "壊れていても読める")
  }

  @Test("指定ロケールの lproj が無ければ nil")
  func returnsNilWhenRequestedLocaleIsMissing() throws {
    let (app, root) = try makeApp { path in
      try strings.write(toFile: path, atomically: true, encoding: .utf8)
    }
    defer { try? FileManager.default.removeItem(atPath: root) }

    #expect(AppScanner().localizedNameFromLproj(for: app, locale: "fr") == nil)
  }
}
