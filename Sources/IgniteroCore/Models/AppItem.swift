import Foundation
import GRDB

public struct AppItem: Codable, Sendable, Identifiable, Equatable {
  public var id: String { path }
  public let name: String
  public let path: String
  public let iconPath: String?
  public let originalName: String?

  enum CodingKeys: String, CodingKey {
    case name
    case path
    case iconPath = "icon_path"
    case originalName = "original_name"
  }

  public init(name: String, path: String, iconPath: String? = nil, originalName: String? = nil) {
    self.name = name
    self.path = path
    self.iconPath = iconPath
    self.originalName = originalName
  }
}

extension AppItem: FetchableRecord, PersistableRecord {
  public static var databaseTableName: String { "apps" }
}
