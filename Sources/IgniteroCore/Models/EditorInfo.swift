public struct EditorInfo: Sendable, Identifiable {
  public let id: EditorType
  public let name: String
  public let appName: String
  public let installed: Bool
  public let iconPath: String?

  public init(
    id: EditorType,
    name: String,
    appName: String,
    installed: Bool,
    iconPath: String? = nil
  ) {
    self.id = id
    self.name = name
    self.appName = appName
    self.installed = installed
    self.iconPath = iconPath
  }
}
