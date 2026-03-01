import AppKit
import Testing

@testable import IgniteroCore

// MARK: - EditorPickerState Tests

@Suite("EditorPickerState Initial State")
struct EditorPickerStateInitialTests {

  @MainActor
  @Test func initialSelectedIndexIsNil() {
    let state = EditorPickerState(availableEditors: EditorType.allCases)
    #expect(state.selectedIndex == nil)
  }

  @MainActor
  @Test func initialConfirmedEditorIsNil() {
    let state = EditorPickerState(availableEditors: EditorType.allCases)
    #expect(state.confirmedEditor == nil)
  }

  @MainActor
  @Test func initialIsDismissedIsFalse() {
    let state = EditorPickerState(availableEditors: EditorType.allCases)
    #expect(state.isDismissed == false)
  }

  @MainActor
  @Test func availableEditorsAreStored() {
    let editors: [EditorType] = [.cursor, .vscode]
    let state = EditorPickerState(availableEditors: editors)
    #expect(state.availableEditors == editors)
  }

  @MainActor
  @Test func emptyAvailableEditors() {
    let state = EditorPickerState(availableEditors: [])
    #expect(state.availableEditors.isEmpty)
  }
}

// MARK: - Shortcut Key Mapping Tests

@Suite("EditorPickerState Shortcut Keys")
struct EditorPickerStateShortcutTests {

  @MainActor
  @Test func shortcutWSelectsWindsurf() {
    let state = EditorPickerState(availableEditors: EditorType.allCases)
    let handled = state.handleKey("w")
    #expect(handled == true)
    #expect(state.selectedEditor == .windsurf)
  }

  @MainActor
  @Test func shortcutCSelectsCursor() {
    let state = EditorPickerState(availableEditors: EditorType.allCases)
    let handled = state.handleKey("c")
    #expect(handled == true)
    #expect(state.selectedEditor == .cursor)
  }

  @MainActor
  @Test func shortcutVSelectsVSCode() {
    let state = EditorPickerState(availableEditors: EditorType.allCases)
    let handled = state.handleKey("v")
    #expect(handled == true)
    #expect(state.selectedEditor == .vscode)
  }

  @MainActor
  @Test func shortcutASelectsAntigravity() {
    let state = EditorPickerState(availableEditors: EditorType.allCases)
    let handled = state.handleKey("a")
    #expect(handled == true)
    #expect(state.selectedEditor == .antigravity)
  }

  @MainActor
  @Test func shortcutZSelectsZed() {
    let state = EditorPickerState(availableEditors: EditorType.allCases)
    let handled = state.handleKey("z")
    #expect(handled == true)
    #expect(state.selectedEditor == .zed)
  }

  @MainActor
  @Test func shortcutForUnavailableEditorIsIgnored() {
    let state = EditorPickerState(availableEditors: [.cursor, .vscode])
    let handled = state.handleKey("w")  // windsurf not available
    #expect(handled == false)
    #expect(state.selectedIndex == nil)
  }

  @MainActor
  @Test func unknownKeyIsIgnored() {
    let state = EditorPickerState(availableEditors: EditorType.allCases)
    let handled = state.handleKey("x")
    #expect(handled == false)
    #expect(state.selectedIndex == nil)
  }

  @MainActor
  @Test func shortcutKeySetsCorrectIndex() {
    let editors: [EditorType] = [.windsurf, .cursor, .vscode]
    let state = EditorPickerState(availableEditors: editors)
    _ = state.handleKey("v")
    #expect(state.selectedIndex == 2)  // vscode is at index 2
  }

  @MainActor
  @Test func shortcutKeySetsCorrectIndexForReorderedList() {
    let editors: [EditorType] = [.zed, .cursor, .windsurf]
    let state = EditorPickerState(availableEditors: editors)
    _ = state.handleKey("c")
    #expect(state.selectedIndex == 1)  // cursor is at index 1
  }
}

// MARK: - Arrow Key Navigation Tests

@Suite("EditorPickerState Arrow Key Navigation")
struct EditorPickerStateArrowKeyTests {

  @MainActor
  @Test func arrowDownFromNilSelectsFirst() {
    let state = EditorPickerState(availableEditors: EditorType.allCases)
    state.moveDown()
    #expect(state.selectedIndex == 0)
  }

  @MainActor
  @Test func arrowDownIncrementsIndex() {
    let state = EditorPickerState(availableEditors: EditorType.allCases)
    state.moveDown()  // 0
    state.moveDown()  // 1
    #expect(state.selectedIndex == 1)
  }

  @MainActor
  @Test func arrowDownWrapsAroundToFirst() {
    let editors: [EditorType] = [.windsurf, .cursor, .vscode]
    let state = EditorPickerState(availableEditors: editors)
    state.moveDown()  // 0
    state.moveDown()  // 1
    state.moveDown()  // 2
    state.moveDown()  // wraps to 0
    #expect(state.selectedIndex == 0)
  }

