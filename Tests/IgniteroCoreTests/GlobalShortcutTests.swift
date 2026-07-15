import KeyboardShortcuts
import Testing

@testable import IgniteroCore

// MARK: - IMEコントローラーのモック

@MainActor
final class MockIMEController: IMEControlling, @unchecked Sendable {
  private(set) var switchToASCIICallCount = 0

  nonisolated func switchToASCII() {
    // テストではGlobalShortcutManagerを介して@MainActorコンテキストから呼び出すため、
    // 単純なカウンターで呼び出し回数を追跡する。
    MainActor.assumeIsolated {
      switchToASCIICallCount += 1
    }
  }
}

// MARK: - KeyboardShortcuts.Name テスト

@Suite("KeyboardShortcuts.Name Extension")
struct KeyboardShortcutsNameTests {

  @Test func toggleLauncherNameExists() {
    let name = KeyboardShortcuts.Name.toggleLauncher
    #expect(name.rawValue == "toggleLauncher")
  }

  @Test func toggleLauncherHasInitialShortcut() {
    let name = KeyboardShortcuts.Name.toggleLauncher
    #expect(name.initialShortcut != nil)
  }

  @Test func toggleLauncherInitialShortcutIsOptionSpace() {
    let name = KeyboardShortcuts.Name.toggleLauncher
    guard let shortcut = name.initialShortcut else {
      Issue.record("Initial shortcut should not be nil")
      return
    }
    #expect(shortcut.key == .space)
    #expect(shortcut.modifiers == .option)
  }
}

// MARK: - GlobalShortcutManager 初期化 テスト

@Suite("GlobalShortcutManager Initialization")
struct GlobalShortcutManagerInitTests {

  @MainActor
  @Test func canBeCreatedWithDependencies() {
    let windowManager = WindowManager()
    let imeController = MockIMEController()
    let manager = GlobalShortcutManager(
      windowManager: windowManager,
      imeController: imeController,
      debounceInterval: .zero
    )
    #expect(type(of: manager) == GlobalShortcutManager.self)
  }

  @MainActor
  @Test func hasWindowManagerReference() {
    let windowManager = WindowManager()
    let imeController = MockIMEController()
    let manager = GlobalShortcutManager(
      windowManager: windowManager,
      imeController: imeController,
      debounceInterval: .zero
    )
    #expect(manager.windowManager === windowManager)
  }
}

// MARK: - GlobalShortcutManager再登録のテスト

@Suite("GlobalShortcutManager Reregister")
struct GlobalShortcutManagerReregisterTests {

  @MainActor
  @Test func reregisterCallsTeardownAndSetup() {
    let windowManager = WindowManager()
    let imeController = MockIMEController()
    let manager = GlobalShortcutManager(
      windowManager: windowManager,
      imeController: imeController,
      debounceInterval: .zero
    )

    // セットアップ→再登録の後もhandleShortcutが動作すること
    manager.setup()
    manager.reregister()
    manager.handleShortcut()

    #expect(windowManager.isLauncherVisible == true)
    manager.teardown()
  }

  @MainActor
  @Test func reregisterWithoutPriorSetup() {
    let windowManager = WindowManager()
    let imeController = MockIMEController()
    let manager = GlobalShortcutManager(
      windowManager: windowManager,
      imeController: imeController,
      debounceInterval: .zero
    )

    // 事前のセットアップなしで再登録してもクラッシュせず、その後も動作すること
    manager.reregister()
    manager.handleShortcut()

    #expect(windowManager.isLauncherVisible == true)
    manager.teardown()
  }
}

// MARK: - GlobalShortcutManager表示切替とIMEロジックのテスト

@Suite("GlobalShortcutManager Toggle + IME Logic")
struct GlobalShortcutManagerToggleIMETests {

  @MainActor
  @Test func handleShortcutTogglesToVisible() {
    let windowManager = WindowManager()
    let imeController = MockIMEController()
    let manager = GlobalShortcutManager(
      windowManager: windowManager,
      imeController: imeController,
      debounceInterval: .zero
    )
    #expect(windowManager.isLauncherVisible == false)

    manager.handleShortcut()

    #expect(windowManager.isLauncherVisible == true)
  }

  @MainActor
  @Test func handleShortcutCallsSwitchToASCIIWhenBecomingVisible() {
    let windowManager = WindowManager()
    let imeController = MockIMEController()
    let manager = GlobalShortcutManager(
      windowManager: windowManager,
      imeController: imeController,
      debounceInterval: .zero
    )

    manager.handleShortcut()

    #expect(windowManager.isLauncherVisible == true)
    #expect(imeController.switchToASCIICallCount == 1)
  }

  @MainActor
  @Test func handleShortcutDoesNotCallSwitchToASCIIWhenHiding() {
    let windowManager = WindowManager()
    let imeController = MockIMEController()
    let manager = GlobalShortcutManager(
      windowManager: windowManager,
      imeController: imeController,
      debounceInterval: .zero
    )

    // 1回目の切り替え: 表示（switchToASCIIを呼び出す）
    manager.handleShortcut()
    #expect(imeController.switchToASCIICallCount == 1)

    // 2回目の切り替え: 非表示（switchToASCIIを再度呼び出さない）
    manager.handleShortcut()
    #expect(windowManager.isLauncherVisible == false)
    #expect(imeController.switchToASCIICallCount == 1)
  }

  @MainActor
  @Test func handleShortcutMultipleToggles() {
    let windowManager = WindowManager()
    let imeController = MockIMEController()
    let manager = GlobalShortcutManager(
      windowManager: windowManager,
      imeController: imeController,
      debounceInterval: .zero
    )

    // 切り替え1: 表示→switchToASCIIを呼び出す（count=1）
    manager.handleShortcut()
    #expect(windowManager.isLauncherVisible == true)
    #expect(imeController.switchToASCIICallCount == 1)

    // 切り替え2: 非表示→switchToASCIIを呼び出さない（count=1）
    manager.handleShortcut()
    #expect(windowManager.isLauncherVisible == false)
    #expect(imeController.switchToASCIICallCount == 1)

    // 切り替え3: 表示→switchToASCIIを呼び出す（count=2）
    manager.handleShortcut()
    #expect(windowManager.isLauncherVisible == true)
    #expect(imeController.switchToASCIICallCount == 2)

    // 切り替え4: 非表示→switchToASCIIを呼び出さない（count=2）
    manager.handleShortcut()
    #expect(windowManager.isLauncherVisible == false)
    #expect(imeController.switchToASCIICallCount == 2)
  }
}
