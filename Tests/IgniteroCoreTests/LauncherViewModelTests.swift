import AppKit
import Foundation
import Testing

@testable import IgniteroCore

// MARK: - LauncherViewModel 初期状態

@Suite("LauncherViewModel Initial State")
struct LauncherViewModelInitialStateTests {

  @MainActor
  @Test func initialSearchQueryIsEmpty() {
    let vm = LauncherViewModel()
    #expect(vm.searchQuery == "")
  }

  @MainActor
  @Test func initialSearchResultsIsEmpty() {
    let vm = LauncherViewModel()
    #expect(vm.searchResults.isEmpty)
  }

  @MainActor
  @Test func initialSelectedIndexIsZero() {
    let vm = LauncherViewModel()
    #expect(vm.selectedIndex == 0)
  }

  @MainActor
  @Test func initialCalculatorResultIsNil() {
    let vm = LauncherViewModel()
    #expect(vm.calculatorResult == nil)
  }

  @MainActor
  @Test func initialUpdateBannerVersionIsNil() {
    let vm = LauncherViewModel()
    #expect(vm.updateBannerVersion == nil)
  }

  @MainActor
  @Test func initialIsUpdateBannerDismissedIsFalse() {
    let vm = LauncherViewModel()
    #expect(vm.isUpdateBannerDismissed == false)
  }
}

// MARK: - LauncherViewModel 検索

@Suite("LauncherViewModel Search")
struct LauncherViewModelSearchTests {

  @MainActor
  @Test func emptyQueryProducesEmptyResults() {
    let vm = LauncherViewModel()
    vm.apps = [AppItem(name: "Safari", path: "/Applications/Safari.app")]
    vm.searchQuery = ""
    vm.updateSearch()
    #expect(vm.searchResults.isEmpty)
  }

  @MainActor
  @Test func searchQueryTriggersResults() {
    let vm = LauncherViewModel()
    vm.apps = [
      AppItem(name: "Safari", path: "/Applications/Safari.app"),
      AppItem(name: "Finder", path: "/System/Applications/Finder.app"),
    ]
    vm.searchQuery = "safari"
    vm.updateSearch()
    #expect(!vm.searchResults.isEmpty)
    #expect(vm.searchResults[0].name == "Safari")
  }

  @MainActor
  @Test func searchQueryResetsSelectedIndex() {
    let vm = LauncherViewModel()
    vm.apps = [
      AppItem(name: "Safari", path: "/Applications/Safari.app"),
      AppItem(name: "Finder", path: "/System/Applications/Finder.app"),
    ]
    vm.searchQuery = "safari"
    vm.updateSearch()
    vm.moveSelectionDown()
    // クエリ変更時に selectedIndex がリセットされることを確認する。
    vm.searchQuery = "finder"
    vm.updateSearch()
    #expect(vm.selectedIndex == 0)
  }

  @MainActor
  @Test func searchDirectories() {
    let vm = LauncherViewModel()
    vm.directories = [
      DirectoryItem(name: "my-project", path: "/Users/test/my-project", editor: "cursor")
    ]
    vm.searchQuery = "project"
    vm.updateSearch()
    #expect(!vm.searchResults.isEmpty)
    #expect(vm.searchResults[0].kind == .directory)
  }

  @MainActor
  @Test func searchCommands() {
    let vm = LauncherViewModel()
    vm.commands = [
      CustomCommand(alias: "deploy", command: "npm run deploy")
    ]
    vm.searchQuery = "deploy"
    vm.updateSearch()
    #expect(!vm.searchResults.isEmpty)
    #expect(vm.searchResults[0].kind == .command)
  }
}

// MARK: - LauncherViewModel 計算機

@Suite("LauncherViewModel Calculator")
struct LauncherViewModelCalculatorTests {

  @MainActor
  @Test func calculatorExpressionDetected() {
    let vm = LauncherViewModel()
    vm.searchQuery = "1+2"
    vm.updateSearch()
    #expect(vm.calculatorResult != nil)
    #expect(vm.calculatorResult == "3")
  }

  @MainActor
  @Test func calculatorComplexExpression() {
    let vm = LauncherViewModel()
    vm.searchQuery = "10 * 5 + 3"
    vm.updateSearch()
    #expect(vm.calculatorResult != nil)
    #expect(vm.calculatorResult == "53")
  }

