import Foundation
import Testing

@testable import IgniteroCore

// MARK: - クエリ正規化

@Suite("SearchService Query Normalization")
struct SearchServiceNormalizationTests {

  @Test func fullwidthToHalfwidth() {
    #expect(SearchQueryNormalizer.normalize("Ａｐｐｌｅ") == "apple")
  }

  @Test func halfwidthPassthrough() {
    #expect(SearchQueryNormalizer.normalize("safari") == "safari")
  }

  @Test func mixedFullwidthHalfwidth() {
    #expect(SearchQueryNormalizer.normalize("Ｖscode") == "vscode")
  }

  @Test func fullwidthNumbers() {
    #expect(SearchQueryNormalizer.normalize("１２３") == "123")
  }

  @Test func japanesePassthrough() {
    #expect(SearchQueryNormalizer.normalize("設定") == "設定")
  }

  @Test func emptyString() {
    #expect(SearchQueryNormalizer.normalize("") == "")
  }

  @Test func whitespaceTrim() {
    #expect(SearchQueryNormalizer.normalize("  safari  ") == "safari")
  }

  @Test func fullwidthSymbolsPassthrough() {
    // 全角記号は変換対象外（英数字のみ変換）
    #expect(SearchQueryNormalizer.normalize("＃タグ") == "＃タグ")
  }

  @Test func mixedFullwidthHalfwidthNumbers() {
    #expect(SearchQueryNormalizer.normalize("App１２３test") == "app123test")
  }

  @Test func fullwidthUppercaseLowered() {
    // 全角大文字 → 半角小文字に変換される
    #expect(SearchQueryNormalizer.normalize("ＡＰＰＬＥ") == "apple")
  }

  @Test func emojiPassthrough() {
    #expect(SearchQueryNormalizer.normalize("🔥fire") == "🔥fire")
  }
}

// MARK: - 検索結果

@Suite("SearchResult")
struct SearchResultTests {

  @Test func appResult() {
    let item = AppItem(name: "Safari", path: "/Applications/Safari.app")
    let result = SearchResult(appItem: item, score: 0.1)
    #expect(result.name == "Safari")
    #expect(result.path == "/Applications/Safari.app")
    #expect(result.kind == .app)
    #expect(result.score == 0.1)
  }

  @Test func directoryResult() {
    let item = DirectoryItem(name: "my-project", path: "/Users/test/my-project", editor: "cursor")
    let result = SearchResult(directoryItem: item, score: 0.2)
    #expect(result.name == "my-project")
    #expect(result.path == "/Users/test/my-project")
    #expect(result.kind == .directory)
    #expect(result.editor == "cursor")
  }

  @Test func commandResult() {
    let cmd = CustomCommand(alias: "deploy", command: "npm run deploy", workingDirectory: "/app")
    let result = SearchResult(customCommand: cmd, score: 0.0)
    #expect(result.name == "deploy")
    #expect(result.kind == .command)
    #expect(result.command == "npm run deploy")
    #expect(result.workingDirectory == "/app")
  }

  @Test func commandResultUsesHistoryIdentifier() throws {
    let commandID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
    let cmd = CustomCommand(
      id: commandID,
      alias: "deploy",
      command: "npm run deploy",
      workingDirectory: "/app"
    )
    let result = SearchResult(customCommand: cmd, score: 0.0)
    #expect(result.path == "command://11111111-1111-1111-1111-111111111111")
  }

  @Test func sortByScore() {
    let r1 = SearchResult(
      appItem: AppItem(name: "A", path: "/a"), score: 0.5)
    let r2 = SearchResult(
      appItem: AppItem(name: "B", path: "/b"), score: 0.1)
    let r3 = SearchResult(
      appItem: AppItem(name: "C", path: "/c"), score: 0.3)
    let sorted = [r1, r2, r3].sorted { $0.score < $1.score }
    #expect(sorted[0].name == "B")
    #expect(sorted[1].name == "C")
    #expect(sorted[2].name == "A")
  }
}

// MARK: - 基本検索

@Suite("SearchService Basic")
struct SearchServiceBasicTests {

  @Test func emptyQueryReturnsEmpty() async {
    let service = SearchService()
    let results = service.search(query: "", apps: [], directories: [], commands: [], history: [])
    #expect(results.isEmpty)
  }

