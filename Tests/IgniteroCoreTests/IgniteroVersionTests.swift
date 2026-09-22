import Foundation
import Testing

@testable import IgniteroCore

/// アプリケーションバージョンの解決。
///
/// バージョンの正本は `Resources/Info.plist` の `CFBundleShortVersionString` ただ 1 つ。
/// Swift 側にも定数を置いていた頃は、リリース CI が Info.plist だけを bump するため
/// 両者が食い違い、アップデート判定が「手元の方が新しい」と誤認して通知が出なくなっていた。
@Suite("アプリケーションバージョンの解決")
struct IgniteroVersionTests {

  /// `Info.plist` を持つ一時バンドルを作る。
  private static func makeBundle(plist: [String: Any]) throws -> (bundle: Bundle, root: URL) {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("ignitero-version-\(UUID().uuidString).bundle")
    let contents = root.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let data = try PropertyListSerialization.data(
      fromPropertyList: plist, format: .xml, options: 0)
    try data.write(to: contents.appendingPathComponent("Info.plist"))
    let bundle = try #require(Bundle(url: root), "一時バンドルを開けない")
    return (bundle, root)
  }

  @Test("Info.plist の CFBundleShortVersionString を返す")
  func readsVersionFromInfoPlist() throws {
    let (bundle, root) = try Self.makeBundle(plist: [
      "CFBundleIdentifier": "com.example.ignitero.test",
      "CFBundleShortVersionString": "26.9.3",
    ])
    defer { try? FileManager.default.removeItem(at: root) }

    #expect(Ignitero.resolveVersion(from: bundle) == "26.9.3")
  }

  @Test("キーが無ければ nil を返す")
  func returnsNilWhenKeyIsMissing() throws {
    let (bundle, root) = try Self.makeBundle(plist: [
      "CFBundleIdentifier": "com.example.ignitero.test"
    ])
    defer { try? FileManager.default.removeItem(at: root) }

    #expect(Ignitero.resolveVersion(from: bundle) == nil)
  }

  /// 空文字を返すと「バージョンは取得できたが空」という比較不能な値が
  /// アップデート判定へ流れるため、未設定と同じく nil に落とす。
  @Test("空文字や空白のみの値は nil として扱う")
  func treatsBlankVersionAsMissing() throws {
    for raw in ["", "   ", "\n"] {
      let (bundle, root) = try Self.makeBundle(plist: [
        "CFBundleIdentifier": "com.example.ignitero.test",
        "CFBundleShortVersionString": raw,
      ])
      defer { try? FileManager.default.removeItem(at: root) }

      #expect(Ignitero.resolveVersion(from: bundle) == nil, "'\(raw)' は nil になる")
    }
  }

  @Test("前後の空白は取り除く")
  func trimsSurroundingWhitespace() throws {
    let (bundle, root) = try Self.makeBundle(plist: [
      "CFBundleIdentifier": "com.example.ignitero.test",
      "CFBundleShortVersionString": " 26.9.3 ",
    ])
    defer { try? FileManager.default.removeItem(at: root) }

    #expect(Ignitero.resolveVersion(from: bundle) == "26.9.3")
  }
}
