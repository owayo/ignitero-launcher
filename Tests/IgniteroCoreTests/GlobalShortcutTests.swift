import KeyboardShortcuts
import Testing

@testable import IgniteroCore

// MARK: - Mock IME Controller

@MainActor
final class MockIMEController: IMEControlling, @unchecked Sendable {
  private(set) var switchToASCIICallCount = 0

  nonisolated func switchToASCII() {
    // In tests we call this from @MainActor context via GlobalShortcutManager,
    // so we track calls with a simple counter.
    MainActor.assumeIsolated {
      switchToASCIICallCount += 1
    }
  }
}

// MARK: - KeyboardShortcuts.Name Tests

@Suite("KeyboardShortcuts.Name Extension")
struct KeyboardShortcutsNameTests {

  @Test func toggleLauncherNameExists() {
    let name = KeyboardShortcuts.Name.toggleLauncher
    #expect(name.rawValue == "toggleLauncher")
  }

  @Test func toggleLauncherHasDefaultShortcut() {
    let name = KeyboardShortcuts.Name.toggleLauncher
    #expect(name.defaultShortcut != nil)
  }

  @Test func toggleLauncherDefaultShortcutIsOptionSpace() {
    let name = KeyboardShortcuts.Name.toggleLauncher
    guard let shortcut = name.defaultShortcut else {
      Issue.record("Default shortcut should not be nil")
      return
    }
    #expect(shortcut.key == .space)
    #expect(shortcut.modifiers == .option)
  }
}

// MARK: - GlobalShortcutManager Initialization Tests

@Suite("GlobalShortcutManager Initialization")
struct GlobalShortcutManagerInitTests {

  @MainActor
  @Test func canBeCreatedWithDependencies() {
    let windowManager = WindowManager(userDefaults: .makeTempDefaults())
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
    let windowManager = WindowManager(userDefaults: .makeTempDefaults())
    let imeController = MockIMEController()
    let manager = GlobalShortcutManager(
      windowManager: windowManager,
      imeController: imeController,
      debounceInterval: .zero
    )
    #expect(manager.windowManager === windowManager)
  }
}

// MARK: - GlobalShortcutManager Reregister Tests

@Suite("GlobalShortcutManager Reregister")
struct GlobalShortcutManagerReregisterTests {

  @MainActor
  @Test func reregisterCallsTeardownAndSetup() {
    let windowManager = WindowManager(userDefaults: .makeTempDefaults())
    let imeController = MockIMEController()
    let manager = GlobalShortcutManager(
      windowManager: windowManager,
      imeController: imeController,
      debounceInterval: .zero
    )

    // setup → reregister → handleShortcut should still work
    manager.setup()
    manager.reregister()
    manager.handleShortcut()

    #expect(windowManager.isLauncherVisible == true)
    manager.teardown()
  }

  @MainActor
  @Test func reregisterWithoutPriorSetup() {
    let windowManager = WindowManager(userDefaults: .makeTempDefaults())
    let imeController = MockIMEController()
    let manager = GlobalShortcutManager(
      windowManager: windowManager,
      imeController: imeController,
      debounceInterval: .zero
    )

    // reregister without prior setup should not crash and should work after
    manager.reregister()
    manager.handleShortcut()

    #expect(windowManager.isLauncherVisible == true)
    manager.teardown()
  }
}

// MARK: - GlobalShortcutManager Toggle + IME Logic Tests

@Suite("GlobalShortcutManager Toggle + IME Logic")
struct GlobalShortcutManagerToggleIMETests {

  @MainActor
  @Test func handleShortcutTogglesToVisible() {
    let windowManager = WindowManager(userDefaults: .makeTempDefaults())
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
    let windowManager = WindowManager(userDefaults: .makeTempDefaults())
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
    let windowManager = WindowManager(userDefaults: .makeTempDefaults())
    let imeController = MockIMEController()
    let manager = GlobalShortcutManager(
      windowManager: windowManager,
      imeController: imeController,
      debounceInterval: .zero
    )

    // First toggle: show (switchToASCII called)
    manager.handleShortcut()
    #expect(imeController.switchToASCIICallCount == 1)

    // Second toggle: hide (switchToASCII NOT called again)
    manager.handleShortcut()
    #expect(windowManager.isLauncherVisible == false)
    #expect(imeController.switchToASCIICallCount == 1)
  }

  @MainActor
  @Test func handleShortcutMultipleToggles() {
    let windowManager = WindowManager(userDefaults: .makeTempDefaults())
    let imeController = MockIMEController()
    let manager = GlobalShortcutManager(
      windowManager: windowManager,
      imeController: imeController,
      debounceInterval: .zero
    )

    // Toggle 1: show -> switchToASCII called (count=1)
    manager.handleShortcut()
    #expect(windowManager.isLauncherVisible == true)
    #expect(imeController.switchToASCIICallCount == 1)

    // Toggle 2: hide -> switchToASCII NOT called (count=1)
    manager.handleShortcut()
    #expect(windowManager.isLauncherVisible == false)
    #expect(imeController.switchToASCIICallCount == 1)

    // Toggle 3: show -> switchToASCII called (count=2)
    manager.handleShortcut()
    #expect(windowManager.isLauncherVisible == true)
    #expect(imeController.switchToASCIICallCount == 2)

    // Toggle 4: hide -> switchToASCII NOT called (count=2)
    manager.handleShortcut()
    #expect(windowManager.isLauncherVisible == false)
    #expect(imeController.switchToASCIICallCount == 2)
  }
}