  @Test func searchApps() async {
    let apps = [
      AppItem(name: "Safari", path: "/Applications/Safari.app"),
      AppItem(name: "Finder", path: "/System/Applications/Finder.app"),
      AppItem(name: "System Settings", path: "/System/Applications/System Settings.app"),
    ]
    let service = SearchService()
    let results = service.search(
      query: "safari", apps: apps, directories: [], commands: [], history: [])
    #expect(!results.isEmpty)
    #expect(results[0].name == "Safari")
  }

  @Test func searchDirectories() async {
    let dirs = [
      DirectoryItem(name: "my-project", path: "/Users/test/my-project", editor: "cursor"),
      DirectoryItem(name: "another-app", path: "/Users/test/another-app"),
    ]
    let service = SearchService()
    let results = service.search(
      query: "project", apps: [], directories: dirs, commands: [], history: [])
    #expect(!results.isEmpty)
    #expect(results[0].name == "my-project")
  }

  @Test func searchCommands() async {
    let cmds = [
      CustomCommand(alias: "deploy", command: "npm run deploy"),
      CustomCommand(alias: "test", command: "npm test"),
    ]
    let service = SearchService()
    let results = service.search(
      query: "deploy", apps: [], directories: [], commands: cmds, history: [])
    #expect(!results.isEmpty)
    #expect(results[0].name == "deploy")
  }

  @Test func maxResults() async {
    var apps: [AppItem] = []
    for i in 0..<30 {
      apps.append(AppItem(name: "App\(i)", path: "/Applications/App\(i).app"))
    }
    let service = SearchService()
    let results = service.search(
      query: "app", apps: apps, directories: [], commands: [], history: [])
    #expect(results.count <= 20)
  }
}

// MARK: - 元のアプリ名一致

@Suite("SearchService Original Name")
struct SearchServiceOriginalNameTests {

  @Test func matchesOriginalName() async {
    let apps = [
      AppItem(
        name: "システム設定", path: "/System/Applications/System Settings.app",
        originalName: "System Settings")
    ]
    let service = SearchService()
    let results = service.search(
      query: "system", apps: apps, directories: [], commands: [], history: [])
    #expect(!results.isEmpty)
    #expect(results[0].name == "システム設定")
  }
}

// MARK: - 全角クエリ

@Suite("SearchService Fullwidth")
struct SearchServiceFullwidthTests {

  @Test func fullwidthQueryMatchesApp() async {
    let apps = [
      AppItem(name: "Safari", path: "/Applications/Safari.app")
    ]
    let service = SearchService()
    let results = service.search(
      query: "Ｓａｆａｒｉ", apps: apps, directories: [], commands: [], history: [])
    #expect(!results.isEmpty)
    #expect(results[0].name == "Safari")
  }
}

// MARK: - 履歴ブースト

@Suite("SearchService History")
struct SearchServiceHistoryTests {

  @Test func historyBoostsResult() async {
    let apps = [
      AppItem(name: "Safari", path: "/Applications/Safari.app"),
      AppItem(name: "Safeguard", path: "/Applications/Safeguard.app"),
    ]
    let history = [
      SelectionHistoryEntry(
        keyword: "saf", selectedPath: "/Applications/Safeguard.app", count: 10)
    ]
    let service = SearchService()
    let resultsWithHistory = service.search(
      query: "saf", apps: apps, directories: [], commands: [], history: history)
    let resultsWithout = service.search(
      query: "saf", apps: apps, directories: [], commands: [], history: [])
    #expect(!resultsWithHistory.isEmpty)
    #expect(!resultsWithout.isEmpty)
    // 履歴がある場合は Safeguard が先頭に来る
    #expect(resultsWithHistory[0].path == "/Applications/Safeguard.app")
  }

  @Test func exactMatchHistoryPriority() async {
    let apps = [
      AppItem(name: "Safari", path: "/Applications/Safari.app"),
      AppItem(name: "Slack", path: "/Applications/Slack.app"),
    ]
    let history = [
      SelectionHistoryEntry(
        keyword: "sa", selectedPath: "/Applications/Safari.app", count: 10)
    ]
    let service = SearchService()
    let results = service.search(
      query: "sa", apps: apps, directories: [], commands: [], history: history)
    #expect(!results.isEmpty)
    #expect(results[0].path == "/Applications/Safari.app")
  }
}

// MARK: - 複合ケース

@Suite("SearchService Mixed")
struct SearchServiceMixedTests {