  @MainActor
  @Test func calculatorDecimalResult() {
    let vm = LauncherViewModel()
    vm.searchQuery = "10 / 3"
    vm.updateSearch()
    #expect(vm.calculatorResult != nil)
    // 小数表現の結果になることを確認する。
    #expect(vm.calculatorResult?.contains("3.3") == true)
  }

  @MainActor
  @Test func nonCalculatorExpressionReturnsNil() {
    let vm = LauncherViewModel()
    vm.searchQuery = "safari"
    vm.updateSearch()
    #expect(vm.calculatorResult == nil)
  }

  @MainActor
  @Test func singleNumberIsNotCalculatorExpression() {
    let vm = LauncherViewModel()
    vm.searchQuery = "42"
    vm.updateSearch()
    // 演算対象がないため、演算子を含まない単一数値は計算式として扱わない。
    #expect(vm.calculatorResult == nil)
  }
}

// MARK: - LauncherViewModel 選択移動

@Suite("LauncherViewModel Selection Navigation")
struct LauncherViewModelSelectionTests {

  @MainActor
  @Test func moveSelectionDownIncrementsIndex() {
    let vm = LauncherViewModel()
    vm.apps = [
      AppItem(name: "App Alpha", path: "/Applications/AppAlpha.app"),
      AppItem(name: "App Beta", path: "/Applications/AppBeta.app"),
      AppItem(name: "App Gamma", path: "/Applications/AppGamma.app"),
    ]
    vm.searchQuery = "app"
    vm.updateSearch()
    // 移動対象の検索結果があることを確認する。
    guard vm.searchResults.count >= 2 else {
      Issue.record("Expected at least 2 results but got \(vm.searchResults.count)")
      return
    }
    #expect(vm.selectedIndex == 0)
    vm.moveSelectionDown()
    #expect(vm.selectedIndex == 1)
  }

  @MainActor
  @Test func moveSelectionUpDecrementsIndex() {
    let vm = LauncherViewModel()
    vm.apps = [
      AppItem(name: "App Alpha", path: "/Applications/AppAlpha.app"),
      AppItem(name: "App Beta", path: "/Applications/AppBeta.app"),
      AppItem(name: "App Gamma", path: "/Applications/AppGamma.app"),
    ]
    vm.searchQuery = "app"
    vm.updateSearch()
    guard vm.searchResults.count >= 2 else {
      Issue.record("Expected at least 2 results but got \(vm.searchResults.count)")
      return
    }
    vm.moveSelectionDown()
    #expect(vm.selectedIndex == 1)
    vm.moveSelectionUp()
    #expect(vm.selectedIndex == 0)
  }

  @MainActor
  @Test func moveSelectionUpAtZeroStaysAtZero() {
    let vm = LauncherViewModel()
    vm.apps = [
      AppItem(name: "Safari", path: "/Applications/Safari.app")
    ]
    vm.searchQuery = "safari"
    vm.updateSearch()
    #expect(vm.selectedIndex == 0)
    vm.moveSelectionUp()
    #expect(vm.selectedIndex == 0)
  }

  @MainActor
  @Test func moveSelectionDownAtLastStaysAtLast() {
    let vm = LauncherViewModel()
    vm.apps = [
      AppItem(name: "Safari", path: "/Applications/Safari.app")
    ]
    vm.searchQuery = "safari"
    vm.updateSearch()
    guard vm.searchResults.count == 1 else {
      Issue.record("Expected exactly 1 result")
      return
    }
    vm.moveSelectionDown()
    #expect(vm.selectedIndex == 0)
  }

  @MainActor
  @Test func moveSelectionDownWithEmptyResultsStaysAtZero() {
    let vm = LauncherViewModel()
    vm.searchQuery = ""
    vm.updateSearch()
    vm.moveSelectionDown()
    #expect(vm.selectedIndex == 0)
  }

  @MainActor
  @Test func moveSelectionUpWithEmptyResultsStaysAtZero() {
    let vm = LauncherViewModel()
    vm.searchQuery = ""
    vm.updateSearch()
    vm.moveSelectionUp()
    #expect(vm.selectedIndex == 0)
  }
}

// MARK: - LauncherViewModel 選択確定

@Suite("LauncherViewModel Confirm Selection")
struct LauncherViewModelConfirmSelectionTests {

