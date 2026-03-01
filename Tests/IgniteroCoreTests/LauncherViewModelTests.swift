import AppKit
import Foundation
import Testing

@testable import IgniteroCore

// MARK: - LauncherViewModel Initial State

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

// MARK: - LauncherViewModel Search

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
    // Now change query, selectedIndex should reset
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

// MARK: - LauncherViewModel Calculator

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
    // Result should be a decimal representation
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
    // A single number without operators is not a calculator expression
    // because there's no operation to perform
    #expect(vm.calculatorResult == nil)
  }
}

// MARK: - LauncherViewModel Selection Navigation

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
    // Ensure we have results
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

// MARK: - LauncherViewModel Confirm Selection

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

// MARK: - LauncherViewModel Special Key Handling

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

// MARK: - LauncherViewModel Clear Search

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

// MARK: - LauncherViewModel Update Banner

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
    // Dismissing a different version should not affect current banner
    #expect(vm.isUpdateBannerDismissed == false)
  }

  @MainActor
  @Test func dismissedBannerResetsWhenNewVersionSet() {
    let vm = LauncherViewModel()
    vm.updateBannerVersion = "2.0.0"
    vm.dismissUpdateBanner(version: "2.0.0")
    #expect(vm.isUpdateBannerDismissed == true)
    // Setting a new version resets the dismissed flag
    vm.showUpdateBanner(version: "3.0.0")
    #expect(vm.updateBannerVersion == "3.0.0")
    #expect(vm.isUpdateBannerDismissed == false)
  }

  @MainActor
  @Test func shouldShowUpdateBanner() {
    let vm = LauncherViewModel()
    // No banner version set
    #expect(vm.shouldShowUpdateBanner == false)
    // Set banner version
    vm.updateBannerVersion = "2.0.0"
    #expect(vm.shouldShowUpdateBanner == true)
    // Dismiss it
    vm.dismissUpdateBanner(version: "2.0.0")
    #expect(vm.shouldShowUpdateBanner == false)
  }
}

// MARK: - LauncherViewModel Copy Calculator Result

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
    // Should not crash
    vm.copyCalculatorResult()
  }
}
