import Foundation
import Synchronization

/// 選択履歴の1エントリ
public struct SelectionHistoryEntry: Codable, Sendable {
  public let keyword: String
  public let selectedPath: String
  public var count: Int
  public var lastUsed: Date

  public init(keyword: String, selectedPath: String, count: Int = 1, lastUsed: Date = Date()) {
    self.keyword = keyword
    self.selectedPath = selectedPath
    self.count = count
    self.lastUsed = lastUsed
  }
}

/// キーワード+パスによる選択履歴を管理する
///
/// ランチャーで選択された結果を記録し、次回以降の検索スコア調整に利用する。
/// エントリ数は最大 50 件に制限される。
public final class SelectionHistory: Sendable {
  private static let maxEntries = 50

  private let storage: Mutex<[SelectionHistoryEntry]>
  private let filePath: String

  public init(filePath: String) {
    self.filePath = filePath
    self.storage = Mutex([])
  }

  /// 全エントリを返す
  public var allEntries: [SelectionHistoryEntry] {
    storage.withLock { $0 }
  }

  /// キーワードとパスの組み合わせを記録する
  ///
  /// 同じキーワード+パスが既に存在する場合はカウントを増加し lastUsed を更新する。
  /// エントリ数が上限を超えた場合、lastUsed が最も古いエントリを削除する。
  public func record(keyword: String, path: String) {
    storage.withLock { entries in
      if let index = entries.firstIndex(where: { $0.keyword == keyword && $0.selectedPath == path })
      {
        entries[index].count += 1
        entries[index].lastUsed = Date()
      } else {
        let entry = SelectionHistoryEntry(keyword: keyword, selectedPath: path)
        entries.append(entry)
      }

      // 上限を超えたら最も古いエントリを削除
      if entries.count > SelectionHistory.maxEntries {
        if let oldestIndex = entries.indices.min(by: { entries[$0].lastUsed < entries[$1].lastUsed }
        ) {
          entries.remove(at: oldestIndex)
        }
      }
    }
  }

  /// 指定キーワードに該当するエントリをカウント降順で返す
  public func entries(for keyword: String) -> [SelectionHistoryEntry] {
    storage.withLock { entries in
      entries
        .filter { $0.keyword == keyword }
        .sorted { $0.count > $1.count }
    }
  }

  /// 現在のエントリを JSON ファイルに保存する
  public func save() throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(allEntries)
    try data.write(to: URL(fileURLWithPath: filePath), options: .atomic)
  }

  /// JSON ファイルからエントリを読み込む
  ///
  /// ファイルが存在しない場合は何もしない（空の状態を維持）。
  public func load() throws {
    let url = URL(fileURLWithPath: filePath)
    guard FileManager.default.fileExists(atPath: filePath) else { return }
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let loaded = try decoder.decode([SelectionHistoryEntry].self, from: data)
    storage.withLock { $0 = loaded }
  }
}