  @MainActor
  @Test func confirmSelectionReturnsSelectedResult() {
    let vm = LauncherViewModel()
    vm.apps = [
      AppItem(name: "Safari", path: "/Applications/Safari.app")
    ]
    vm.searchQuery = "safari"
    vm.updateSearch()
    let result = vm.confirmSelection()
    #expect(result != nil)
    #expect(result?.name == "Safari")
  }

  @MainActor
  @Test func confirmSelectionReturnsNilWhenNoResults() {
    let vm = LauncherViewModel()
    vm.searchQuery = ""
    vm.updateSearch()
    let result = vm.confirmSelection()
    #expect(result == nil)
  }

  @MainActor
  @Test func confirmSelectionRespectsSelectedIndex() {
    let vm = LauncherViewModel()
    vm.apps = [
      AppItem(name: "App Alpha", path: "/Applications/AppAlpha.app"),
      AppItem(name: "App Beta", path: "/Applications/AppBeta.app"),
      AppItem(name: "App Gamma", path: "/Applications/AppGamma.app"),
    ]
    vm.searchQuery = "app"
    vm.updateSearch()
    guard vm.searchResults.count >= 2 else {
      Issue.record("Expected at least 2 results but got \(vm.searchResults.count)")
      return
    }
    let firstName = vm.searchResults[0].name
    let secondName = vm.searchResults[1].name
    let result0 = vm.confirmSelection()
    #expect(result0?.name == firstName)

    vm.moveSelectionDown()
    let result1 = vm.confirmSelection()
    #expect(result1?.name == secondName)
  }
}

// MARK: - LauncherViewModel 特殊キー処理

@Suite("LauncherViewModel Special Key Handling")
struct LauncherViewModelSpecialKeyTests {

  @MainActor
  @Test func escapeReturnsDismiss() {
    let vm = LauncherViewModel()
    let action = vm.handleSpecialKey(.escape, modifiers: [])
    #expect(action == .dismiss)
  }

  @MainActor
  @Test func enterWithCalculatorResultReturnsCopyCalculator() {
    let vm = LauncherViewModel()
    vm.searchQuery = "1+2"
    vm.updateSearch()
    #expect(vm.calculatorResult != nil)
    let action = vm.handleSpecialKey(.enter, modifiers: [])
    #expect(action == .copyCalculator)
  }

  @MainActor
  @Test func enterWithoutCalculatorResultReturnsExecute() {
    let vm = LauncherViewModel()
    vm.apps = [
      AppItem(name: "Safari", path: "/Applications/Safari.app")
    ]
    vm.searchQuery = "safari"
    vm.updateSearch()
    let action = vm.handleSpecialKey(.enter, modifiers: [])
    #expect(action == .execute)
  }

  @MainActor
  @Test func enterWithNoResultsReturnsNil() {
    let vm = LauncherViewModel()
    vm.searchQuery = ""
    vm.updateSearch()
    let action = vm.handleSpecialKey(.enter, modifiers: [])
    #expect(action == nil)
  }

  @MainActor
  @Test func rightArrowOnDirectoryReturnsOpenInTerminal() {
    let vm = LauncherViewModel()
    vm.directories = [
      DirectoryItem(name: "my-project", path: "/Users/test/my-project")
    ]
    vm.searchQuery = "project"
    vm.updateSearch()
    guard !vm.searchResults.isEmpty, vm.searchResults[0].kind == .directory else {
      Issue.record("Expected directory result")
      return
    }
    let action = vm.handleSpecialKey(.right, modifiers: [])
    #expect(action == .openInTerminal)
  }

  @MainActor
  @Test func leftArrowOnDirectoryReturnsShowEditorPicker() {
    let vm = LauncherViewModel()
    vm.directories = [
      DirectoryItem(name: "my-project", path: "/Users/test/my-project")
    ]
    vm.searchQuery = "project"
    vm.updateSearch()
    guard !vm.searchResults.isEmpty, vm.searchResults[0].kind == .directory else {
      Issue.record("Expected directory result")
      return
    }
    let action = vm.handleSpecialKey(.left, modifiers: [])
    #expect(action == .showEditorPicker)
  }

  @MainActor
  @Test func commandRightArrowOnDirectoryReturnsShowTerminalPicker() {
    let vm = LauncherViewModel()
    vm.directories = [
      DirectoryItem(name: "my-project", path: "/Users/test/my-project")
    ]
    vm.searchQuery = "project"
    vm.updateSearch()
    guard !vm.searchResults.isEmpty, vm.searchResults[0].kind == .directory else {
      Issue.record("Expected directory result")
      return
    }
    let action = vm.handleSpecialKey(.right, modifiers: .command)
    #expect(action == .showTerminalPicker)
  }

