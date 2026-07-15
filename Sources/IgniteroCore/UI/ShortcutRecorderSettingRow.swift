import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts
import SwiftUI

// MARK: - ShortcutRecorderSettingRow関連

/// `KeyboardShortcuts.Recorder` を使わずにショートカットを記録する設定行。
///
/// SwiftPM の依存リソースバンドルが `.app` 内で解決できない環境でも設定画面を開けるよう、
/// 表示文言とキー記録処理をアプリ側で持つ。
struct ShortcutRecorderSettingRow: View {

  @State private var shortcut: KeyboardShortcuts.Shortcut?

  init() {
    self._shortcut = State(initialValue: Self.currentShortcut())
  }

  var body: some View {
    LabeledContent("ランチャー表示") {
      HStack(spacing: 8) {
        ShortcutRecorderView(name: .toggleLauncher, shortcut: $shortcut)
          .frame(width: 150, height: 28)

        Button("デフォルトに戻す") {
          KeyboardShortcuts.reset(.toggleLauncher)
          shortcut = Self.currentShortcut()
        }
      }
    }
  }

  private static func currentShortcut() -> KeyboardShortcuts.Shortcut? {
    KeyboardShortcuts.getShortcut(for: .toggleLauncher)
      ?? KeyboardShortcuts.Name.toggleLauncher.initialShortcut
  }
}

// MARK: - ShortcutRecorderView関連

private struct ShortcutRecorderView: NSViewRepresentable {
  let name: KeyboardShortcuts.Name
  @Binding var shortcut: KeyboardShortcuts.Shortcut?

  func makeCoordinator() -> Coordinator {
    Coordinator(name: name, shortcut: $shortcut)
  }

  func makeNSView(context: Context) -> ShortcutRecorderButton {
    let button = ShortcutRecorderButton()
    button.shortcut = shortcut
    button.onShortcutChange = { newShortcut in
      context.coordinator.setShortcut(newShortcut)
    }
    return button
  }

  func updateNSView(_ nsView: ShortcutRecorderButton, context: Context) {
    context.coordinator.shortcut = $shortcut
    nsView.shortcut = shortcut
    nsView.onShortcutChange = { newShortcut in
      context.coordinator.setShortcut(newShortcut)
    }
  }

  @MainActor
  final class Coordinator {
    let name: KeyboardShortcuts.Name
    var shortcut: Binding<KeyboardShortcuts.Shortcut?>

    init(name: KeyboardShortcuts.Name, shortcut: Binding<KeyboardShortcuts.Shortcut?>) {
      self.name = name
      self.shortcut = shortcut
    }

    func setShortcut(_ newShortcut: KeyboardShortcuts.Shortcut?) {
      KeyboardShortcuts.setShortcut(newShortcut, for: name)
      shortcut.wrappedValue = KeyboardShortcuts.getShortcut(for: name) ?? name.initialShortcut
    }
  }
}

// MARK: - ShortcutRecorderButton関連

@MainActor
private final class ShortcutRecorderButton: NSButton {

  var shortcut: KeyboardShortcuts.Shortcut? {
    didSet {
      updateTitle()
    }
  }

  var onShortcutChange: ((KeyboardShortcuts.Shortcut?) -> Void)?

  private var isRecording = false

