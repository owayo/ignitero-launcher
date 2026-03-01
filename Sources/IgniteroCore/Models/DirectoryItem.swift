import Foundation
import GRDB

public struct DirectoryItem: Codable, Sendable, Identifiable, Equatable {
  public var id: String { path }
  public let name: String
  public let path: String
  public let editor: String?

  enum CodingKeys: String, CodingKey {
    case name
    case path
    case editor
  }

  public init(name: String, path: String, editor: String? = nil) {
    self.name = name
    self.path = path
    self.editor = editor
  }
}

extension DirectoryItem: FetchableRecord, PersistableRecord {
  public static var databaseTableName: String { "directories" }
}
