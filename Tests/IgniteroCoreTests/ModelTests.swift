import Foundation
import Testing

@testable import IgniteroCore

// MARK: - AppItem Tests

@Suite("AppItem Model")
struct AppItemTests {

  @Test func idIsPath() {
    let item = AppItem(name: "Xcode", path: "/Applications/Xcode.app")
    #expect(item.id == "/Applications/Xcode.app")
  }

  @Test func optionalFieldsDefaultToNil() {
    let item = AppItem(name: "Xcode", path: "/Applications/Xcode.app")
    #expect(item.iconPath == nil)
    #expect(item.originalName == nil)
  }

  @Test func optionalFieldsCanBeSet() {
    let item = AppItem(
      name: "Xcode",
      path: "/Applications/Xcode.app",
      iconPath: "/icons/xcode.png",
      originalName: "Xcode.app"
    )
    #expect(item.iconPath == "/icons/xcode.png")
    #expect(item.originalName == "Xcode.app")
  }

  @Test func equatableByAllFields() {
    let a = AppItem(
      name: "Xcode", path: "/Applications/Xcode.app", iconPath: nil, originalName: nil)
    let b = AppItem(
      name: "Xcode", path: "/Applications/Xcode.app", iconPath: nil, originalName: nil)
    #expect(a == b)
  }

  @Test func notEqualWhenPathDiffers() {
    let a = AppItem(name: "Xcode", path: "/Applications/Xcode.app")
    let b = AppItem(name: "Xcode", path: "/Applications/Xcode-beta.app")
    #expect(a != b)
  }

  @Test func codableRoundTrip() throws {
    let original = AppItem(
      name: "Terminal",
      path: "/Applications/Utilities/Terminal.app",
      iconPath: "/icons/terminal.png",
      originalName: "Terminal.app"
    )
    let encoder = JSONEncoder()
    let data = try encoder.encode(original)
    let decoder = JSONDecoder()
    let decoded = try decoder.decode(AppItem.self, from: data)
    #expect(decoded == original)
  }

  @Test func codingKeysUsesSnakeCase() throws {
    let item = AppItem(
      name: "Test",
      path: "/test",
      iconPath: "/icon",
      originalName: "Original"
    )
    let data = try JSONEncoder().encode(item)
    let json = String(data: data, encoding: .utf8)!
    #expect(json.contains("icon_path"))
    #expect(json.contains("original_name"))
    #expect(!json.contains("iconPath"))
    #expect(!json.contains("originalName"))
  }

  @Test func databaseTableName() {
    #expect(AppItem.databaseTableName == "apps")
  }

  @Test func conformsToSendable() {
    let item: any Sendable = AppItem(name: "Test", path: "/test")
    #expect(item is AppItem)
  }
}

// MARK: - DirectoryItem Tests

@Suite("DirectoryItem Model")
struct DirectoryItemTests {

  @Test func idIsPath() {
    let item = DirectoryItem(name: "project", path: "/Users/dev/project")
    #expect(item.id == "/Users/dev/project")
  }

  @Test func editorDefaultsToNil() {
    let item = DirectoryItem(name: "project", path: "/Users/dev/project")
    #expect(item.editor == nil)
  }

  @Test func editorCanBeSet() {
    let item = DirectoryItem(name: "project", path: "/Users/dev/project", editor: "cursor")
    #expect(item.editor == "cursor")
  }

  @Test func equatableByAllFields() {
    let a = DirectoryItem(name: "project", path: "/Users/dev/project", editor: "vscode")
    let b = DirectoryItem(name: "project", path: "/Users/dev/project", editor: "vscode")
    #expect(a == b)
  }

  @Test func notEqualWhenEditorDiffers() {
    let a = DirectoryItem(name: "project", path: "/path", editor: "vscode")
    let b = DirectoryItem(name: "project", path: "/path", editor: "cursor")
    #expect(a != b)
  }

  @Test func codableRoundTrip() throws {
    let original = DirectoryItem(name: "myapp", path: "/Users/dev/myapp", editor: "windsurf")
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(DirectoryItem.self, from: data)
    #expect(decoded == original)
  }

  @Test func databaseTableName() {
    #expect(DirectoryItem.databaseTableName == "directories")
  }

  @Test func conformsToSendable() {
    let item: any Sendable = DirectoryItem(name: "test", path: "/test")
    #expect(item is DirectoryItem)
  }
}

// MARK: - EditorType Tests

@Suite("EditorType DisplayName")
struct EditorTypeDisplayNameTests {

  @Test func windsurfDisplayName() {
    #expect(EditorType.windsurf.displayName == "Windsurf")
  }

  @Test func cursorDisplayName() {
    #expect(EditorType.cursor.displayName == "Cursor")
  }

  @Test func vscodeDisplayName() {
    #expect(EditorType.vscode.displayName == "Visual Studio Code")
  }

  @Test func antigravityDisplayName() {
    #expect(EditorType.antigravity.displayName == "Antigravity")
  }

  @Test func zedDisplayName() {
    #expect(EditorType.zed.displayName == "Zed")
  }

  @Test func allCasesHaveDisplayName() {
    for editor in EditorType.allCases {
      #expect(!editor.displayName.isEmpty)
    }
  }

  @Test func codableRoundTrip() throws {
    for editor in EditorType.allCases {
      let data = try JSONEncoder().encode(editor)
      let decoded = try JSONDecoder().decode(EditorType.self, from: data)
      #expect(decoded == editor)
    }
  }
}
