import Foundation
import Fuse

// MARK: - SearchQueryNormalizer

/// 全角英数字を半角に正規化するユーティリティ
public enum SearchQueryNormalizer: Sendable {
  /// 全角英数字を半角に変換し、前後の空白を除去して小文字化する
  public static func normalize(_ query: String) -> String {
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return "" }

    var result = ""
    result.reserveCapacity(trimmed.count)

    for scalar in trimmed.unicodeScalars {
      // 全角英数字 (Ａ-Ｚ: U+FF21-FF3A, ａ-ｚ: U+FF41-FF5A, ０-９: U+FF10-FF19)
      if scalar.value >= 0xFF21, scalar.value <= 0xFF3A {
        // 全角大文字 → 半角小文字
        result.append(Character(UnicodeScalar(scalar.value - 0xFF21 + 0x41)!))
      } else if scalar.value >= 0xFF41, scalar.value <= 0xFF5A {
        // 全角小文字 → 半角小文字
        result.append(Character(UnicodeScalar(scalar.value - 0xFF41 + 0x61)!))
      } else if scalar.value >= 0xFF10, scalar.value <= 0xFF19 {
        // 全角数字 → 半角数字
        result.append(Character(UnicodeScalar(scalar.value - 0xFF10 + 0x30)!))
      } else {
        result.append(Character(scalar))
      }
    }

    return result.lowercased()
  }
}

// MARK: - SearchResult

/// 検索結果の種別
public enum SearchResultKind: Sendable {
  case app
  case directory
  case command
  case webSearch
  case colorPicker
  case emoji
}

/// 統一された検索結果
public struct SearchResult: Sendable {
  public let name: String
  public let path: String
  public let kind: SearchResultKind
  public var score: Double
  public let iconPath: String?
  public let originalName: String?
  public let editor: String?
  public let command: String?
  public let workingDirectory: String?

  public init(appItem: AppItem, score: Double) {
    self.name = appItem.name
    self.path = appItem.path
    self.kind = .app
    self.score = score
    self.iconPath = appItem.iconPath
    self.originalName = appItem.originalName
    self.editor = nil
    self.command = nil
    self.workingDirectory = nil
  }

  public init(directoryItem: DirectoryItem, score: Double) {
    self.name = directoryItem.name
    self.path = directoryItem.path
    self.kind = .directory
    self.score = score
    self.iconPath = nil
    self.originalName = nil
    self.editor = directoryItem.editor
    self.command = nil
    self.workingDirectory = nil
  }

  public init(customCommand: CustomCommand, score: Double) {
    self.name = customCommand.alias
    self.path = ""
    self.kind = .command
    self.score = score
    self.iconPath = nil
    self.originalName = nil
    self.editor = nil
    self.command = customCommand.command
    self.workingDirectory = customCommand.workingDirectory
  }

  public init(name: String, kind: SearchResultKind, score: Double, path: String = "") {
    self.name = name
    self.path = path
    self.kind = kind
    self.score = score
    self.iconPath = nil
    self.originalName = nil
    self.editor = nil
    self.command = nil
    self.workingDirectory = nil
  }
}

// MARK: - SearchService

/// ファジー検索サービス
///
/// アプリケーション、ディレクトリ、カスタムコマンドを Fuse-Swift で並列ファジー検索し、
/// スコア順にマージして上位20件を返す。選択履歴による優先度調整も行う。
public struct SearchService: Sendable {
  private static let maxResults = 20

  public init() {}

  /// 統合検索を実行する
  ///
  /// - Parameters:
  ///   - query: 検索クエリ（全角英数字は自動で半角に正規化される）
  ///   - apps: アプリケーション一覧
  ///   - directories: ディレクトリ一覧
  ///   - commands: カスタムコマンド一覧
  ///   - history: 選択履歴エントリ
  /// - Returns: スコア順にソートされた検索結果（最大20件）
  public func search(
    query: String,
    apps: [AppItem],
    directories: [DirectoryItem],
    commands: [CustomCommand],
    history: [SelectionHistoryEntry]
  ) -> [SearchResult] {
    let normalized = SearchQueryNormalizer.normalize(query)
    guard !normalized.isEmpty else { return [] }

    let fuse = Fuse(threshold: 0.4)

    var results: [SearchResult] = []

    // アプリケーション検索
    for app in apps {
      let nameScore = fuseScore(fuse: fuse, pattern: normalized, text: app.name)
      let originalScore: Double? =
        if let original = app.originalName {
          fuseScore(fuse: fuse, pattern: normalized, text: original)
        } else {
          nil
        }

      let bestScore = min(nameScore ?? 1.0, originalScore ?? 1.0)
      if bestScore < 1.0 {
        results.append(SearchResult(appItem: app, score: bestScore))
      }
    }

    // ディレクトリ検索
    for dir in directories {
      if let score = fuseScore(fuse: fuse, pattern: normalized, text: dir.name), score < 1.0 {
        results.append(SearchResult(directoryItem: dir, score: score))
      }
    }

    // カスタムコマンド検索
    for cmd in commands {
      if let score = fuseScore(fuse: fuse, pattern: normalized, text: cmd.alias), score < 1.0 {
        results.append(SearchResult(customCommand: cmd, score: score))
      }
    }

    // 選択履歴による優先度調整
    applyHistoryBoost(results: &results, query: normalized, history: history)

    // スコア順にソートし上位20件を返す
    results.sort { $0.score < $1.score }
    return Array(results.prefix(Self.maxResults))
  }

  // MARK: - Private

  private func fuseScore(fuse: Fuse, pattern: String, text: String) -> Double? {
    fuse.search(pattern, in: text.lowercased())?.score
  }

  private func applyHistoryBoost(
    results: inout [SearchResult],
    query: String,
    history: [SelectionHistoryEntry]
  ) {
    guard !history.isEmpty else { return }

    for i in results.indices {
      let path = results[i].path

      // 完全一致の履歴エントリ
      if let exactEntry = history.first(where: {
        $0.keyword == query && $0.selectedPath == path
      }) {
        // 完全一致は最高優先度: スコアを大幅に下げる（負のスコアを許可）
        results[i].score -= 1.0 + Double(exactEntry.count) * 0.01
      } else if let prefixEntry = history.first(where: {
        $0.keyword.hasPrefix(query) && $0.selectedPath == path
      }) {
        // 前方一致は中程度の優先度
        results[i].score -= 0.5 + Double(prefixEntry.count) * 0.005
      }
    }
  }
}
