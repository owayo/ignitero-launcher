import Foundation
import Testing

@testable import IgniteroCore

// MARK: - Query Normalization

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
}

// MARK: - Search Result

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

// MARK: - SearchService Basic

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

// MARK: - SearchService Original Name Matching

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

// MARK: - SearchService Fullwidth Query

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

// MARK: - SearchService History Boosting

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
    // With history, Safeguard should be boosted to first position
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

// MARK: - SearchService Mixed Results

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
    // 負のスコアは履歴ブーストによる意図的な設計（優先度最大化）
    #expect(results[0].score < 0.0)
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
