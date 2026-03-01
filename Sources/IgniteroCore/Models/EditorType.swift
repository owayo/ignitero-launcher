public enum EditorType: String, Codable, Sendable, CaseIterable {
  case windsurf
  case cursor
  case vscode
  case antigravity
  case zed

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
