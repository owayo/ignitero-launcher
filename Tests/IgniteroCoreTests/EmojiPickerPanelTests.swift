import AppKit
import Foundation
import Testing

@testable import IgniteroCore

// MARK: - EmojiPickerPanel テスト

@Suite("EmojiPickerPanel")
@MainActor
struct EmojiPickerPanelTests {

  @Test("初期化時にクラッシュしない")
  func initDoesNotCrash() {
    let panel = EmojiPickerPanel()
    _ = panel
  }

  @Test("canBecomeKey が true")
  func canBecomeKey() {
    let panel = EmojiPickerPanel()
    #expect(panel.canBecomeKey == true)
  }

  @Test("canBecomeMain が false")
  func canBecomeMain() {
    let panel = EmojiPickerPanel()
    #expect(panel.canBecomeMain == false)
  }

  @Test("パネルサイズが正しい")
  func panelDimensions() {
    let panel = EmojiPickerPanel()
    #expect(panel.frame.width == 380)
    #expect(panel.frame.height == 480)
  }

  @Test("dismissPanel で onDismiss コールバックが呼ばれる")
  func dismissPanelCallsCallback() {
    let panel = EmojiPickerPanel()
    var called = false
    panel.onDismiss = { called = true }
    panel.dismissPanel()
    #expect(called)
  }

  @Test("dismissPanel でコールバック未設定でもクラッシュしない")
  func dismissPanelWithoutCallback() {
    let panel = EmojiPickerPanel()
    panel.onDismiss = nil
    panel.dismissPanel()
  }

  @Test("Escape キーでパネルが閉じる")
  func escapeKeyDismissesPanel() {
    let panel = EmojiPickerPanel()
    var dismissed = false
    panel.onDismiss = { dismissed = true }

    // Escape キー (keyCode 53)
    guard
      let event = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "\u{1B}",
        charactersIgnoringModifiers: "\u{1B}",
        isARepeat: false,
        keyCode: 53
      )
    else {
      Issue.record("NSEvent の生成に失敗")
      return
    }
    panel.keyDown(with: event)
    #expect(dismissed)
  }

  @Test("パネル設定が正しい")
  func panelConfiguration() {
    let panel = EmojiPickerPanel()
    #expect(panel.isFloatingPanel == true)
    #expect(panel.hidesOnDeactivate == false)
    #expect(panel.titlebarAppearsTransparent == true)
    #expect(panel.titleVisibility == .hidden)
    #expect(panel.isMovableByWindowBackground == true)
    #expect(panel.isOpaque == false)
    #expect(panel.title == "Emoji")
  }
}
