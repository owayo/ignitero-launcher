import AppKit
import Testing

@testable import IgniteroCore

// MARK: - Test Helpers

private func makeSampleTerminals() -> [TerminalInfo] {
  [
    TerminalInfo(id: .terminal, name: "Terminal", appName: "Terminal.app", installed: true),
    TerminalInfo(id: .iterm2, name: "iTerm2", appName: "iTerm.app", installed: true),
    TerminalInfo(id: .ghostty, name: "Ghostty", appName: "Ghostty.app", installed: true),
    TerminalInfo(id: .warp, name: "Warp", appName: "Warp.app", installed: true),
  ]
}

// MARK: - TerminalPickerState Tests

@Suite("TerminalPickerState Tests")
struct TerminalPickerStateTests {

  // MARK: - Initial State

  @Test @MainActor func initialStateHasNoTerminals() {
    let state = TerminalPickerState()
    #expect(state.terminals.isEmpty)
  }

  @Test @MainActor func initialHighlightedIndexIsZero() {
    let state = TerminalPickerState()
    #expect(state.highlightedIndex == 0)
  }

  @Test @MainActor func initialSelectedTerminalIsNil() {
    let state = TerminalPickerState()
    #expect(state.selectedTerminal == nil)
  }

  // MARK: - Reset

  @Test @MainActor func resetSetsTerminals() {
    let state = TerminalPickerState()
    let terminals = makeSampleTerminals()
    state.reset(terminals: terminals)
    #expect(state.terminals.count == 4)
    #expect(state.terminals[0].id == .terminal)
    #expect(state.terminals[3].id == .warp)
  }

  @Test @MainActor func resetSetsHighlightedIndexToZero() {
    let state = TerminalPickerState()
    let terminals = makeSampleTerminals()
    state.reset(terminals: terminals)
    state.moveDown()
    state.moveDown()
    #expect(state.highlightedIndex == 2)

    state.reset(terminals: terminals)
    #expect(state.highlightedIndex == 0)
  }

  @Test @MainActor func resetClearsSelectedTerminal() {
    let state = TerminalPickerState()
    let terminals = makeSampleTerminals()
    state.reset(terminals: terminals)
    state.confirmSelection()
    #expect(state.selectedTerminal != nil)

    state.reset(terminals: terminals)
    #expect(state.selectedTerminal == nil)
  }

  // MARK: - Move Down

  @Test @MainActor func moveDownIncrementsHighlightedIndex() {
    let state = TerminalPickerState()
    state.reset(terminals: makeSampleTerminals())

    state.moveDown()
    #expect(state.highlightedIndex == 1)

    state.moveDown()
    #expect(state.highlightedIndex == 2)
  }

  @Test @MainActor func moveDownWrapsAroundToFirstItem() {
    let state = TerminalPickerState()
    state.reset(terminals: makeSampleTerminals())

    state.moveDown()  // 1
    state.moveDown()  // 2
    state.moveDown()  // 3
    #expect(state.highlightedIndex == 3)

    state.moveDown()  // wraps to 0
    #expect(state.highlightedIndex == 0)
  }

  @Test @MainActor func moveDownWithEmptyTerminalsStaysAtZero() {
    let state = TerminalPickerState()
    state.moveDown()
    #expect(state.highlightedIndex == 0)
  }

  // MARK: - Move Up

  @Test @MainActor func moveUpDecrementsHighlightedIndex() {
    let state = TerminalPickerState()
    state.reset(terminals: makeSampleTerminals())
    state.moveDown()
    state.moveDown()
    #expect(state.highlightedIndex == 2)

    state.moveUp()
    #expect(state.highlightedIndex == 1)
  }

  @Test @MainActor func moveUpWrapsAroundToLastItem() {
    let state = TerminalPickerState()
    state.reset(terminals: makeSampleTerminals())
    #expect(state.highlightedIndex == 0)

    state.moveUp()  // wraps to 3
    #expect(state.highlightedIndex == 3)
  }

  @Test @MainActor func moveUpWithEmptyTerminalsStaysAtZero() {
    let state = TerminalPickerState()
    state.moveUp()
    #expect(state.highlightedIndex == 0)
  }

  // MARK: - Confirm Selection

  @Test @MainActor func confirmSelectionSetsSelectedTerminal() {
    let state = TerminalPickerState()
    state.reset(terminals: makeSampleTerminals())
    state.confirmSelection()
    #expect(state.selectedTerminal == .terminal)
  }

  @Test @MainActor func confirmSelectionWithNavigationSelectsCorrectTerminal() {
    let state = TerminalPickerState()
    state.reset(terminals: makeSampleTerminals())
    state.moveDown()
    state.moveDown()
    state.confirmSelection()
    #expect(state.selectedTerminal == .ghostty)
  }

  @Test @MainActor func confirmSelectionAfterWrapSelectsCorrectTerminal() {
    let state = TerminalPickerState()
    state.reset(terminals: makeSampleTerminals())
    state.moveUp()  // wraps to 3 (warp)
    state.confirmSelection()
    #expect(state.selectedTerminal == .warp)
  }