  @MainActor
  @Test func rightArrowOnNonDirectoryReturnsNil() {
    let vm = LauncherViewModel()
    vm.apps = [
      AppItem(name: "Safari", path: "/Applications/Safari.app")
    ]
    vm.searchQuery = "safari"
    vm.updateSearch()
    guard !vm.searchResults.isEmpty, vm.searchResults[0].kind == .app else {
      Issue.record("Expected app result")
      return
    }
    let action = vm.handleSpecialKey(.right, modifiers: [])
    #expect(action == nil)
  }

  @MainActor
  @Test func leftArrowOnNonDirectoryReturnsNil() {
    let vm = LauncherViewModel()
    vm.apps = [
      AppItem(name: "Safari", path: "/Applications/Safari.app")
    ]
    vm.searchQuery = "safari"
    vm.updateSearch()
    guard !vm.searchResults.isEmpty, vm.searchResults[0].kind == .app else {
      Issue.record("Expected app result")
      return
    }
    let action = vm.handleSpecialKey(.left, modifiers: [])
    #expect(action == nil)
  }

  @MainActor
  @Test func arrowKeysWithNoResultsReturnNil() {
    let vm = LauncherViewModel()
    vm.searchQuery = ""
    vm.updateSearch()
    #expect(vm.handleSpecialKey(.right, modifiers: []) == nil)
    #expect(vm.handleSpecialKey(.left, modifiers: []) == nil)
  }
}

// MARK: - LauncherViewModel 検索クリア

@Suite("LauncherViewModel Clear Search")
struct LauncherViewModelClearSearchTests {

  @MainActor
  @Test func clearSearchResetsQuery() {
    let vm = LauncherViewModel()
    vm.searchQuery = "safari"
    vm.updateSearch()
    vm.clearSearch()
    #expect(vm.searchQuery == "")
  }

  @MainActor
  @Test func clearSearchResetsResults() {
    let vm = LauncherViewModel()
    vm.apps = [
      AppItem(name: "Safari", path: "/Applications/Safari.app")
    ]
    vm.searchQuery = "safari"
    vm.updateSearch()
    #expect(!vm.searchResults.isEmpty)
    vm.clearSearch()
    #expect(vm.searchResults.isEmpty)
  }

  @MainActor
  @Test func clearSearchResetsSelectedIndex() {
    let vm = LauncherViewModel()
    vm.apps = [
      AppItem(name: "App Alpha", path: "/Applications/AppAlpha.app"),
      AppItem(name: "App Beta", path: "/Applications/AppBeta.app"),
    ]
    vm.searchQuery = "app"
    vm.updateSearch()
    vm.moveSelectionDown()
    vm.clearSearch()
    #expect(vm.selectedIndex == 0)
  }

  @MainActor
  @Test func clearSearchResetsCalculatorResult() {
    let vm = LauncherViewModel()
    vm.searchQuery = "1+2"
    vm.updateSearch()
    #expect(vm.calculatorResult != nil)
    vm.clearSearch()
    #expect(vm.calculatorResult == nil)
  }
}

// MARK: - LauncherViewModel アップデートバナー

@Suite("LauncherViewModel Update Banner")
struct LauncherViewModelUpdateBannerTests {

  @MainActor
  @Test func setUpdateBannerVersion() {
    let vm = LauncherViewModel()
    vm.updateBannerVersion = "2.0.0"
    #expect(vm.updateBannerVersion == "2.0.0")
    #expect(vm.isUpdateBannerDismissed == false)
  }

  @MainActor
  @Test func dismissUpdateBannerSetsFlag() {
    let vm = LauncherViewModel()
    vm.updateBannerVersion = "2.0.0"
    vm.dismissUpdateBanner(version: "2.0.0")
    #expect(vm.isUpdateBannerDismissed == true)
  }

  @MainActor
  @Test func dismissUpdateBannerOnlyMatchesVersion() {
    let vm = LauncherViewModel()
    vm.updateBannerVersion = "2.0.0"
    vm.dismissUpdateBanner(version: "1.0.0")
    // 別バージョンの非表示要求は現在のバナーへ影響しない。
    #expect(vm.isUpdateBannerDismissed == false)
  }

