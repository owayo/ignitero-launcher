import IgniteroCore
import Testing

@Suite("選択インデックス境界値テスト")
@MainActor
struct SelectionIndexBoundaryTests {
  @Test("ランチャーの負の選択位置は未選択として扱う")
  func launcherNegativeSelectionReturnsNil() {
    let viewModel = LauncherViewModel()
    viewModel.apps = [AppItem(name: "Safari", path: "/Applications/Safari.app")]
    viewModel.searchQuery = "Safari"
    viewModel.updateSearch()
    viewModel.selectedIndex = -1

    #expect(viewModel.confirmSelection() == nil)
  }

  @Test("ターミナルピッカーの負の選択位置は未選択として扱う")
  func terminalPickerNegativeSelectionKeepsNil() {
    let state = TerminalPickerState()
    state.reset(terminals: [
      TerminalInfo(
        id: .terminal,
        name: "Terminal",
        appName: "Terminal.app",
        installed: true
      )
    ])
    state.highlightedIndex = -1

    state.confirmSelection()

    #expect(state.selectedTerminal == nil)
  }
}