  @Test @MainActor func confirmSelectionWithEmptyTerminalsKeepsNil() {
    let state = TerminalPickerState()
    state.confirmSelection()
    #expect(state.selectedTerminal == nil)
  }

  // MARK: - Full Navigation Cycle

  @Test @MainActor func fullCycleDownReturnsToStart() {
    let state = TerminalPickerState()
    state.reset(terminals: makeSampleTerminals())

    for _ in 0..<4 {
      state.moveDown()
    }
    #expect(state.highlightedIndex == 0)
  }

  @Test @MainActor func fullCycleUpReturnsToStart() {
    let state = TerminalPickerState()
    state.reset(terminals: makeSampleTerminals())

    for _ in 0..<4 {
      state.moveUp()
    }
    #expect(state.highlightedIndex == 0)
  }
}

// MARK: - TerminalPickerPanel Tests

@Suite("TerminalPickerPanel Tests")
struct TerminalPickerPanelTests {

  // MARK: - Style Mask

  @Test @MainActor func styleMaskIncludesBorderless() {
    let panel = TerminalPickerPanel()
    #expect(panel.styleMask.contains(.borderless))
  }

  @Test @MainActor func styleMaskIncludesNonactivatingPanel() {
    let panel = TerminalPickerPanel()
    #expect(panel.styleMask.contains(.nonactivatingPanel))
  }

  @Test @MainActor func styleMaskIncludesTitled() {
    let panel = TerminalPickerPanel()
    #expect(panel.styleMask.contains(.titled))
  }

  @Test @MainActor func styleMaskIncludesFullSizeContentView() {
    let panel = TerminalPickerPanel()
    #expect(panel.styleMask.contains(.fullSizeContentView))
  }

  // MARK: - Panel Properties

  @Test @MainActor func isFloatingPanelIsTrue() {
    let panel = TerminalPickerPanel()
    #expect(panel.isFloatingPanel == true)
  }

  @Test @MainActor func levelIsAboveStatusBar() {
    let panel = TerminalPickerPanel()
    let expectedLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
    #expect(panel.level == expectedLevel)
  }

  @Test @MainActor func hidesOnDeactivateIsFalse() {
    let panel = TerminalPickerPanel()
    #expect(panel.hidesOnDeactivate == false)
  }

  // MARK: - Collection Behavior

  @Test @MainActor func collectionBehaviorIncludesCanJoinAllSpaces() {
    let panel = TerminalPickerPanel()
    #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
  }

  @Test @MainActor func collectionBehaviorIncludesFullScreenAuxiliary() {
    let panel = TerminalPickerPanel()
    #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
  }

  @Test @MainActor func collectionBehaviorIncludesTransient() {
    let panel = TerminalPickerPanel()
    #expect(panel.collectionBehavior.contains(.transient))
  }

  @Test @MainActor func collectionBehaviorIncludesIgnoresCycle() {
    let panel = TerminalPickerPanel()
    #expect(panel.collectionBehavior.contains(.ignoresCycle))
  }

  // MARK: - Key / Main Behavior

  @Test @MainActor func canBecomeKeyReturnsTrue() {
    let panel = TerminalPickerPanel()
    #expect(panel.canBecomeKey == true)
  }

  @Test @MainActor func canBecomeMainReturnsFalse() {
    let panel = TerminalPickerPanel()
    #expect(panel.canBecomeMain == false)
  }

  // MARK: - Titlebar Settings

  @Test @MainActor func titlebarAppearsTransparentIsTrue() {
    let panel = TerminalPickerPanel()
    #expect(panel.titlebarAppearsTransparent == true)
  }

  @Test @MainActor func titleVisibilityIsHidden() {
    let panel = TerminalPickerPanel()
    #expect(panel.titleVisibility == .hidden)
  }

  // MARK: - Movement & Appearance

  @Test @MainActor func isMovableByWindowBackgroundIsTrue() {
    let panel = TerminalPickerPanel()
    #expect(panel.isMovableByWindowBackground == true)
  }

  @Test @MainActor func backgroundColorIsClear() {
    let panel = TerminalPickerPanel()
    #expect(panel.backgroundColor == .clear)
  }

  @Test @MainActor func isOpaqueIsFalse() {
    let panel = TerminalPickerPanel()
    #expect(panel.isOpaque == false)
  }

  // MARK: - State Integration

  @Test @MainActor func panelHasState() {
    let panel = TerminalPickerPanel()
    #expect(panel.state.highlightedIndex == 0)
    #expect(panel.state.selectedTerminal == nil)
  }

  // MARK: - Dismiss

  @Test @MainActor func dismissOrdersOutPanel() {
    let panel = TerminalPickerPanel()
    panel.dismiss()
    #expect(panel.isVisible == false)
  }

  @Test @MainActor func dismissDoesNotSetSelectedTerminal() {
    let panel = TerminalPickerPanel()
    panel.state.reset(terminals: makeSampleTerminals())
    panel.dismiss()
    #expect(panel.state.selectedTerminal == nil)
  }
}