  @Test func searchWithOnlyOriginalNameMatch() async {
    let apps = [
      AppItem(
        name: "日本語名", path: "/Applications/EnglishApp.app",
        originalName: "EnglishApp")
    ]
    let service = SearchService()
    let results = service.search(
      query: "english", apps: apps, directories: [], commands: [], history: [])
    #expect(!results.isEmpty)
    #expect(results[0].name == "日本語名")
  }

  @Test func searchWhitespaceOnlyQueryReturnsEmpty() async {
    let apps = [
      AppItem(name: "Safari", path: "/Applications/Safari.app")
    ]
    let service = SearchService()
    let results = service.search(
      query: "   ", apps: apps, directories: [], commands: [], history: [])
    #expect(results.isEmpty)
  }

  @Test func searchSingleCharacterQuery() async {
    let apps = [
      AppItem(name: "Safari", path: "/Applications/Safari.app"),
      AppItem(name: "Slack", path: "/Applications/Slack.app"),
    ]
    let service = SearchService()
    let results = service.search(
      query: "s", apps: apps, directories: [], commands: [], history: [])
    #expect(!results.isEmpty)
  }

  @Test func historyBoostAllowsNegativeScoreForPriority() async {
    let apps = [
      AppItem(name: "Safari", path: "/Applications/Safari.app")
    ]
    let history = [
      SelectionHistoryEntry(
        keyword: "safari", selectedPath: "/Applications/Safari.app", count: 100)
    ]
    let service = SearchService()
    let results = service.search(
      query: "safari", apps: apps, directories: [], commands: [], history: history)
    #expect(!results.isEmpty)
    // 負のスコアは履歴ブーストによる意図的な設計
    #expect(results[0].score < 0.0)
  }

  @Test func prefixMatchHistoryBoost() async {
    let apps = [
      AppItem(name: "Safari", path: "/Applications/Safari.app"),
      AppItem(name: "Safeguard", path: "/Applications/Safeguard.app"),
    ]
    // "safari" の完全一致ではなく "saf" → "safari" の前方一致履歴
    let history = [
      SelectionHistoryEntry(
        keyword: "safari", selectedPath: "/Applications/Safeguard.app", count: 5)
    ]
    let service = SearchService()
    let results = service.search(
      query: "saf", apps: apps, directories: [], commands: [], history: history)
    #expect(!results.isEmpty)
    // 前方一致ブーストにより Safeguard が優先される
    #expect(results[0].path == "/Applications/Safeguard.app")
  }

  @Test func historyBoostIsCapped() async {
    let apps = [
      AppItem(name: "Safari", path: "/Applications/Safari.app")
    ]
    // 非常に大きい count でもブーストが際限なく増えないことを確認
    let history = [
      SelectionHistoryEntry(
        keyword: "safari", selectedPath: "/Applications/Safari.app", count: 10000)
    ]
    let service = SearchService()
    let results = service.search(
      query: "safari", apps: apps, directories: [], commands: [], history: history)
    #expect(!results.isEmpty)
    // 完全一致ブーストには上限がある
    #expect(results[0].score >= -2.0)
  }

  @Test func noHistoryBoostForDifferentPath() async {
    let apps = [
      AppItem(name: "Safari", path: "/Applications/Safari.app"),
      AppItem(name: "Slack", path: "/Applications/Slack.app"),
    ]
    // 異なるパスの履歴はブーストに影響しない
    let history = [
      SelectionHistoryEntry(
        keyword: "sa", selectedPath: "/Applications/NonExistent.app", count: 100)
    ]
    let service = SearchService()
    let resultsWithHistory = service.search(
      query: "sa", apps: apps, directories: [], commands: [], history: history)
    let resultsWithout = service.search(
      query: "sa", apps: apps, directories: [], commands: [], history: [])
    // 存在しないパスの履歴はマッチしないため、スコアに影響しない
    #expect(resultsWithHistory.count == resultsWithout.count)
    if !resultsWithHistory.isEmpty && !resultsWithout.isEmpty {
      #expect(resultsWithHistory[0].score == resultsWithout[0].score)
    }
  }

