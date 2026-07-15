import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts

// MARK: - ShortcutDisplayFormatter関連

/// `KeyboardShortcuts.Shortcut` を表示用文字列に変換するフォーマッタ。
///
/// `KeyboardShortcuts.Shortcut.description`（および `String(describing:)`）は
/// 内部で `"space_key".localized` を呼び、SwiftPM の `Bundle.module`（KeyboardShortcuts
/// パッケージのリソースバンドル）を遅延初期化する。`.app` 内のリソースバンドル解決に
/// 失敗する環境では `Bundle.module` の初期化で `assertionFailure` が走ってアプリ全体が
/// クラッシュする（初期ショートカットの Option+Space で必ずこのパスを通り 100% 再現）。
///
/// このフォーマッタは `Bundle.module` を一切踏まず、Carbon キーコードと
/// `NSEvent.ModifierFlags` のみから自前で文字列を組み立てる。
public enum ShortcutDisplayFormatter {

  /// `KeyboardShortcuts.Shortcut` を表示用文字列に変換する。
  ///
  /// - Parameter shortcut: 変換対象のショートカット
  /// - Returns: `⌥Space` などの表示文字列
  @MainActor
  public static func string(for shortcut: KeyboardShortcuts.Shortcut) -> String {
    modifierSymbols(shortcut.modifiers) + keySymbol(forCarbonKeyCode: shortcut.carbonKeyCode)
  }

  /// 修飾キーを macOS HIG の表示順（⌃⌥⇧⌘）で記号化する。
  public static func modifierSymbols(_ flags: NSEvent.ModifierFlags) -> String {
    var symbols = ""
    if flags.contains(.control) { symbols += "⌃" }
    if flags.contains(.option) { symbols += "⌥" }
    if flags.contains(.shift) { symbols += "⇧" }
    if flags.contains(.command) { symbols += "⌘" }
    return symbols
  }

  /// Carbon キーコードを表示文字列に変換する。
  /// 特殊キーは固定マップ、通常文字キーは UCKeyTranslate で現在のキーボードレイアウトから取得する。
  @MainActor
  public static func keySymbol(forCarbonKeyCode keyCode: Int) -> String {
    if let special = specialKeySymbol(forCarbonKeyCode: keyCode) {
      return special
    }
    return characterFromKeyCode(keyCode)?.uppercased() ?? "?"
  }

  /// 特殊キー（記号で表す制御キー・矢印キー・ファンクションキー等）の表示記号。
  /// `KeyboardShortcuts.SpecialKey.presentableDescription` と同じ表示に揃えるが、
  /// `Bundle.module` を踏まないために `Space` だけはローカライズせず固定文字で返す。
  public static func specialKeySymbol(forCarbonKeyCode keyCode: Int) -> String? {
    switch keyCode {
    case kVK_Space: "Space"
    case kVK_Return: "↩"
    case kVK_Tab: "⇥"
    case kVK_Delete: "⌫"
    case kVK_ForwardDelete: "⌦"
    case kVK_Escape: "⎋"
    case kVK_Help: "?⃝"
    case kVK_Home: "↖"
    case kVK_End: "↘"
    case kVK_PageUp: "⇞"
    case kVK_PageDown: "⇟"
    case kVK_UpArrow: "↑"
    case kVK_DownArrow: "↓"
    case kVK_LeftArrow: "←"
    case kVK_RightArrow: "→"
    case kVK_F1: "F1"
    case kVK_F2: "F2"
    case kVK_F3: "F3"
    case kVK_F4: "F4"
    case kVK_F5: "F5"
    case kVK_F6: "F6"
    case kVK_F7: "F7"
    case kVK_F8: "F8"
    case kVK_F9: "F9"
    case kVK_F10: "F10"
    case kVK_F11: "F11"
    case kVK_F12: "F12"
    case kVK_F13: "F13"
    case kVK_F14: "F14"
    case kVK_F15: "F15"
    case kVK_F16: "F16"
    case kVK_F17: "F17"
    case kVK_F18: "F18"
    case kVK_F19: "F19"
    case kVK_F20: "F20"
    case kVK_ANSI_KeypadClear: "⌧"
    case kVK_ANSI_KeypadEnter: "⌤"
    default: nil
    }
  }

  /// 通常文字キーの Carbon キーコードを現在のキーボードレイアウトの文字へ変換する。
  /// `KeyboardShortcuts.Shortcut.keyToCharacter()` と同等の UCKeyTranslate ベース実装。
  @MainActor
  public static func characterFromKeyCode(_ keyCode: Int) -> String? {
    guard
      let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
      let layoutDataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
    else {
      return nil
    }

    let layoutData = unsafeBitCast(layoutDataPointer, to: CFData.self)
    let keyLayout = unsafeBitCast(
      CFDataGetBytePtr(layoutData),
      to: UnsafePointer<UCKeyboardLayout>.self
    )
    var deadKeyState: UInt32 = 0
    let maxLength = 4
    var length = 0
    var characters = [UniChar](repeating: 0, count: maxLength)

    let error = UCKeyTranslate(
      keyLayout,
      UInt16(keyCode),
      UInt16(kUCKeyActionDisplay),
      0,
      UInt32(LMGetKbdType()),
      OptionBits(kUCKeyTranslateNoDeadKeysBit),
      &deadKeyState,
      maxLength,
      &length,
      &characters
    )

    guard error == noErr, length > 0 else { return nil }
    return String(utf16CodeUnits: characters, count: length)
  }
}