  override var acceptsFirstResponder: Bool { true }
  override var canBecomeKeyView: Bool { true }
  override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 28) }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    bezelStyle = .rounded
    setButtonType(.momentaryPushIn)
    focusRingType = .default
    target = self
    action = #selector(startRecordingFromAction)
    updateTitle()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    startRecording()
  }

  override func keyDown(with event: NSEvent) {
    guard isRecording else {
      super.keyDown(with: event)
      return
    }

    switch Int(event.keyCode) {
    case kVK_Escape:
      endRecording()
      return
    case kVK_Delete, kVK_ForwardDelete:
      NSSound.beep()
      return
    default:
      break
    }

    guard isValidShortcutEvent(event), let shortcut = KeyboardShortcuts.Shortcut(event: event)
    else {
      NSSound.beep()
      return
    }

    if let menuItem = firstMenuItem(using: shortcut) {
      showAlert(title: "このショートカットはメニュー「\(menuItem.title)」で使用されています")
      return
    }

    if shortcut.isTakenBySystem {
      showAlert(title: "このショートカットはシステムで使用されています")
      return
    }

    self.shortcut = shortcut
    onShortcutChange?(shortcut)
    endRecording()
  }

  override func resignFirstResponder() -> Bool {
    if isRecording {
      isRecording = false
      updateTitle()
    }
    return super.resignFirstResponder()
  }

  @objc private func startRecordingFromAction() {
    startRecording()
  }

  private func startRecording() {
    isRecording = true
    updateTitle()
  }

  private func endRecording() {
    guard isRecording else { return }
    isRecording = false
    updateTitle()
    window?.makeFirstResponder(nil)
  }

  private func updateTitle() {
    if isRecording {
      title = "キー入力待ち..."
    } else if let shortcut {
      // `String(describing:)` は `KeyboardShortcuts.Shortcut.description` を呼ぶが、
      // 内部で `"space_key".localized` 経由で `Bundle.module`（KeyboardShortcuts の
      // SwiftPM リソースバンドル）を初期化する。`.app` 内のリソースバンドル解決に
      // 失敗する環境では `assertionFailure` でアプリ全体がクラッシュする
      // （既定の Option+Space では必ず .space ケースを通り 100% 再現）。
      // ここでは `Bundle.module` を一切踏まない自前フォーマッタを使う。
      title = ShortcutDisplayFormatter.string(for: shortcut)
    } else {
      title = "未設定"
    }
    toolTip = "クリックしてショートカットを記録"
    setAccessibilityLabel("ランチャー表示ショートカット")
  }

  private func isValidShortcutEvent(_ event: NSEvent) -> Bool {
    let modifiers = Self.normalizedModifiers(from: event.modifierFlags)
    if Self.functionKeyCodes.contains(event.keyCode) {
      return true
    }
    return !modifiers.subtracting(.shift).isEmpty
  }

  private func firstMenuItem(using shortcut: KeyboardShortcuts.Shortcut) -> NSMenuItem? {
    guard let keyEquivalent = shortcut.nsMenuItemKeyEquivalent,
      let mainMenu = NSApp.mainMenu
    else {
      return nil
    }

    return Self.firstMenuItem(in: mainMenu) { item in
      var itemKeyEquivalent = item.keyEquivalent
      var itemModifiers = Self.normalizedModifiers(from: item.keyEquivalentModifierMask)
      if shortcut.modifiers.contains(.shift), itemKeyEquivalent.lowercased() != itemKeyEquivalent {
        itemKeyEquivalent = itemKeyEquivalent.lowercased()
        itemModifiers.insert(.shift)
      }
      return itemKeyEquivalent == keyEquivalent
        && itemModifiers == Self.normalizedModifiers(from: shortcut.modifiers)
    }
  }

  private func showAlert(title: String) {
    endRecording()
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = title
    alert.addButton(withTitle: "OK")
    alert.runModal()
    window?.makeFirstResponder(self)
    startRecording()
  }

  private static func firstMenuItem(
    in menu: NSMenu,
    matching predicate: (NSMenuItem) -> Bool
  ) -> NSMenuItem? {
    for item in menu.items {
      if predicate(item) {
        return item
      }
      if let submenu = item.submenu,
        let match = firstMenuItem(in: submenu, matching: predicate)
      {
        return match
      }
    }
    return nil
  }

  private static func normalizedModifiers(
    from flags: NSEvent.ModifierFlags
  ) -> NSEvent.ModifierFlags {
    flags
      .intersection(.deviceIndependentFlagsMask)
      .subtracting([.capsLock, .numericPad, .function])
  }

  private static let functionKeyCodes: Set<UInt16> = [
    UInt16(kVK_F1),
    UInt16(kVK_F2),
    UInt16(kVK_F3),
    UInt16(kVK_F4),
    UInt16(kVK_F5),
    UInt16(kVK_F6),
    UInt16(kVK_F7),
    UInt16(kVK_F8),
    UInt16(kVK_F9),
    UInt16(kVK_F10),
    UInt16(kVK_F11),
    UInt16(kVK_F12),
    UInt16(kVK_F13),
    UInt16(kVK_F14),
    UInt16(kVK_F15),
    UInt16(kVK_F16),
    UInt16(kVK_F17),
    UInt16(kVK_F18),
    UInt16(kVK_F19),
    UInt16(kVK_F20),
  ]
}
