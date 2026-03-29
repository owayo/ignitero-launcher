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

      // 上限を超えたら保持価値が最も低いエントリを削除
      // 保持スコア = lastUsed + log2(count+1) * 1日分（頻繁に使うほど猶予を与える）
      if entries.count > SelectionHistory.maxEntries {
        if let evictIndex = entries.indices.min(by: {
          Self.retentionScore(entries[$0]) < Self.retentionScore(entries[$1])
        }) {
          entries.remove(at: evictIndex)
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

  /// 存在しないパスの履歴エントリを削除する。
  ///
  /// キャッシュ読み込み後に呼び出して、削除済みアプリやディレクトリの履歴をクリーンアップする。
  /// 空パスのエントリ（カスタムコマンド等）は削除対象外。
  /// - Parameter validPaths: 有効なパスの集合
  public func purgeInvalidPaths(_ validPaths: Set<String>) {
    storage.withLock { entries in
      entries.removeAll { entry in
        !entry.selectedPath.isEmpty && !validPaths.contains(entry.selectedPath)
      }
    }
  }

  /// エントリの保持スコアを計算する（高いほど保持価値が高い）。
  ///
  /// 使用頻度が高いエントリほど「猶予期間」が長くなる（count の対数 × 1日）。
  private static func retentionScore(_ entry: SelectionHistoryEntry) -> Double {
    entry.lastUsed.timeIntervalSinceReferenceDate + log2(Double(entry.count) + 1) * 86400
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