  @Test func emptyQueryWithHistoryReturnsRecentItems() async {
    let apps = [
      AppItem(name: "Safari", path: "/Applications/Safari.app"),
      AppItem(name: "Finder", path: "/System/Applications/Finder.app"),
      AppItem(name: "Xcode", path: "/Applications/Xcode.app"),
    ]
    let history = [
      SelectionHistoryEntry(
        keyword: "saf", selectedPath: "/Applications/Safari.app", count: 5),
      SelectionHistoryEntry(
        keyword: "xc", selectedPath: "/Applications/Xcode.app", count: 10),
    ]
    let service = SearchService()
    let results = service.search(
      query: "", apps: apps, directories: [], commands: [], history: history)
    // 履歴にあるアイテムのみが返される
    #expect(results.count == 2)
    // Xcode が count=10 で最優先
    #expect(results[0].path == "/Applications/Xcode.app")
    #expect(results[1].path == "/Applications/Safari.app")
  }

  @Test func emptyQueryWithSameCountUsesLastUsedOrder() async {
    let apps = [
      AppItem(name: "Safari", path: "/Applications/Safari.app"),
      AppItem(name: "Xcode", path: "/Applications/Xcode.app"),
    ]
    let history = [
      SelectionHistoryEntry(
        keyword: "saf",
        selectedPath: "/Applications/Safari.app",
        count: 3,
        lastUsed: Date(timeIntervalSince1970: 1_700_000_000)
      ),
      SelectionHistoryEntry(
        keyword: "xc",
        selectedPath: "/Applications/Xcode.app",
        count: 3,
        lastUsed: Date(timeIntervalSince1970: 1_700_000_600)
      ),
    ]
    let service = SearchService()
    let results = service.search(
      query: "", apps: apps, directories: [], commands: [], history: history)
    #expect(results.count == 2)
    #expect(results[0].path == "/Applications/Xcode.app")
    #expect(results[1].path == "/Applications/Safari.app")
  }

  @Test func emptyQueryWithCommandHistoryReturnsCommand() throws {
    let commandID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
    let command = CustomCommand(
      id: commandID,
      alias: "build",
      command: "make build",
      workingDirectory: "/project"
    )
    let history = [
      SelectionHistoryEntry(
        keyword: "build",
        selectedPath: command.historyIdentifier,
        count: 4,
        lastUsed: Date(timeIntervalSince1970: 1_700_000_000)
      )
    ]
    let service = SearchService()
    let results = service.search(
      query: "", apps: [], directories: [], commands: [command], history: history)
    #expect(results.count == 1)
    #expect(results[0].kind == .command)
    #expect(results[0].name == "build")
    #expect(results[0].path == command.historyIdentifier)
  }

  @Test func emptyQueryWithoutHistoryReturnsEmpty() async {
    let apps = [
      AppItem(name: "Safari", path: "/Applications/Safari.app")
    ]
    let service = SearchService()
    let results = service.search(
      query: "", apps: apps, directories: [], commands: [], history: [])
    #expect(results.isEmpty)
  }

  @Test func emptyQueryHistoryWithDeletedAppReturnsOnlyExisting() async {
    let apps = [
      AppItem(name: "Safari", path: "/Applications/Safari.app")
    ]
    let history = [
      SelectionHistoryEntry(
        keyword: "saf", selectedPath: "/Applications/Safari.app", count: 3),
      SelectionHistoryEntry(
        keyword: "old", selectedPath: "/Applications/DeletedApp.app", count: 10),
    ]
    let service = SearchService()
    let results = service.search(
      query: "", apps: apps, directories: [], commands: [], history: history)
    // 存在するアプリのみ返される
    #expect(results.count == 1)
    #expect(results[0].path == "/Applications/Safari.app")
  }

  @Test func mixedResultsSortedByScore() async {
    let apps = [
      AppItem(name: "Terminal", path: "/Applications/Utilities/Terminal.app")
    ]
    let dirs = [
      DirectoryItem(name: "terminal-app", path: "/Users/test/terminal-app")
    ]
    let cmds = [
      CustomCommand(alias: "terminal-check", command: "echo terminal")
    ]
    let service = SearchService()
    let results = service.search(
      query: "terminal", apps: apps, directories: dirs, commands: cmds, history: [])
    #expect(results.count >= 1)
  }
}

// MARK: - 履歴集約テスト

@Suite("SearchService History Aggregation")
struct SearchServiceHistoryAggregationTests {

