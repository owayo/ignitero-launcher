public enum EditorType: String, Codable, Sendable, CaseIterable {
  case windsurf
  case cursor
  case vscode
  case antigravity
  case zed

  /// .code-workspace ファイルの読み込みに対応しているか
  public var supportsCodeWorkspace: Bool {
    switch self {
    case .zed: false
    default: true
    }
  }

  public var displayName: String {
    switch self {
    case .windsurf: "Windsurf"
    case .cursor: "Cursor"
    case .vscode: "Visual Studio Code"
    case .antigravity: "Antigravity"
    case .zed: "Zed"
    }
  }

  /// エディタピッカーでこのエディタを選ぶショートカットキー。
  ///
  /// ピッカーのキー操作（`EditorPickerState`）とラジアル表示（`RadialPickerItemFactory`）の
  /// 両方がここを参照する。対応表を別々に持つと、片方だけ変えたときに
  /// 「表示されたキーを押しても選べない」食い違いが起きる。
  public var shortcutKey: String {
    switch self {
    case .windsurf: "w"
    case .cursor: "c"
    case .vscode: "v"
    case .antigravity: "a"
    case .zed: "z"
    }
  }

  /// ショートカットキーに対応するエディタを返す。未知のキーなら `nil`。
  ///
  /// `shortcutKey` の逆引きとして実装し、対応表を 1 か所に保つ。
  public init?(shortcutKey key: String) {
    guard let editor = Self.allCases.first(where: { $0.shortcutKey == key }) else {
      return nil
    }
    self = editor
  }
}
