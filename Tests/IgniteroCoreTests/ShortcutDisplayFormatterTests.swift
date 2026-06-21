import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts
import Testing

@testable import IgniteroCore

// MARK: - ShortcutDisplayFormatter Tests

@MainActor
@Suite("ShortcutDisplayFormatter")
struct ShortcutDisplayFormatterTests {

  // MARK: - 設定画面クラッシュの回帰テスト

  /// 過去のクラッシュ回帰テスト: 既定ショートカット Option+Space で
  /// 設定画面を開いた瞬間にクラッシュしないこと。
  ///
  /// 原因（2026-06-21）:
  /// `String(describing: shortcut)` → `KeyboardShortcuts.Shortcut.description`
  /// → `SpecialKey.presentableDescription` の `.space` ケースで
  /// `"space_key".localized` を呼び、SwiftPM の `Bundle.module` 初期化が
  /// `.app` 内のリソース解決に失敗して `assertionFailure` で SIGTRAP。
  ///
  /// このテストは Bundle.module を踏まないフォーマッタが Option+Space を
  /// "⌥Space" として返すことで、回避が機能していることを保証する。
  @Test("Option+Space をクラッシュせず ⌥Space と表示する")
  func 既定ショートカットを安全にフォーマットする() {
    let shortcut = KeyboardShortcuts.Shortcut(.space, modifiers: [.option])
    let formatted = ShortcutDisplayFormatter.string(for: shortcut)
    #expect(formatted == "⌥Space")
  }

  // MARK: - 修飾キーの表示順

  @Test("修飾キーは macOS HIG の表示順 ⌃⌥⇧⌘ で並ぶ")
  func 修飾キーは固定順序で並ぶ() {
    let flags: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
    let symbols = ShortcutDisplayFormatter.modifierSymbols(flags)
    #expect(symbols == "⌃⌥⇧⌘")
  }

  @Test("修飾キーがない場合は空文字")
  func 修飾キーなしは空文字() {
    let symbols = ShortcutDisplayFormatter.modifierSymbols([])
    #expect(symbols == "")
  }

  @Test("単一修飾キー: control のみ")
  func 単一controlは丸印() {
    let symbols = ShortcutDisplayFormatter.modifierSymbols([.control])
    #expect(symbols == "⌃")
  }

  @Test("単一修飾キー: command のみ")
  func 単一commandはコマンド印() {
    let symbols = ShortcutDisplayFormatter.modifierSymbols([.command])
    #expect(symbols == "⌘")
  }

  // MARK: - 特殊キーの記号化

  @Test("特殊キーは固定記号にマップされる")
  func 特殊キー記号が正しい() {
    let cases: [(Int, String)] = [
      (kVK_Space, "Space"),
      (kVK_Return, "↩"),
      (kVK_Tab, "⇥"),
      (kVK_Delete, "⌫"),
      (kVK_ForwardDelete, "⌦"),
      (kVK_Escape, "⎋"),
      (kVK_Home, "↖"),
      (kVK_End, "↘"),
      (kVK_PageUp, "⇞"),
      (kVK_PageDown, "⇟"),
      (kVK_UpArrow, "↑"),
      (kVK_DownArrow, "↓"),
      (kVK_LeftArrow, "←"),
      (kVK_RightArrow, "→"),
      (kVK_F1, "F1"),
      (kVK_F12, "F12"),
      (kVK_F20, "F20"),
    ]
    for (keyCode, expected) in cases {
      let symbol = ShortcutDisplayFormatter.specialKeySymbol(forCarbonKeyCode: keyCode)
      #expect(
        symbol == expected, "keyCode=\(keyCode) expected=\(expected) actual=\(symbol ?? "nil")")
    }
  }

  @Test("特殊キーでないキーコードは nil")
  func 通常文字キーは特殊記号として返さない() {
    #expect(ShortcutDisplayFormatter.specialKeySymbol(forCarbonKeyCode: kVK_ANSI_A) == nil)
    #expect(ShortcutDisplayFormatter.specialKeySymbol(forCarbonKeyCode: kVK_ANSI_1) == nil)
  }

  // MARK: - 組み合わせ表示

  @Test("修飾キー＋特殊キーの組み合わせ表示")
  func 修飾キー付きの特殊キー表示() {
    let escape = KeyboardShortcuts.Shortcut(.escape, modifiers: [.command])
    #expect(ShortcutDisplayFormatter.string(for: escape) == "⌘⎋")

    let f1 = KeyboardShortcuts.Shortcut(.f1, modifiers: [.control, .shift])
    #expect(ShortcutDisplayFormatter.string(for: f1) == "⌃⇧F1")
  }

  // MARK: - Bundle.module 非依存性の間接保証

  /// `KeyboardShortcuts.SpecialKey` 内で `"space_key".localized` を呼ぶのは
  /// `.space` 1 ケースのみ（KeyboardShortcuts 3.0.1 時点）。本テストは
  /// Space を含む 32 種類の特殊キー全てが Bundle.module を踏むパスに入らず
  /// 例外なくフォーマットできることを確認する。フォーマッタが将来
  /// `Shortcut.description` を呼ぶ実装に戻ると、このテストが
  /// `assertionFailure` で落ちて回帰を検知する。
  @Test("全特殊キーの組み合わせをフォーマットしても Bundle.module を踏まない")
  func 全特殊キーをフォーマットしてもクラッシュしない() {
    let specialKeys: [KeyboardShortcuts.Key] = [
      .space, .return, .tab,
      .delete, .deleteForward, .escape,
      .home, .end, .pageUp, .pageDown,
      .upArrow, .downArrow, .leftArrow, .rightArrow,
      .f1, .f2, .f3, .f4, .f5, .f6,
      .f7, .f8, .f9, .f10, .f11, .f12,
      .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20,
    ]
    for key in specialKeys {
      let shortcut = KeyboardShortcuts.Shortcut(key, modifiers: [.option])
      let formatted = ShortcutDisplayFormatter.string(for: shortcut)
      #expect(!formatted.isEmpty, "key=\(key.rawValue) format result must not be empty")
    }
  }
}