  @MainActor
  @Test func dismissedBannerResetsWhenNewVersionSet() {
    let vm = LauncherViewModel()
    vm.updateBannerVersion = "2.0.0"
    vm.dismissUpdateBanner(version: "2.0.0")
    #expect(vm.isUpdateBannerDismissed == true)
    // 新しいバージョン表示時に非表示フラグがリセットされる。
    vm.showUpdateBanner(version: "3.0.0")
    #expect(vm.updateBannerVersion == "3.0.0")
    #expect(vm.isUpdateBannerDismissed == false)
  }

  @MainActor
  @Test func shouldShowUpdateBanner() {
    let vm = LauncherViewModel()
    // バナーバージョン未設定時。
    #expect(vm.shouldShowUpdateBanner == false)
    // バナーバージョンを設定する。
    vm.updateBannerVersion = "2.0.0"
    #expect(vm.shouldShowUpdateBanner == true)
    // バナーを非表示にする。
    vm.dismissUpdateBanner(version: "2.0.0")
    #expect(vm.shouldShowUpdateBanner == false)
  }
}

// MARK: - LauncherViewModel 計算結果コピー

@Suite("LauncherViewModel Copy Calculator")
struct LauncherViewModelCopyCalculatorTests {

  @MainActor
  @Test func copyCalculatorResultSetsClipboard() {
    let vm = LauncherViewModel()
    vm.searchQuery = "1+2"
    vm.updateSearch()
    #expect(vm.calculatorResult == "3")
    vm.copyCalculatorResult()
    let clipboard = NSPasteboard.general.string(forType: .string)
    #expect(clipboard == "3")
  }

  @MainActor
  @Test func copyCalculatorResultDoesNothingWhenNil() {
    let vm = LauncherViewModel()
    vm.searchQuery = "safari"
    vm.updateSearch()
    #expect(vm.calculatorResult == nil)
    // nil の場合もクラッシュしないことを確認する。
    vm.copyCalculatorResult()
  }
}

// MARK: - LauncherViewModel 特殊アクション

@Suite("LauncherViewModel Special Actions")
struct LauncherViewModelSpecialActionsTests {

  @MainActor
  @Test func googleSearchInsertedForGPrefix() {
    let vm = LauncherViewModel()
    vm.searchQuery = "g swift concurrency"
    vm.updateSearch()
    #expect(!vm.searchResults.isEmpty)
    #expect(vm.searchResults[0].kind == .webSearch)
    #expect(vm.searchResults[0].name.contains("Google"))
    #expect(vm.searchResults[0].path.contains("google.com/search"))
  }

  @MainActor
  @Test func xSearchInsertedForXPrefix() {
    let vm = LauncherViewModel()
    vm.searchQuery = "x swift"
    vm.updateSearch()
    #expect(!vm.searchResults.isEmpty)
    #expect(vm.searchResults[0].kind == .webSearch)
    #expect(vm.searchResults[0].name.contains("X"))
    #expect(vm.searchResults[0].path.contains("x.com/search"))
  }

  @MainActor
  @Test func googleSearchNotInsertedForGOnly() {
    let vm = LauncherViewModel()
    vm.searchQuery = "g "
    vm.updateSearch()
    // "g " の後ろが空なので挿入されない
    let webResults = vm.searchResults.filter { $0.kind == .webSearch }
    #expect(webResults.isEmpty)
  }

  @MainActor
  @Test func colorPickerInsertedForColorKeyword() {
    let vm = LauncherViewModel()
    vm.searchQuery = "color"
    vm.updateSearch()
    #expect(!vm.searchResults.isEmpty)
    #expect(vm.searchResults[0].kind == .colorPicker)
  }

  @MainActor
  @Test func colorPickerInsertedForKatakanaKeyword() {
    let vm = LauncherViewModel()
    vm.searchQuery = "カラー"
    vm.updateSearch()
    #expect(!vm.searchResults.isEmpty)
    #expect(vm.searchResults[0].kind == .colorPicker)
  }

  @MainActor
  @Test func emojiPickerInsertedForEmojiKeyword() {
    let vm = LauncherViewModel()
    vm.searchQuery = "emoji"
    vm.updateSearch()
    #expect(!vm.searchResults.isEmpty)
    #expect(vm.searchResults[0].kind == .emoji)
  }

