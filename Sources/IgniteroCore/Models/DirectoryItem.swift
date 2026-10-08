import Foundation
import GRDB

public struct DirectoryItem: Codable, Sendable, Identifiable, Equatable {
  public var id: String { path }
  public let name: String
  public let path: String
  /// 開くエディタの `EditorType.rawValue`。`nil` は「既定エディタで開く」。
  public let editor: String?
  /// 登録ディレクトリの開き方が「Finder で開く」か。
  ///
  /// `editor == nil` は「既定エディタ」を意味するため、Finder 指定を `editor` だけで
  /// 表そうとすると両者を区別できず、Finder 指定のディレクトリまで既定エディタで開いてしまう。
  public let opensInFinder: Bool

  enum CodingKeys: String, CodingKey {
    case name
    case path
    case editor
    case opensInFinder = "opens_in_finder"
  }

  public init(name: String, path: String, editor: String? = nil, opensInFinder: Bool = false) {
    self.name = name
    self.path = path
    self.editor = editor
    self.opensInFinder = opensInFinder
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = try container.decode(String.self, forKey: .name)
    path = try container.decode(String.self, forKey: .path)
    editor = try container.decodeIfPresent(String.self, forKey: .editor)
    // 列が無い古いデータ（マイグレーション前の行など）は「Finder 指定なし」として読む
    opensInFinder = try container.decodeIfPresent(Bool.self, forKey: .opensInFinder) ?? false
  }
}

extension DirectoryItem: FetchableRecord, PersistableRecord {
  public static var databaseTableName: String { "directories" }
}
