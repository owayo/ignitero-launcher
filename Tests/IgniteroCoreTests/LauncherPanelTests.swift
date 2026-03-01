import AppKit
import SwiftUI
import Testing

@testable import IgniteroCore

/// テスト用の SwiftUI ビュー
private struct TestView: View {
  var body: some View {
    Text("Hello")
  }
}

@Suite("LauncherPanel Tests")
struct LauncherPanelTests {

  // MARK: - Style Mask

  @Test @MainActor func styleMaskIncludesBorderless() {
    let panel = LauncherPanel()
    #expect(panel.styleMask.contains(.borderless))
  }

  @Test @MainActor func styleMaskIncludesNonactivatingPanel() {
    let panel = LauncherPanel()
    #expect(panel.styleMask.contains(.nonactivatingPanel))
  }

  @Test @MainActor func styleMaskIncludesTitled() {
    let panel = LauncherPanel()
    #expect(panel.styleMask.contains(.titled))
  }

  @Test @MainActor func styleMaskIncludesFullSizeContentView() {
    let panel = LauncherPanel()
    #expect(panel.styleMask.contains(.fullSizeContentView))
  }

  // MARK: - Panel Properties

  @Test @MainActor func isFloatingPanelIsTrue() {
    let panel = LauncherPanel()
    #expect(panel.isFloatingPanel == true)
  }

  @Test @MainActor func levelIsStatusBar() {
    let panel = LauncherPanel()
    #expect(panel.level == .statusBar)
  }

  @Test @MainActor func hidesOnDeactivateIsFalse() {
    let panel = LauncherPanel()
    #expect(panel.hidesOnDeactivate == false)
  }

  @Test @MainActor func hasShadowIsTrue() {
    let panel = LauncherPanel()
    #expect(panel.hasShadow == true)
  }

  // MARK: - Collection Behavior

  @Test @MainActor func collectionBehaviorIncludesCanJoinAllSpaces() {
    let panel = LauncherPanel()
    #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
  }

  @Test @MainActor func collectionBehaviorIncludesFullScreenAuxiliary() {
    let panel = LauncherPanel()
    #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
  }

  @Test @MainActor func collectionBehaviorIncludesTransient() {
    let panel = LauncherPanel()
    #expect(panel.collectionBehavior.contains(.transient))
  }

  @Test @MainActor func collectionBehaviorIncludesIgnoresCycle() {
    let panel = LauncherPanel()
    #expect(panel.collectionBehavior.contains(.ignoresCycle))
  }

  // MARK: - Key / Main Behavior

  @Test @MainActor func canBecomeKeyReturnsTrue() {
    let panel = LauncherPanel()
    #expect(panel.canBecomeKey == true)
  }

  @Test @MainActor func canBecomeMainReturnsFalse() {
    let panel = LauncherPanel()
    #expect(panel.canBecomeMain == false)
  }

  // MARK: - Titlebar Settings

  @Test @MainActor func titlebarAppearsTransparentIsTrue() {
    let panel = LauncherPanel()
    #expect(panel.titlebarAppearsTransparent == true)
  }

  @Test @MainActor func titleVisibilityIsHidden() {
    let panel = LauncherPanel()
    #expect(panel.titleVisibility == .hidden)
  }

  // MARK: - Movement & Appearance

  @Test @MainActor func isMovableByWindowBackgroundIsTrue() {
    let panel = LauncherPanel()
    #expect(panel.isMovableByWindowBackground == true)
  }

  @Test @MainActor func backgroundColorIsClear() {
    let panel = LauncherPanel()
    #expect(panel.backgroundColor == .clear)
  }

  @Test @MainActor func isOpaqueIsFalse() {
    let panel = LauncherPanel()
    #expect(panel.isOpaque == false)
  }

  // MARK: - SwiftUI Content View

  @Test @MainActor func setContentViewWrapsSwiftUIInNSHostingView() {
    let panel = LauncherPanel()
    panel.setContentView(TestView())
    #expect(panel.contentView is NSHostingView<TestView>)
  }
}
