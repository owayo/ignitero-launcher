import Foundation
import Testing

@testable import IgniteroCore

// MARK: - アプリItem テスト

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

// MARK: - DirectoryItem テスト

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

// MARK: - EditorType テスト

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

  @Test func zedDoesNotSupportCodeWorkspace() {
    #expect(EditorType.zed.supportsCodeWorkspace == false)
  }

  @Test func vscodeBasedEditorsSupportCodeWorkspace() {
    #expect(EditorType.vscode.supportsCodeWorkspace == true)
    #expect(EditorType.cursor.supportsCodeWorkspace == true)
    #expect(EditorType.windsurf.supportsCodeWorkspace == true)
    #expect(EditorType.antigravity.supportsCodeWorkspace == true)
  }
}

// MARK: - EditorType ショートカットキー テスト

@Suite("EditorType ShortcutKey")
struct EditorTypeShortcutKeyTests {

  @Test func shortcutKeysAreUniqueSingleLowercaseCharacters() {
    let keys = EditorType.allCases.map(\.shortcutKey)
    // 重複があると逆引きで後ろのエディタが選べなくなる
    #expect(Set(keys).count == keys.count)
    for key in keys {
      #expect(key.count == 1)
      #expect(key == key.lowercased())
    }
  }

  @Test func reverseLookupRoundTripsForAllCases() {
    for editor in EditorType.allCases {
      #expect(EditorType(shortcutKey: editor.shortcutKey) == editor)
    }
  }

  @Test(arguments: ["", "x", "W", " w", "w ", "ww"])
  func unknownOrUnnormalizedKeysReturnNil(key: String) {
    // charactersIgnoringModifiers をそのまま照合するため、大文字や空白付きは一致させない
    #expect(EditorType(shortcutKey: key) == nil)
  }

  @MainActor
  @Test func pickerAndRadialDisplayUseSameKeys() {
    // ラジアル表示に出るキーと、ピッカーが実際に受け付けるキーが一致すること
    let editors = EditorType.allCases.map { type in
      EditorInfo(id: type, name: type.displayName, appName: "\(type.rawValue).app", installed: true)
    }
    let items = RadialPickerItemFactory.editorItems(from: editors)
    for (editor, item) in zip(EditorType.allCases, items) {
      #expect(item.shortcutKey == EditorPickerState.shortcutKey(for: editor))
      #expect(item.shortcutKey.flatMap { EditorPickerState.editor(forShortcutKey: $0) } == editor)
    }
  }

  @Test func launchServiceDisplayNameMatchesModel() {
    for editor in EditorType.allCases {
      #expect(LaunchService.displayName(for: editor) == editor.displayName)
    }
  }
}

// MARK: - ディレクトリの開き方（Finder 指定）

@Suite("ディレクトリの開き方 (Finder 指定)")
struct DirectoryOpenTargetTests {

  @Test("opens_in_finder を持たない古い JSON は Finder 指定なしとして読む")
  func decodingWithoutOpensInFinderDefaultsToFalse() throws {
    let json = #"{"name":"proj","path":"/Users/dev/proj","editor":"zed"}"#
    let item = try JSONDecoder().decode(DirectoryItem.self, from: Data(json.utf8))
    #expect(item.opensInFinder == false)
    #expect(item.editor == "zed")
  }

  @Test("Finder 指定は Codable の往復で保たれる")
  func opensInFinderRoundTrips() throws {
    let original = DirectoryItem(name: "proj", path: "/Users/dev/proj", opensInFinder: true)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(DirectoryItem.self, from: data)
    #expect(decoded == original)
  }

  @Test("SearchResult は DirectoryItem の Finder 指定を引き継ぐ")
  func searchResultCarriesOpensInFinder() {
    let finder = SearchResult(
      directoryItem: DirectoryItem(name: "a", path: "/a", opensInFinder: true), score: 0)
    let editor = SearchResult(
      directoryItem: DirectoryItem(name: "b", path: "/b", editor: "zed"), score: 0)
    #expect(finder.opensInFinder)
    #expect(!editor.opensInFinder)
    #expect(!SearchResult(appItem: AppItem(name: "X", path: "/X.app"), score: 0).opensInFinder)
  }

  @Test("開くエディタの解決: Finder 指定は nil、未指定は既定エディタ、個別指定はその値")
  func directoryEditorRawValueRules() {
    let finder = SearchResult(
      directoryItem: DirectoryItem(name: "a", path: "/a", editor: "zed", opensInFinder: true),
      score: 0)
    let unspecified = SearchResult(
      directoryItem: DirectoryItem(name: "b", path: "/b"), score: 0)
    let explicit = SearchResult(
      directoryItem: DirectoryItem(name: "c", path: "/c", editor: "zed"), score: 0)

    // Finder 指定は editor の値に関わらず Finder（nil）
    #expect(finder.directoryEditorRawValue(defaultEditorRawValue: "cursor") == nil)
    #expect(unspecified.directoryEditorRawValue(defaultEditorRawValue: "cursor") == "cursor")
    #expect(explicit.directoryEditorRawValue(defaultEditorRawValue: "cursor") == "zed")
  }
}
