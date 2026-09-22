import Foundation

/// 設定画面のディレクトリ選択で使うパス解決ヘルパー。
enum DirectoryPathResolver {

  /// 指定 URL から遡って、実在する最も近い祖先ディレクトリを返す。見つからなければ `nil`。
  ///
  /// `URL.deletingLastPathComponent()` は `..` を解決しない。そのため
  /// `/nonexistent/../foo` のように「実在しない要素 + `..`」を含むパスでは
  /// `/nonexistent/..` が不動点になり、素朴な `while` ループが永久に回る。
  /// この処理は `NSOpenPanel` を開くボタンから同期実行されるため、
  /// ループに入るとメインスレッドごと固まり強制終了しか手段がなくなる。
  ///
  /// 先に `..` を畳んだうえで、遡上が進まなくなったら打ち切ることで停止性を保証する。
  static func existingAncestor(of url: URL) -> URL? {
    var current = url.standardizedFileURL.deletingLastPathComponent()
    while current.path != "/" {
      if FileManager.default.fileExists(atPath: current.path) {
        return current
      }
      let parent = current.deletingLastPathComponent().standardizedFileURL
      // 遡上が進まない（不動点）ならこれ以上辿れない。
      guard parent.path != current.path else { return nil }
      current = parent
    }
    return FileManager.default.fileExists(atPath: "/") ? URL(fileURLWithPath: "/") : nil
  }
}