  @Test func emptyQueryAggregatesDuplicatePathEntries() async {
    // 同一パスに対する複数の履歴エントリが正しく集約されることを確認
    let apps = [
      AppItem(name: "Safari", path: "/Applications/Safari.app"),
      AppItem(name: "Xcode", path: "/Applications/Xcode.app"),
    ]
    let history = [
      SelectionHistoryEntry(
        keyword: "saf",
        selectedPath: "/Applications/Safari.app",
        count: 3,
        lastUsed: Date(timeIntervalSince1970: 1_700_000_000)
      ),
      SelectionHistoryEntry(
        keyword: "safari",
        selectedPath: "/Applications/Safari.app",
        count: 5,
        lastUsed: Date(timeIntervalSince1970: 1_700_001_000)
      ),
      SelectionHistoryEntry(
        keyword: "xc",
        selectedPath: "/Applications/Xcode.app",
        count: 4,
        lastUsed: Date(timeIntervalSince1970: 1_700_000_500)
      ),
    ]
    let service = SearchService()
    let results = service.search(
      query: "", apps: apps, directories: [], commands: [], history: history)
    // Safari: count 3+5=8, Xcode: count 4 → Safari が優先
    #expect(results.count == 2)
    #expect(results[0].path == "/Applications/Safari.app")
    #expect(results[1].path == "/Applications/Xcode.app")
  }

  @Test func emptyQueryAggregatesLastUsedCorrectly() async {
    // 集約時に最新の lastUsed が採用されることを確認
    let apps = [
      AppItem(name: "Safari", path: "/Applications/Safari.app"),
      AppItem(name: "Xcode", path: "/Applications/Xcode.app"),
    ]
    let history = [
      SelectionHistoryEntry(
        keyword: "saf",
        selectedPath: "/Applications/Safari.app",
        count: 2,
        lastUsed: Date(timeIntervalSince1970: 1_700_000_000)
      ),
      SelectionHistoryEntry(
        keyword: "safari",
        selectedPath: "/Applications/Safari.app",
        count: 1,
        lastUsed: Date(timeIntervalSince1970: 1_700_002_000)
      ),
      SelectionHistoryEntry(
        keyword: "xc",
        selectedPath: "/Applications/Xcode.app",
        count: 3,
        lastUsed: Date(timeIntervalSince1970: 1_700_001_000)
      ),
    ]
    let service = SearchService()
    let results = service.search(
      query: "", apps: apps, directories: [], commands: [], history: history)
    // Safari: count=3, Xcode: count=3 → 同数なので lastUsed が新しい Safari が先
    #expect(results.count == 2)
    #expect(results[0].path == "/Applications/Safari.app")
    #expect(results[1].path == "/Applications/Xcode.app")
  }

  @Test func emptyQueryWithDirectoryHistory() async {
    // ディレクトリの履歴も正しく集約されることを確認
    let dirs = [
      DirectoryItem(name: "my-project", path: "/Users/test/my-project", editor: "cursor")
    ]
    let history = [
      SelectionHistoryEntry(
        keyword: "my",
        selectedPath: "/Users/test/my-project",
        count: 2,
        lastUsed: Date(timeIntervalSince1970: 1_700_000_000)
      ),
      SelectionHistoryEntry(
        keyword: "proj",
        selectedPath: "/Users/test/my-project",
        count: 3,
        lastUsed: Date(timeIntervalSince1970: 1_700_001_000)
      ),
    ]
    let service = SearchService()
    let results = service.search(
      query: "", apps: [], directories: dirs, commands: [], history: history)
    #expect(results.count == 1)
    #expect(results[0].kind == .directory)
    #expect(results[0].path == "/Users/test/my-project")
  }

  @Test func emptyQueryNameFallbackSortForSameScoreAndDate() async {
    // count と lastUsed が同一の場合、名前のアルファベット順でソートされることを確認
    let apps = [
      AppItem(name: "Zulu", path: "/Applications/Zulu.app"),
      AppItem(name: "Alpha", path: "/Applications/Alpha.app"),
    ]
    let sameDate = Date(timeIntervalSince1970: 1_700_000_000)
    let history = [
      SelectionHistoryEntry(
        keyword: "z", selectedPath: "/Applications/Zulu.app",
        count: 1, lastUsed: sameDate),
      SelectionHistoryEntry(
        keyword: "a", selectedPath: "/Applications/Alpha.app",
        count: 1, lastUsed: sameDate),
    ]
    let service = SearchService()
    let results = service.search(
      query: "", apps: apps, directories: [], commands: [], history: history)
    #expect(results.count == 2)
    // 名前順で Alpha が先
    #expect(results[0].name == "Alpha")
    #expect(results[1].name == "Zulu")
  }
}