  @MainActor
  @Test func arrowUpFromNilSelectsLast() {
    let editors: [EditorType] = [.windsurf, .cursor, .vscode]
    let state = EditorPickerState(availableEditors: editors)
    state.moveUp()
    #expect(state.selectedIndex == 2)  // last index
  }

  @MainActor
  @Test func arrowUpDecrementsIndex() {
    let state = EditorPickerState(availableEditors: EditorType.allCases)
    state.moveDown()  // 0
    state.moveDown()  // 1
    state.moveDown()  // 2
    state.moveUp()  // 1
    #expect(state.selectedIndex == 1)
  }

  @MainActor
  @Test func arrowUpWrapsAroundToLast() {
    let editors: [EditorType] = [.windsurf, .cursor, .vscode]
    let state = EditorPickerState(availableEditors: editors)
    state.moveDown()  // 0
    state.moveUp()  // wraps to 2
    #expect(state.selectedIndex == 2)
  }

  @MainActor
  @Test func arrowDownOnEmptyListDoesNothing() {
    let state = EditorPickerState(availableEditors: [])
    state.moveDown()
    #expect(state.selectedIndex == nil)
  }

  @MainActor
  @Test func arrowUpOnEmptyListDoesNothing() {
    let state = EditorPickerState(availableEditors: [])
    state.moveUp()
    #expect(state.selectedIndex == nil)
  }
}

// MARK: - Enter / Escape Tests

@Suite("EditorPickerState Confirm and Dismiss")
struct EditorPickerStateConfirmDismissTests {

  @MainActor
  @Test func enterConfirmsSelectedEditor() {
    let state = EditorPickerState(availableEditors: EditorType.allCases)
    state.moveDown()  // select first (windsurf)
    state.confirm()
    #expect(state.confirmedEditor == .windsurf)
  }

  @MainActor
  @Test func enterWithNoSelectionDoesNotConfirm() {
    let state = EditorPickerState(availableEditors: EditorType.allCases)
    state.confirm()
    #expect(state.confirmedEditor == nil)
  }

  @MainActor
  @Test func enterAfterShortcutConfirmsCorrectEditor() {
    let state = EditorPickerState(availableEditors: EditorType.allCases)
    _ = state.handleKey("c")
    state.confirm()
    #expect(state.confirmedEditor == .cursor)
  }

  @MainActor
  @Test func escapeSetsDismissed() {
    let state = EditorPickerState(availableEditors: EditorType.allCases)
    state.dismiss()
    #expect(state.isDismissed == true)
  }

  @MainActor
  @Test func escapeDoesNotSetConfirmedEditor() {
    let state = EditorPickerState(availableEditors: EditorType.allCases)
    state.moveDown()
    state.dismiss()
    #expect(state.confirmedEditor == nil)
    #expect(state.isDismissed == true)
  }
}

// MARK: - Selected Editor Property Tests

@Suite("EditorPickerState Selected Editor")
struct EditorPickerStateSelectedEditorTests {

  @MainActor
  @Test func selectedEditorReturnsNilWhenNoSelection() {
    let state = EditorPickerState(availableEditors: EditorType.allCases)
    #expect(state.selectedEditor == nil)
  }

  @MainActor
  @Test func selectedEditorReturnsCorrectEditorForIndex() {
    let editors: [EditorType] = [.cursor, .vscode, .zed]
    let state = EditorPickerState(availableEditors: editors)
    state.moveDown()  // index 0 = cursor
    #expect(state.selectedEditor == .cursor)
    state.moveDown()  // index 1 = vscode
    #expect(state.selectedEditor == .vscode)
    state.moveDown()  // index 2 = zed
    #expect(state.selectedEditor == .zed)
  }
}

// MARK: - Reset Tests

@Suite("EditorPickerState Reset")
struct EditorPickerStateResetTests {

  @MainActor
  @Test func resetClearsSelection() {
    let state = EditorPickerState(availableEditors: EditorType.allCases)
    state.moveDown()
    state.reset()
    #expect(state.selectedIndex == nil)
  }

  @MainActor
  @Test func resetClearsConfirmedEditor() {
    let state = EditorPickerState(availableEditors: EditorType.allCases)
    state.moveDown()
    state.confirm()
    state.reset()
    #expect(state.confirmedEditor == nil)
  }

  @MainActor
  @Test func resetClearsDismissed() {
    let state = EditorPickerState(availableEditors: EditorType.allCases)
    state.dismiss()
    state.reset()
    #expect(state.isDismissed == false)
  }
}

// MARK: - EditorPickerPanel Configuration Tests

@Suite("EditorPickerPanel Configuration")
struct EditorPickerPanelConfigurationTests {

