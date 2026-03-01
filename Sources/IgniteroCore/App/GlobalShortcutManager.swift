import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts
import os

// MARK: - Shortcut Name Definition

extension KeyboardShortcuts.Name {
  /// ランチャーの表示/非表示を切り替えるグローバルショートカット名。
  /// デフォルトは Option+Space（⌥Space）。
  public static let toggleLauncher = Self(
    "toggleLauncher",
    default: .init(.space, modifiers: .option)
  )
}

// MARK: - Carbon Hot Key C Callback

/// Carbon イベントハンドラ。`@convention(c)` 互換のトップレベル関数。
private func carbonHotKeyEventHandler(
  _: EventHandlerCallRef?,
  event: EventRef?,
  _: UnsafeMutableRawPointer?
) -> OSStatus {
  guard let event else { return OSStatus(eventNotHandledErr) }

  var hotKeyID = EventHotKeyID()
  let err = GetEventParameter(
    event,
    UInt32(kEventParamDirectObject),
    UInt32(typeEventHotKeyID),
    nil,
    MemoryLayout<EventHotKeyID>.size,
    nil,
    &hotKeyID
  )
  guard err == noErr else { return err }

  guard hotKeyID.signature == GlobalShortcutManager.hotKeySignature else {
    return OSStatus(eventNotHandledErr)
  }

  DispatchQueue.main.async {
    MainActor.assumeIsolated {
      GlobalShortcutManager.handleHotKeyEvent()
    }
  }

  return noErr
}

// MARK: - GlobalShortcutManager

/// グローバルキーボードショートカットを管理するマネージャ。
///
/// Carbon `RegisterEventHotKey` を直接使用して Option+Space ショートカットを登録し、
/// ランチャーの表示/非表示トグルと IME の英数切り替えを行う。
@MainActor
public final class GlobalShortcutManager {

  // MARK: - Constants

  /// Carbon hotkey signature "IGNT"
  nonisolated static let hotKeySignature: UInt32 = 0x4947_4E54

  // MARK: - Properties

  /// ランチャーウィンドウの表示/非表示を管理する WindowManager
  public let windowManager: WindowManager

  /// IME 制御を行うコントローラ
  private let imeController: any IMEControlling

  /// Carbon hotkey 参照
  private var carbonHotKeyRef: EventHotKeyRef?

  /// Carbon イベントハンドラ参照
  private var carbonEventHandlerRef: EventHandlerRef?

  /// ショートカット変更通知の監視トークン
  private var shortcutChangeObserver: (any NSObjectProtocol)?

  /// C コールバックから MainActor にブリッジするための static 参照
  nonisolated(unsafe) private static weak var activeInstance: GlobalShortcutManager?

  /// キーリピート抑制用のタイムスタンプ
  private var lastShortcutTime: ContinuousClock.Instant = .now - .milliseconds(500)

  /// キーリピート抑制の最小間隔
  private let debounceInterval: Duration

  private static let logger = Logger(
    subsystem: "com.ignitero.launcher", category: "GlobalShortcut")

  // MARK: - Initialization

  /// GlobalShortcutManager を初期化する。
  ///
  /// - Parameters:
  ///   - windowManager: ランチャーウィンドウの管理を行う WindowManager
  ///   - imeController: IME の切り替えを行うコントローラ
  ///   - debounceInterval: キーリピート抑制の最小間隔。テスト時は `.zero` を指定可能。
  public init(
    windowManager: WindowManager,
    imeController: any IMEControlling,
    debounceInterval: Duration = .milliseconds(300)
  ) {
    self.windowManager = windowManager
    self.imeController = imeController
    self.debounceInterval = debounceInterval
  }

  // MARK: - Static Callback Entry Point

  /// Carbon イベントハンドラから呼び出されるエントリポイント。
  static func handleHotKeyEvent() {
    activeInstance?.handleShortcut()
  }

  // MARK: - Setup / Teardown

  /// Carbon API を使用してグローバルショートカットを登録する。
  ///
  /// Option+Space が押されたとき、`handleShortcut()` を呼び出す。
  public func setup() {
    Self.activeInstance = self

    // KeyboardShortcuts の設定からショートカットを取得
    let shortcut =
      KeyboardShortcuts.Name.toggleLauncher.shortcut
      ?? KeyboardShortcuts.Name.toggleLauncher.defaultShortcut

    guard let shortcut else {
      Self.logger.error("No shortcut configured for toggleLauncher")
      return
    }

    let keyCode = UInt32(shortcut.carbonKeyCode)
    let modifiers = UInt32(shortcut.carbonModifiers)

    Self.logger.notice(
      "Registering Carbon hotkey: keyCode=\(keyCode), modifiers=\(modifiers)")

    // Carbon イベントハンドラをインストール
    var eventTypes = [
      EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard),
        eventKind: UInt32(kEventHotKeyPressed)
      )
    ]

    let handlerStatus = InstallEventHandler(
      GetApplicationEventTarget(),
      carbonHotKeyEventHandler,
      eventTypes.count,
      &eventTypes,
      nil,
      &carbonEventHandlerRef
    )

    Self.logger.notice(
      "InstallEventHandler status: \(handlerStatus) (0=success)")

    guard handlerStatus == noErr else {
      Self.logger.error(
        "Failed to install Carbon event handler: \(handlerStatus)")
      return
    }

    // ホットキーを登録
    let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: 1)
    let regStatus = RegisterEventHotKey(
      keyCode,
      modifiers,
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &carbonHotKeyRef
    )

    Self.logger.notice(
      "RegisterEventHotKey status: \(regStatus) (0=success)")

    if regStatus != noErr {
      Self.logger.error("Failed to register Carbon hotkey: \(regStatus)")
    }

    // ショートカット変更通知を監視
    shortcutChangeObserver = NotificationCenter.default.addObserver(
      forName: .init("KeyboardShortcuts_shortcutByNameDidChange"),
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard
        let name = notification.userInfo?["name"] as? KeyboardShortcuts.Name,
        name == .toggleLauncher
      else { return }
      MainActor.assumeIsolated {
        self?.reregister()
      }
    }
  }

  /// グローバルショートカットのハンドラを解除する。
  public func teardown() {
    if let observer = shortcutChangeObserver {
      NotificationCenter.default.removeObserver(observer)
      shortcutChangeObserver = nil
    }
    if let ref = carbonHotKeyRef {
      UnregisterEventHotKey(ref)
      carbonHotKeyRef = nil
    }
    if let ref = carbonEventHandlerRef {
      RemoveEventHandler(ref)
      carbonEventHandlerRef = nil
    }
    Self.activeInstance = nil
  }

  /// Carbon ホットキーを再登録する。
  ///
  /// ショートカット変更時に `teardown()` → `setup()` を呼び出し、
  /// 新しいキーの組み合わせで Carbon ホットキーを再登録する。
  public func reregister() {
    Self.logger.notice("Reregistering Carbon hotkey due to shortcut change")
    teardown()
    setup()
  }

  // MARK: - Handler

  /// ショートカット発火時の処理。
  ///
  /// `windowManager.toggleLauncher()` を呼び出し、
  /// ランチャーが表示状態になった場合は `imeController.switchToASCII()` で英数入力に切り替える。
  public func handleShortcut() {
    // キーリピートによる連射を抑制
    let now = ContinuousClock.now
    guard now - lastShortcutTime >= debounceInterval else { return }
    lastShortcutTime = now

    windowManager.toggleLauncher()
    if windowManager.isLauncherVisible {
      imeController.switchToASCII()
    }
  }
}
