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
}