  // MARK: - Style Mask

  @Test @MainActor func styleMaskIncludesBorderless() {
    let panel = EditorPickerPanel()
    #expect(panel.styleMask.contains(.borderless))
  }

  @Test @MainActor func styleMaskIncludesNonactivatingPanel() {
    let panel = EditorPickerPanel()
    #expect(panel.styleMask.contains(.nonactivatingPanel))
  }

  @Test @MainActor func styleMaskIncludesTitled() {
    let panel = EditorPickerPanel()
    #expect(panel.styleMask.contains(.titled))
  }

  @Test @MainActor func styleMaskIncludesFullSizeContentView() {
    let panel = EditorPickerPanel()
    #expect(panel.styleMask.contains(.fullSizeContentView))
  }

  // MARK: - Panel Properties

  @Test @MainActor func isFloatingPanelIsTrue() {
    let panel = EditorPickerPanel()
    #expect(panel.isFloatingPanel == true)
  }

  @Test @MainActor func levelIsAboveStatusBar() {
    let panel = EditorPickerPanel()
    #expect(panel.level == NSWindow.Level(NSWindow.Level.statusBar.rawValue + 1))
  }

  @Test @MainActor func hidesOnDeactivateIsFalse() {
    let panel = EditorPickerPanel()
    #expect(panel.hidesOnDeactivate == false)
  }

  // MARK: - Collection Behavior

  @Test @MainActor func collectionBehaviorIncludesCanJoinAllSpaces() {
    let panel = EditorPickerPanel()
    #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
  }

  @Test @MainActor func collectionBehaviorIncludesFullScreenAuxiliary() {
    let panel = EditorPickerPanel()
    #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
  }

  @Test @MainActor func collectionBehaviorIncludesTransient() {
    let panel = EditorPickerPanel()
    #expect(panel.collectionBehavior.contains(.transient))
  }

  @Test @MainActor func collectionBehaviorIncludesIgnoresCycle() {
    let panel = EditorPickerPanel()
    #expect(panel.collectionBehavior.contains(.ignoresCycle))
  }

  // MARK: - Key / Main Behavior

  @Test @MainActor func canBecomeKeyReturnsTrue() {
    let panel = EditorPickerPanel()
    #expect(panel.canBecomeKey == true)
  }

  @Test @MainActor func canBecomeMainReturnsFalse() {
    let panel = EditorPickerPanel()
    #expect(panel.canBecomeMain == false)
  }

  // MARK: - Titlebar Settings

  @Test @MainActor func titlebarAppearsTransparentIsTrue() {
    let panel = EditorPickerPanel()
    #expect(panel.titlebarAppearsTransparent == true)
  }

  @Test @MainActor func titleVisibilityIsHidden() {
    let panel = EditorPickerPanel()
    #expect(panel.titleVisibility == .hidden)
  }

  // MARK: - Movement & Appearance

  @Test @MainActor func isMovableByWindowBackgroundIsTrue() {
    let panel = EditorPickerPanel()
    #expect(panel.isMovableByWindowBackground == true)
  }

  @Test @MainActor func backgroundColorIsClear() {
    let panel = EditorPickerPanel()
    #expect(panel.backgroundColor == .clear)
  }

  @Test @MainActor func isOpaqueIsFalse() {
    let panel = EditorPickerPanel()
    #expect(panel.isOpaque == false)
  }

  // MARK: - State

  @Test @MainActor func panelHasPickerState() {
    let panel = EditorPickerPanel()
    _ = panel.pickerState  // 非オプショナルなので存在確認のみ
  }
}

// MARK: - EditorPickerPanel Key Event Handling Tests

@Suite("EditorPickerPanel Key Event Integration")
struct EditorPickerPanelKeyEventTests {

  @MainActor
  @Test func shortcutKeyMappingIsCorrect() {
    #expect(EditorPickerState.shortcutKey(for: .windsurf) == "w")
    #expect(EditorPickerState.shortcutKey(for: .cursor) == "c")
    #expect(EditorPickerState.shortcutKey(for: .vscode) == "v")
    #expect(EditorPickerState.shortcutKey(for: .antigravity) == "a")
    #expect(EditorPickerState.shortcutKey(for: .zed) == "z")
  }

  @MainActor
  @Test func editorForShortcutKeyMapping() {
    #expect(EditorPickerState.editor(forShortcutKey: "w") == .windsurf)
    #expect(EditorPickerState.editor(forShortcutKey: "c") == .cursor)
    #expect(EditorPickerState.editor(forShortcutKey: "v") == .vscode)
    #expect(EditorPickerState.editor(forShortcutKey: "a") == .antigravity)
    #expect(EditorPickerState.editor(forShortcutKey: "z") == .zed)
    #expect(EditorPickerState.editor(forShortcutKey: "x") == nil)
  }
}