  @MainActor
  @Test func emojiPickerInsertedForEmojiWithSpace() {
    let vm = LauncherViewModel()
    vm.searchQuery = "emoji smile"
    vm.updateSearch()
    #expect(!vm.searchResults.isEmpty)
    #expect(vm.searchResults[0].kind == .emoji)
  }

  @MainActor
  @Test func gPrefixQueryMatchesOnlyGoogleNotX() {
    let vm = LauncherViewModel()
    // "g x foo" は "g " プレフィックスに一致するので Google 検索のみ
    vm.searchQuery = "g x foo"
    vm.updateSearch()
    let webResults = vm.searchResults.filter { $0.kind == .webSearch }
    #expect(webResults.count == 1)
    #expect(webResults[0].name.contains("Google"))
    #expect(webResults[0].path.contains("google.com/search"))
    // X 検索は含まれない
    #expect(!webResults.contains(where: { $0.path.contains("x.com/search") }))
  }

  @MainActor
  @Test func xPrefixQueryMatchesOnlyXNotGoogle() {
    let vm = LauncherViewModel()
    vm.searchQuery = "x swift"
    vm.updateSearch()
    let webResults = vm.searchResults.filter { $0.kind == .webSearch }
    #expect(webResults.count == 1)
    #expect(webResults[0].name.contains("X"))
    #expect(webResults[0].path.contains("x.com/search"))
    // Google 検索は含まれない
    #expect(!webResults.contains(where: { $0.path.contains("google.com/search") }))
  }

  @MainActor
  @Test func gPrefixWithXKeywordProducesCorrectSearchTerm() {
    let vm = LauncherViewModel()
    // "g x swift" は Google 検索で "x swift" を検索
    vm.searchQuery = "g x swift"
    vm.updateSearch()
    let webResults = vm.searchResults.filter { $0.kind == .webSearch }
    #expect(webResults.count == 1)
    #expect(webResults[0].path.contains("google.com/search"))
    #expect(
      webResults[0].path.contains("x%20swift") || webResults[0].path.contains("x+swift")
        || webResults[0].path.contains("x swift"))
  }

  @MainActor
  @Test func googleSearchEncodesQuerySeparatorsAsValue() {
    let vm = LauncherViewModel()
    vm.searchQuery = "g a&b=c+d"
    vm.updateSearch()
    let webResults = vm.searchResults.filter { $0.kind == .webSearch }
    #expect(webResults.count == 1)
    #expect(webResults[0].path == "https://www.google.com/search?q=a%26b%3Dc%2Bd")
    #expect(Self.queryValue(from: webResults[0].path) == "a&b=c+d")
  }

  @MainActor
  @Test func xSearchEncodesQuerySeparatorsAsValue() {
    let vm = LauncherViewModel()
    vm.searchQuery = "x a&b=c+d"
    vm.updateSearch()
    let webResults = vm.searchResults.filter { $0.kind == .webSearch }
    #expect(webResults.count == 1)
    #expect(webResults[0].path == "https://x.com/search?q=a%26b%3Dc%2Bd")
    #expect(Self.queryValue(from: webResults[0].path) == "a&b=c+d")
  }

  private static func queryValue(from urlString: String) -> String? {
    URLComponents(string: urlString)?.queryItems?.first { $0.name == "q" }?.value
  }
}

// MARK: - LauncherViewModel 選択確定エッジケース

@Suite("LauncherViewModel Confirm Selection Edge Cases")
struct LauncherViewModelConfirmEdgeCaseTests {

  @MainActor
  @Test func confirmSelectionWithOutOfBoundsIndexReturnsNil() {
    let vm = LauncherViewModel()
    vm.apps = [AppItem(name: "Safari", path: "/Applications/Safari.app")]
    vm.searchQuery = "safari"
    vm.updateSearch()
    // 強制的にインデックスを範囲外に設定
    vm.selectedIndex = 100
    let result = vm.confirmSelection()
    #expect(result == nil)
  }

  @MainActor
  @Test func searchResultsMaxLimit() {
    let vm = LauncherViewModel()
    // 25個のアプリを生成（検索結果上限20件のテスト）
    vm.apps = (0..<25).map { i in
      AppItem(name: "TestApp\(i)", path: "/Applications/TestApp\(i).app")
    }
    vm.searchQuery = "testapp"
    vm.updateSearch()
    #expect(vm.searchResults.count <= 20)
  }
}

// MARK: - LauncherViewModel コマンド結果のキー操作

