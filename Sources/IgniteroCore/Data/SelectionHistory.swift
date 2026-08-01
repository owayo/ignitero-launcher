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
  /// エントリ数が上限を超えた場合、保持価値が最も低い「既存の」エントリを削除する。
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
      //
      // 退避候補から末尾（＝いま append した新規エントリ）を必ず除外する。
      // 新規エントリのスコアは `now + log2(2)*86400` で固定だが、count が 2 以上の
      // 既存エントリは `lastUsed + log2(3)*86400` 以上になるため、上限に達した
      // 履歴がすべて「count>=2 かつ直近約14時間以内に使用」だと新規エントリが
      // 最小スコアになり、追加した直後に自分自身が削除されてしまう。
      // その状態では履歴が恒久的に更新されなくなる。
      if entries.count > SelectionHistory.maxEntries {
        let existingIndices = entries.indices.dropLast()
        if let evictIndex = existingIndices.min(by: {
          Self.retentionScore(entries[$0]) < Self.retentionScore(entries[$1])
        }) {
          entries.remove(at: evictIndex)
        } else {
          // 既存エントリが無い（maxEntries が 0）ケースの保険
          entries.removeLast()
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

  /// 存在しないパス・識別子の履歴エントリを削除する（allowlist 方式）。
  ///
  /// キャッシュ読み込み後に呼び出して、削除済みアプリ、ディレクトリ、カスタムコマンドの履歴をクリーンアップする。
  /// `validPaths` は現在復元可能なアプリ・ディレクトリのパスとカスタムコマンド識別子（`command://UUID`）の集合。
  /// 空パスや Web 検索 URL のように検索結果へ復元できない履歴も削除する
  /// （これらは履歴ブースト・最近使った項目で何にもマッチせず、エントリ枠だけを消費するため）。
  /// - Parameter validPaths: 有効なパス・識別子の集合
  public func purgeInvalidPaths(_ validPaths: Set<String>) {
    storage.withLock { entries in
      entries.removeAll { entry in
        entry.selectedPath.isEmpty || !validPaths.contains(entry.selectedPath)
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
    var loaded = try decoder.decode([SelectionHistoryEntry].self, from: data)
    // ファイルが maxEntries を超えている場合（手動編集・旧バージョン等）は切り詰める
    if loaded.count > Self.maxEntries {
      loaded.sort { Self.retentionScore($0) > Self.retentionScore($1) }
      loaded = Array(loaded.prefix(Self.maxEntries))
    }
    storage.withLock { $0 = loaded }
  }
}
