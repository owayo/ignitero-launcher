import Foundation
import Testing

@testable import IgniteroCore

@Suite("SelectionHistory Tests")
struct SelectionHistoryTests {

  /// テスト用の一時ファイルパスを生成
  private func makeTempFilePath() -> String {
    let dir = NSTemporaryDirectory()
    return (dir as NSString).appendingPathComponent("selection_history_\(UUID().uuidString).json")
  }

  /// 一時ファイルを削除
  private func cleanup(_ path: String) {
    try? FileManager.default.removeItem(atPath: path)
  }

  // MARK: - エントリの記録

  @Test("エントリを記録できる")
  func recordEntry() throws {
    let path = makeTempFilePath()
    defer { cleanup(path) }

    let history = SelectionHistory(filePath: path)
    history.record(keyword: "xcode", path: "/Applications/Xcode.app")

    let results = history.entries(for: "xcode")
    #expect(results.count == 1)
    #expect(results[0].keyword == "xcode")
    #expect(results[0].selectedPath == "/Applications/Xcode.app")
    #expect(results[0].count == 1)
  }

  // MARK: - 同じキーワード+パスでカウント増加

  @Test("同じキーワード+パスの記録でカウントが増加する")
  func recordDuplicateIncrementsCount() throws {
    let path = makeTempFilePath()
    defer { cleanup(path) }

    let history = SelectionHistory(filePath: path)
    history.record(keyword: "xcode", path: "/Applications/Xcode.app")
    history.record(keyword: "xcode", path: "/Applications/Xcode.app")
    history.record(keyword: "xcode", path: "/Applications/Xcode.app")

    let results = history.entries(for: "xcode")
    #expect(results.count == 1)
    #expect(results[0].count == 3)
  }

  // MARK: - 50件上限

  @Test("50件を超えると最も古いエントリが削除される")
  func maxEntriesLimit() throws {
    let path = makeTempFilePath()
    defer { cleanup(path) }

    let history = SelectionHistory(filePath: path)

    // 50件のユニークエントリを追加
    for i in 0..<50 {
      history.record(keyword: "key\(i)", path: "/path/\(i)")
    }
    #expect(history.allEntries.count == 50)

    // 51件目を追加 → 最も古い（key0）が削除される
    history.record(keyword: "key50", path: "/path/50")
    #expect(history.allEntries.count == 50)

    // key0 のエントリは消えている
    let oldEntries = history.entries(for: "key0")
    #expect(oldEntries.isEmpty)

    // key50 のエントリは存在する
    let newEntries = history.entries(for: "key50")
    #expect(newEntries.count == 1)
  }

  // MARK: - JSON 保存と読み込み

  @Test("JSON への保存と読み込み")
  func saveAndLoad() throws {
    let path = makeTempFilePath()
    defer { cleanup(path) }

    let history = SelectionHistory(filePath: path)
    history.record(keyword: "terminal", path: "/Applications/Terminal.app")
    history.record(keyword: "terminal", path: "/Applications/iTerm.app")
    history.record(keyword: "terminal", path: "/Applications/Terminal.app")
    try history.save()

    // 新しいインスタンスで読み込み
    let loaded = SelectionHistory(filePath: path)
    try loaded.load()

    let results = loaded.entries(for: "terminal")
    #expect(results.count == 2)

    // カウント順（降順）で返ることを確認
    let terminalEntry = results.first { $0.selectedPath == "/Applications/Terminal.app" }
    #expect(terminalEntry?.count == 2)

    let itermEntry = results.first { $0.selectedPath == "/Applications/iTerm.app" }
    #expect(itermEntry?.count == 1)
  }

  // MARK: - キーワードによる検索

  @Test("キーワードによる履歴検索")
  func entriesForKeyword() throws {
    let path = makeTempFilePath()
    defer { cleanup(path) }

    let history = SelectionHistory(filePath: path)
    history.record(keyword: "code", path: "/Applications/VSCode.app")
    history.record(keyword: "code", path: "/Applications/Xcode.app")
    history.record(keyword: "terminal", path: "/Applications/Terminal.app")

    let codeResults = history.entries(for: "code")
    #expect(codeResults.count == 2)

    let terminalResults = history.entries(for: "terminal")
    #expect(terminalResults.count == 1)

    let unknownResults = history.entries(for: "unknown")
    #expect(unknownResults.isEmpty)
  }