@Suite("LauncherViewModel Command Key Handling")
struct LauncherViewModelCommandKeyTests {

  @MainActor
  @Test func rightArrowOnCommandReturnsNil() {
    // コマンド結果に対して右キーは無効（ディレクトリ専用）
    let vm = LauncherViewModel()
    vm.commands = [
      CustomCommand(alias: "deploy", command: "npm run deploy")
    ]
    vm.searchQuery = "deploy"
    vm.updateSearch()
    guard !vm.searchResults.isEmpty, vm.searchResults[0].kind == .command else {
      Issue.record("Expected command result")
      return
    }
    let action = vm.handleSpecialKey(.right, modifiers: [])
    #expect(action == nil)
  }

  @MainActor
  @Test func leftArrowOnCommandReturnsNil() {
    // コマンド結果に対して左キーは無効（ディレクトリ専用）
    let vm = LauncherViewModel()
    vm.commands = [
      CustomCommand(alias: "deploy", command: "npm run deploy")
    ]
    vm.searchQuery = "deploy"
    vm.updateSearch()
    guard !vm.searchResults.isEmpty, vm.searchResults[0].kind == .command else {
      Issue.record("Expected command result")
      return
    }
    let action = vm.handleSpecialKey(.left, modifiers: [])
    #expect(action == nil)
  }

  @MainActor
  @Test func commandRightArrowOnCommandReturnsNil() {
    // コマンド結果に対して Cmd+右キーも無効
    let vm = LauncherViewModel()
    vm.commands = [
      CustomCommand(alias: "deploy", command: "npm run deploy")
    ]
    vm.searchQuery = "deploy"
    vm.updateSearch()
    guard !vm.searchResults.isEmpty, vm.searchResults[0].kind == .command else {
      Issue.record("Expected command result")
      return
    }
    let action = vm.handleSpecialKey(.right, modifiers: .command)
    #expect(action == nil)
  }

  @MainActor
  @Test func commandLeftArrowOnDirectoryReturnsEditorPicker() {
    // Cmd+左キーでもエディタピッカー表示（修飾キーは左矢印では無視される）
    let vm = LauncherViewModel()
    vm.directories = [
      DirectoryItem(name: "my-project", path: "/Users/test/my-project")
    ]
    vm.searchQuery = "project"
    vm.updateSearch()
    guard !vm.searchResults.isEmpty, vm.searchResults[0].kind == .directory else {
      Issue.record("Expected directory result")
      return
    }
    let action = vm.handleSpecialKey(.left, modifiers: .command)
    #expect(action == .showEditorPicker)
  }
}

// MARK: - LauncherViewModel 計算式検出エッジケース

@Suite("LauncherViewModel Calculator Expression Edge Cases")
struct LauncherViewModelCalculatorExpressionEdgeCaseTests {

  @MainActor
  @Test("演算子を含むが不正な式は計算結果 nil を返す")
  func invalidExpressionWithOperatorReturnsNil() {
    let vm = LauncherViewModel()
    vm.searchQuery = "abc+def"
    vm.checkForCalculatorExpression()
    #expect(vm.calculatorResult == nil)
  }

  @MainActor
  @Test("演算子を含まない数値のみは計算式とみなさない")
  func numericOnlyIsNotCalculator() {
    let vm = LauncherViewModel()
    vm.searchQuery = "12345"
    vm.checkForCalculatorExpression()
    #expect(vm.calculatorResult == nil)
  }

  @MainActor
  @Test("負の数のみ（単項マイナス）は演算子として検出される")
  func unaryMinusDetectedAsOperator() {
    let vm = LauncherViewModel()
    vm.searchQuery = "-5"
    vm.checkForCalculatorExpression()
    // "-" が演算子として検出され、evaluate("-5") は -5.0 を返す
    #expect(vm.calculatorResult != nil)
  }

  @MainActor
  @Test("空白のみのクエリは計算結果 nil を返す")
  func whitespaceOnlyReturnsNil() {
    let vm = LauncherViewModel()
    vm.searchQuery = "   "
    vm.checkForCalculatorExpression()
    #expect(vm.calculatorResult == nil)
  }

  @MainActor
  @Test("剰余演算子を含む式が正しく評価される")
  func moduloExpressionEvaluated() {
    let vm = LauncherViewModel()
    vm.searchQuery = "10%3"
    vm.checkForCalculatorExpression()
    #expect(vm.calculatorResult == "1")
  }
}