  // MARK: - 空の履歴

  @Test("空の履歴の扱い")
  func emptyHistory() throws {
    let path = makeTempFilePath()
    defer { cleanup(path) }

    let history = SelectionHistory(filePath: path)

    #expect(history.allEntries.isEmpty)
    #expect(history.entries(for: "anything").isEmpty)

    // 存在しないファイルからの load はエラーにならない
    try history.load()
    #expect(history.allEntries.isEmpty)
  }

  // MARK: - lastUsed の更新

  @Test("記録時に lastUsed が更新される")
  func lastUsedUpdatesOnRecord() throws {
    let path = makeTempFilePath()
    defer { cleanup(path) }

    let history = SelectionHistory(filePath: path)
    history.record(keyword: "test", path: "/path/test")

    let firstDate = history.entries(for: "test")[0].lastUsed

    // わずかな時間差を作る
    Thread.sleep(forTimeInterval: 0.01)

    history.record(keyword: "test", path: "/path/test")

    let secondDate = history.entries(for: "test")[0].lastUsed
    #expect(secondDate > firstDate)
  }

  // MARK: - ISO 8601 フォーマット

  @Test("JSON は ISO 8601 フォーマットで日付を保存する")
  func iso8601DateFormat() throws {
    let path = makeTempFilePath()
    defer { cleanup(path) }

    let history = SelectionHistory(filePath: path)
    history.record(keyword: "test", path: "/path/test")
    try history.save()

    // ファイルの中身を直接確認
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let jsonString = String(data: data, encoding: .utf8)!

    // ISO 8601 フォーマット（例: "2024-01-01T00:00:00Z"）のパターンを含む
    #expect(jsonString.contains("T"))
    #expect(jsonString.contains("Z") || jsonString.contains("+"))
  }

  // MARK: - 並行アクセス

  @Test("複数スレッドからの同時記録でクラッシュしない")
  func concurrentRecordDoesNotCrash() async throws {
    let path = makeTempFilePath()
    defer { cleanup(path) }

    let history = SelectionHistory(filePath: path)

    await withTaskGroup(of: Void.self) { group in
      for i in 0..<100 {
        group.addTask {
          history.record(keyword: "key\(i % 10)", path: "/path/\(i)")
        }
      }
    }

    // クラッシュせずに完了し、エントリ数が上限以内であること
    #expect(history.allEntries.count <= 50)
    #expect(history.allEntries.count > 0)
  }

  // MARK: - 既存エントリの再記録で lastUsed が古いエントリより新しくなる

  @Test("再記録したエントリは上限超過時に削除されない")
  func rerecordedEntryIsNotEvicted() throws {
    let path = makeTempFilePath()
    defer { cleanup(path) }

    let history = SelectionHistory(filePath: path)

    // 最初のエントリを記録
    history.record(keyword: "first", path: "/path/first")

    // 49件の他のエントリを追加
    for i in 1..<50 {
      history.record(keyword: "key\(i)", path: "/path/\(i)")
    }

    // 最初のエントリを再記録して lastUsed を更新
    history.record(keyword: "first", path: "/path/first")
    #expect(history.allEntries.count == 50)

    // 51件目を追加 → first ではなく他の古いエントリが削除される
    history.record(keyword: "new", path: "/path/new")
    #expect(history.allEntries.count == 50)

    // first は残っている（lastUsed が更新されたため）
    let firstEntries = history.entries(for: "first")
    #expect(firstEntries.count == 1)
    #expect(firstEntries[0].count == 2)
  }

  // MARK: - 破損した JSON の読み込み

  @Test("破損した JSON ファイルの読み込みはエラーを投げる")
  func loadCorruptedJsonThrows() throws {
    let path = makeTempFilePath()
    defer { cleanup(path) }

    // 不正な JSON を書き込む
    try "{ invalid json }".write(
      to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)

    let history = SelectionHistory(filePath: path)
    #expect(throws: (any Error).self) {
      try history.load()
    }
  }
}
