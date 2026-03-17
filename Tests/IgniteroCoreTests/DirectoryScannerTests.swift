import Foundation
import Testing

@testable import IgniteroCore

// MARK: - モックファイルシステムプロバイダー

struct MockFileSystemProvider: FileSystemProvider {
  var directoryContents: [String: [String]] = [:]
  var directoryFlags: Set<String> = []
  var existingPaths: Set<String> = []

  func contentsOfDirectory(atPath path: String) throws -> [String] {
    guard let contents = directoryContents[path] else {
      throw FileSystemError.directoryNotFound(path)
    }
    return contents
  }

  func isDirectory(atPath path: String) -> Bool {
    directoryFlags.contains(path)
  }

  func fileExists(atPath path: String) -> Bool {
    existingPaths.contains(path)
  }
}

// MARK: - ScanResult テスト

@Suite("ScanResult")
struct ScanResultTests {

  @Test func emptyScanResult() {
    let result = ScanResult(directories: [], apps: [])
    #expect(result.directories.isEmpty)
    #expect(result.apps.isEmpty)
  }

  @Test func scanResultEquality() {
    let dirs = [DirectoryItem(name: "project", path: "/dev/project", editor: "cursor")]
    let apps = [AppItem(name: "MyApp", path: "/dev/MyApp.app")]
    let result1 = ScanResult(directories: dirs, apps: apps)
    let result2 = ScanResult(directories: dirs, apps: apps)
    #expect(result1 == result2)
  }
}

// MARK: - DirectoryScanner プロトコルテスト

@Suite("DirectoryScannerProtocol")
struct DirectoryScannerProtocolTests {

  @Test func conformsToProtocol() {
    let fs = MockFileSystemProvider()
    let scanner = DirectoryScanner(fileSystemProvider: fs)
    let _: any DirectoryScannerProtocol = scanner
  }

  @Test func isSendable() {
    let fs = MockFileSystemProvider()
    let scanner = DirectoryScanner(fileSystemProvider: fs)
    let _: any Sendable = scanner
    _ = scanner
  }
}

// MARK: - 空入力テスト

@Suite("DirectoryScanner Empty Input")
struct DirectoryScannerEmptyInputTests {

  @Test func scanWithNoRegisteredDirectories() throws {
    let fs = MockFileSystemProvider()
    let scanner = DirectoryScanner(fileSystemProvider: fs)
    let result = try scanner.scan(directories: [])
    #expect(result.directories.isEmpty)
    #expect(result.apps.isEmpty)
  }
}

// MARK: - サブディレクトリスキャンテスト

@Suite("DirectoryScanner Subdirectory Scanning")
struct DirectoryScannerSubdirectoryScanningTests {

  @Test func scanFindsImmediateSubdirectories() throws {
    var fs = MockFileSystemProvider()
    let basePath = "/Users/dev/projects"
    fs.directoryContents[basePath] = ["project-a", "project-b", "readme.txt"]
    fs.directoryFlags = [
      basePath,
      "\(basePath)/project-a",
      "\(basePath)/project-b",
    ]
    fs.existingPaths = [
      basePath,
      "\(basePath)/project-a",
      "\(basePath)/project-b",
      "\(basePath)/readme.txt",
    ]

    let registered = RegisteredDirectory(
      path: basePath,
      parentOpenMode: .editor,
      parentEditor: "cursor",
      subdirsOpenMode: .editor,
      subdirsEditor: "vscode",
      scanForApps: false
    )

    let scanner = DirectoryScanner(fileSystemProvider: fs)
    let result = try scanner.scan(directories: [registered])

    // サブディレクトリが結果に含まれることを確認する
    let subdirs = result.directories.filter { $0.path != basePath }
    #expect(subdirs.count == 2)
    #expect(subdirs.contains { $0.name == "project-a" && $0.path == "\(basePath)/project-a" })
    #expect(subdirs.contains { $0.name == "project-b" && $0.path == "\(basePath)/project-b" })
  }

  @Test func scanExcludesRegularFiles() throws {
    var fs = MockFileSystemProvider()
    let basePath = "/Users/dev/projects"
    fs.directoryContents[basePath] = ["project-a", "readme.txt", ".gitignore"]
    fs.directoryFlags = [
      basePath,
      "\(basePath)/project-a",
    ]
    fs.existingPaths = [
      basePath,
      "\(basePath)/project-a",
      "\(basePath)/readme.txt",
      "\(basePath)/.gitignore",
    ]

    let registered = RegisteredDirectory(
      path: basePath,
      parentOpenMode: .finder,
      subdirsOpenMode: .editor,
      subdirsEditor: "cursor",
      scanForApps: false
    )

    let scanner = DirectoryScanner(fileSystemProvider: fs)
    let result = try scanner.scan(directories: [registered])

    // project-a のみディレクトリで、readme.txt と .gitignore は除外される
    let subdirs = result.directories.filter { $0.path != basePath }
    #expect(subdirs.count == 1)
    #expect(subdirs[0].name == "project-a")
  }

  @Test func scanExcludesHiddenDirectories() throws {
    var fs = MockFileSystemProvider()
    let basePath = "/Users/dev/projects"
    fs.directoryContents[basePath] = ["visible-project", ".hidden-dir"]
    fs.directoryFlags = [
      basePath,
      "\(basePath)/visible-project",
      "\(basePath)/.hidden-dir",
    ]
    fs.existingPaths = [
      basePath,
      "\(basePath)/visible-project",
      "\(basePath)/.hidden-dir",
    ]

    let registered = RegisteredDirectory(
      path: basePath,
      parentOpenMode: .finder,
      subdirsOpenMode: .editor,
      scanForApps: false
    )

    let scanner = DirectoryScanner(fileSystemProvider: fs)
    let result = try scanner.scan(directories: [registered])

    let subdirs = result.directories.filter { $0.path != basePath }
    #expect(subdirs.count == 1)
    #expect(subdirs[0].name == "visible-project")
  }
}

// MARK: - エディタ割り当てテスト

@Suite("DirectoryScanner Editor Assignment")
struct DirectoryScannerEditorAssignmentTests {

  @Test func parentDirectoryUsesParentEditor() throws {
    var fs = MockFileSystemProvider()
    let basePath = "/Users/dev/projects"
    fs.directoryContents[basePath] = []
    fs.directoryFlags = [basePath]
    fs.existingPaths = [basePath]

    let registered = RegisteredDirectory(
      path: basePath,
      parentOpenMode: .editor,
      parentEditor: "cursor",
      subdirsOpenMode: .editor,
      subdirsEditor: "vscode",
      scanForApps: false
    )

    let scanner = DirectoryScanner(fileSystemProvider: fs)
    let result = try scanner.scan(directories: [registered])

    let parent = result.directories.first { $0.path == basePath }
    #expect(parent != nil)
    #expect(parent?.editor == "cursor")
  }

  @Test func subdirectoriesUseSubdirsEditor() throws {
    var fs = MockFileSystemProvider()
    let basePath = "/Users/dev/projects"
    fs.directoryContents[basePath] = ["sub-a"]
    fs.directoryFlags = [basePath, "\(basePath)/sub-a"]
    fs.existingPaths = [basePath, "\(basePath)/sub-a"]

    let registered = RegisteredDirectory(
      path: basePath,
      parentOpenMode: .editor,
      parentEditor: "cursor",
      subdirsOpenMode: .editor,
      subdirsEditor: "vscode",
      scanForApps: false
    )

    let scanner = DirectoryScanner(fileSystemProvider: fs)
    let result = try scanner.scan(directories: [registered])

    let subdir = result.directories.first { $0.path == "\(basePath)/sub-a" }
    #expect(subdir != nil)
    #expect(subdir?.editor == "vscode")
  }

  @Test func noneOpenModeExcludesFromResults() throws {
    var fs = MockFileSystemProvider()
    let basePath = "/Users/dev/projects"
    fs.directoryContents[basePath] = ["sub-a"]
    fs.directoryFlags = [basePath, "\(basePath)/sub-a"]
    fs.existingPaths = [basePath, "\(basePath)/sub-a"]

    let registered = RegisteredDirectory(
      path: basePath,
      parentOpenMode: .none,
      subdirsOpenMode: .none,
      scanForApps: false
    )

    let scanner = DirectoryScanner(fileSystemProvider: fs)
    let result = try scanner.scan(directories: [registered])

    // mode が .none の場合、親と子ディレクトリの両方を除外する
    #expect(result.directories.isEmpty)
  }

  @Test func noneSubdirsExcludesOnlySubdirectories() throws {
    var fs = MockFileSystemProvider()
    let basePath = "/Users/dev/projects"
    fs.directoryContents[basePath] = ["sub-a", "sub-b"]
    fs.directoryFlags = [basePath, "\(basePath)/sub-a", "\(basePath)/sub-b"]
    fs.existingPaths = [basePath, "\(basePath)/sub-a", "\(basePath)/sub-b"]

    let registered = RegisteredDirectory(
      path: basePath,
      parentOpenMode: .finder,
      subdirsOpenMode: .none,
      scanForApps: false
    )

    let scanner = DirectoryScanner(fileSystemProvider: fs)
    let result = try scanner.scan(directories: [registered])

    // 親は含め、子ディレクトリは除外する
    #expect(result.directories.count == 1)
    #expect(result.directories[0].path == basePath)
  }

  @Test func noneParentExcludesOnlyParent() throws {
    var fs = MockFileSystemProvider()
    let basePath = "/Users/dev/projects"
    fs.directoryContents[basePath] = ["sub-a"]
    fs.directoryFlags = [basePath, "\(basePath)/sub-a"]
    fs.existingPaths = [basePath, "\(basePath)/sub-a"]

    let registered = RegisteredDirectory(
      path: basePath,
      parentOpenMode: .none,
      subdirsOpenMode: .editor,
      subdirsEditor: "vscode",
      scanForApps: false
    )

    let scanner = DirectoryScanner(fileSystemProvider: fs)
    let result = try scanner.scan(directories: [registered])

    // 親は除外し、子ディレクトリは含める
    #expect(result.directories.count == 1)
    #expect(result.directories[0].path == "\(basePath)/sub-a")
    #expect(result.directories[0].editor == "vscode")
  }

  @Test func noEditorWhenOpenModeIsFinder() throws {
    var fs = MockFileSystemProvider()
    let basePath = "/Users/dev/projects"
    fs.directoryContents[basePath] = ["sub-a"]
    fs.directoryFlags = [basePath, "\(basePath)/sub-a"]
    fs.existingPaths = [basePath, "\(basePath)/sub-a"]

    let registered = RegisteredDirectory(
      path: basePath,
      parentOpenMode: .finder,
      subdirsOpenMode: .finder,
      scanForApps: false
    )

    let scanner = DirectoryScanner(fileSystemProvider: fs)
    let result = try scanner.scan(directories: [registered])

    for dir in result.directories {
      #expect(dir.editor == nil)
    }
  }
}

// MARK: - アプリスキャンテスト

@Suite("DirectoryScanner App Scanning")
struct DirectoryScannerAppScanningTests {

  @Test func scanForAppsDetectsAppBundles() throws {
    var fs = MockFileSystemProvider()
    let basePath = "/Users/dev/apps"
    fs.directoryContents[basePath] = ["MyApp.app", "Another.app", "not-an-app"]
    fs.directoryFlags = [
      basePath,
      "\(basePath)/MyApp.app",
      "\(basePath)/Another.app",
      "\(basePath)/not-an-app",
    ]
    fs.existingPaths = [
      basePath,
      "\(basePath)/MyApp.app",
      "\(basePath)/Another.app",
      "\(basePath)/not-an-app",
    ]

    let registered = RegisteredDirectory(
      path: basePath,
      parentOpenMode: .finder,
      subdirsOpenMode: .finder,
      scanForApps: true
    )

    let scanner = DirectoryScanner(fileSystemProvider: fs)
    let result = try scanner.scan(directories: [registered])

    #expect(result.apps.count == 2)
    #expect(result.apps.contains { $0.name == "MyApp" && $0.path == "\(basePath)/MyApp.app" })
    #expect(
      result.apps.contains { $0.name == "Another" && $0.path == "\(basePath)/Another.app" })
  }

  @Test func noAppsScanningWhenDisabled() throws {
    var fs = MockFileSystemProvider()
    let basePath = "/Users/dev/apps"
    fs.directoryContents[basePath] = ["MyApp.app"]
    fs.directoryFlags = [basePath, "\(basePath)/MyApp.app"]
    fs.existingPaths = [basePath, "\(basePath)/MyApp.app"]

    let registered = RegisteredDirectory(
      path: basePath,
      parentOpenMode: .finder,
      subdirsOpenMode: .finder,
      scanForApps: false
    )

    let scanner = DirectoryScanner(fileSystemProvider: fs)
    let result = try scanner.scan(directories: [registered])

    #expect(result.apps.isEmpty)
  }

  @Test func appBundlesExcludedFromDirectoryItems() throws {
    var fs = MockFileSystemProvider()
    let basePath = "/Users/dev/mixed"
    fs.directoryContents[basePath] = ["project-a", "MyApp.app"]
    fs.directoryFlags = [
      basePath,
      "\(basePath)/project-a",
      "\(basePath)/MyApp.app",
    ]
    fs.existingPaths = [
      basePath,
      "\(basePath)/project-a",
      "\(basePath)/MyApp.app",
    ]

    let registered = RegisteredDirectory(
      path: basePath,
      parentOpenMode: .editor,
      parentEditor: "cursor",
      subdirsOpenMode: .editor,
      subdirsEditor: "vscode",
      scanForApps: true
    )

    let scanner = DirectoryScanner(fileSystemProvider: fs)
    let result = try scanner.scan(directories: [registered])

    // .app バンドルはディレクトリ結果に含めない
    let subdirs = result.directories.filter { $0.path != basePath }
    #expect(subdirs.count == 1)
    #expect(subdirs[0].name == "project-a")

    // .app バンドルはアプリ結果に含める
    #expect(result.apps.count == 1)
    #expect(result.apps[0].name == "MyApp")
  }
}

// MARK: - 複数登録ディレクトリテスト

@Suite("DirectoryScanner Multiple Directories")
struct DirectoryScannerMultipleDirectoriesTests {

  @Test func scanMultipleRegisteredDirectories() throws {
    var fs = MockFileSystemProvider()

    let path1 = "/Users/dev/work"
    let path2 = "/Users/dev/personal"

    fs.directoryContents[path1] = ["work-project"]
    fs.directoryContents[path2] = ["hobby-project"]

    fs.directoryFlags = [
      path1, "\(path1)/work-project",
      path2, "\(path2)/hobby-project",
    ]
    fs.existingPaths = [
      path1, "\(path1)/work-project",
      path2, "\(path2)/hobby-project",
    ]

    let dirs = [
      RegisteredDirectory(
        path: path1,
        parentOpenMode: .editor,
        parentEditor: "cursor",
        subdirsOpenMode: .editor,
        subdirsEditor: "cursor",
        scanForApps: false
      ),
      RegisteredDirectory(
        path: path2,
        parentOpenMode: .editor,
        parentEditor: "vscode",
        subdirsOpenMode: .editor,
        subdirsEditor: "vscode",
        scanForApps: false
      ),
    ]

    let scanner = DirectoryScanner(fileSystemProvider: fs)
    let result = try scanner.scan(directories: dirs)

    // 親 2 件 + 子ディレクトリ 2 件で合計 4 件
    #expect(result.directories.count == 4)
    #expect(result.directories.contains { $0.path == path1 && $0.editor == "cursor" })
    #expect(
      result.directories.contains {
        $0.path == "\(path1)/work-project" && $0.editor == "cursor"
      })
    #expect(result.directories.contains { $0.path == path2 && $0.editor == "vscode" })
    #expect(
      result.directories.contains {
        $0.path == "\(path2)/hobby-project" && $0.editor == "vscode"
      })
  }
}

// MARK: - エラーハンドリングテスト

@Suite("DirectoryScanner Error Handling")
struct DirectoryScannerErrorHandlingTests {

  @Test func scanSkipsNonExistentDirectories() throws {
    var fs = MockFileSystemProvider()
    // directoryContents に存在しないため読み取りエラーになる
    let basePath = "/Users/dev/nonexistent"
    fs.existingPaths = []

    let registered = RegisteredDirectory(
      path: basePath,
      parentOpenMode: .finder,
      subdirsOpenMode: .finder,
      scanForApps: false
    )

    let scanner = DirectoryScanner(fileSystemProvider: fs)
    let result = try scanner.scan(directories: [registered])

    // 存在しないディレクトリは安全にスキップされる
    #expect(result.directories.isEmpty)
    #expect(result.apps.isEmpty)
  }

  @Test func scanContinuesAfterOneDirectoryFails() throws {
    var fs = MockFileSystemProvider()

    let path1 = "/Users/dev/broken"
    // path1 は directoryContents にないため読み取り時に失敗する
    let path2 = "/Users/dev/working"
    fs.directoryContents[path2] = ["project"]
    fs.directoryFlags = [path2, "\(path2)/project"]
    fs.existingPaths = [path2, "\(path2)/project"]

    let dirs = [
      RegisteredDirectory(
        path: path1,
        parentOpenMode: .finder,
        subdirsOpenMode: .finder,
        scanForApps: false
      ),
      RegisteredDirectory(
        path: path2,
        parentOpenMode: .editor,
        parentEditor: "cursor",
        subdirsOpenMode: .editor,
        subdirsEditor: "cursor",
        scanForApps: false
      ),
    ]

    let scanner = DirectoryScanner(fileSystemProvider: fs)
    let result = try scanner.scan(directories: dirs)

    // path2 側のスキャンは継続される
    #expect(result.directories.contains { $0.path == path2 })
    #expect(result.directories.contains { $0.path == "\(path2)/project" })
  }
}

// MARK: - 親ディレクトリ名テスト

@Suite("DirectoryScanner Parent Directory Name")
struct DirectoryScannerParentNameTests {

  @Test func parentDirectoryUsesLastPathComponent() throws {
    var fs = MockFileSystemProvider()
    let basePath = "/Users/dev/my-projects"
    fs.directoryContents[basePath] = []
    fs.directoryFlags = [basePath]
    fs.existingPaths = [basePath]

    let registered = RegisteredDirectory(
      path: basePath,
      parentOpenMode: .editor,
      parentEditor: "cursor",
      subdirsOpenMode: .editor,
      scanForApps: false
    )

    let scanner = DirectoryScanner(fileSystemProvider: fs)
    let result = try scanner.scan(directories: [registered])

    let parent = result.directories.first { $0.path == basePath }
    #expect(parent?.name == "my-projects")
  }

  @Test func parentDirectoryHandlesTrailingSlash() throws {
    var fs = MockFileSystemProvider()
    let basePath = "/Users/dev/my-projects"
    // RegisteredDirectory の path が末尾スラッシュ付きでも扱えることを確認する
    let pathWithSlash = basePath + "/"
    fs.directoryContents[basePath] = []
    fs.directoryFlags = [basePath]
    fs.existingPaths = [basePath]

    let registered = RegisteredDirectory(
      path: pathWithSlash,
      parentOpenMode: .editor,
      parentEditor: "cursor",
      subdirsOpenMode: .editor,
      scanForApps: false
    )

    let scanner = DirectoryScanner(fileSystemProvider: fs)
    let result = try scanner.scan(directories: [registered])

    let parent = result.directories.first
    #expect(parent?.name == "my-projects")
  }

  @Test func rootDirectoryPreservesPathAndChildPaths() throws {
    var fs = MockFileSystemProvider()
    fs.directoryContents["/"] = ["Applications"]
    fs.directoryFlags = ["/", "/Applications"]
    fs.existingPaths = ["/", "/Applications"]

    let registered = RegisteredDirectory(
      path: "/",
      parentOpenMode: .editor,
      parentEditor: "cursor",
      subdirsOpenMode: .editor,
      scanForApps: false
    )

    let scanner = DirectoryScanner(fileSystemProvider: fs)
    let result = try scanner.scan(directories: [registered])

    let parent = result.directories.first { $0.path == "/" }
    let child = result.directories.first { $0.path == "/Applications" }
    #expect(parent?.name == "/")
    #expect(child?.name == "Applications")
  }
}

// MARK: - キャッシュデータベース連携テスト

@Suite("DirectoryScanner Cache Integration")
struct DirectoryScannerCacheIntegrationTests {

  @Test func scanResultCanBeSavedToCache() async throws {
    var fs = MockFileSystemProvider()
    let basePath = "/Users/dev/projects"
    fs.directoryContents[basePath] = ["project-a", "MyApp.app"]
    fs.directoryFlags = [
      basePath,
      "\(basePath)/project-a",
      "\(basePath)/MyApp.app",
    ]
    fs.existingPaths = [
      basePath,
      "\(basePath)/project-a",
      "\(basePath)/MyApp.app",
    ]

    let registered = RegisteredDirectory(
      path: basePath,
      parentOpenMode: .editor,
      parentEditor: "cursor",
      subdirsOpenMode: .editor,
      subdirsEditor: "vscode",
      scanForApps: true
    )

    let scanner = DirectoryScanner(fileSystemProvider: fs)
    let result = try scanner.scan(directories: [registered])

    // キャッシュデータベースへ保存する
    let db = try CacheDatabase(inMemory: true)
    try db.saveDirectories(result.directories)
    try db.saveApps(result.apps)

    // 読み戻して内容を確認する
    let loadedDirs = try await db.loadDirectories()
    let loadedApps = try await db.loadApps()

    #expect(loadedDirs.count == result.directories.count)
    #expect(loadedApps.count == result.apps.count)

    for dir in result.directories {
      #expect(loadedDirs.contains { $0.path == dir.path && $0.editor == dir.editor })
    }
    for app in result.apps {
      #expect(loadedApps.contains { $0.path == app.path && $0.name == app.name })
    }
  }
}

// MARK: - デフォルト FileSystemProvider テスト

@Suite("DefaultFileSystemProvider")
struct DefaultFileSystemProviderTests {

  @Test func conformsToProtocol() {
    let provider = DefaultFileSystemProvider()
    let _: any FileSystemProvider = provider
  }

  @Test func isSendable() {
    let provider = DefaultFileSystemProvider()
    let _: any Sendable = provider
    _ = provider
  }

  @Test func detectsExistingDirectory() {
    let provider = DefaultFileSystemProvider()
    // macOS では /tmp が常に存在する
    #expect(provider.fileExists(atPath: "/tmp"))
    #expect(provider.isDirectory(atPath: "/tmp"))
  }

  @Test func detectsNonExistentPath() {
    let provider = DefaultFileSystemProvider()
    #expect(!provider.fileExists(atPath: "/nonexistent_path_xyz_123"))
    #expect(!provider.isDirectory(atPath: "/nonexistent_path_xyz_123"))
  }
}

// MARK: - 実ファイルシステム連携テスト

@Suite("DirectoryScanner Real FileSystem Integration")
struct DirectoryScannerRealFileSystemTests {

  @Test func scanWithRealTempDirectory() throws {
    let fm = FileManager.default
    let tempBase = fm.temporaryDirectory.appendingPathComponent(
      "ignitero-scanner-test-\(UUID().uuidString)")
    try fm.createDirectory(at: tempBase, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tempBase) }

    // サブディレクトリを作成する
    let subA = tempBase.appendingPathComponent("project-a")
    let subB = tempBase.appendingPathComponent("project-b")
    try fm.createDirectory(at: subA, withIntermediateDirectories: true)
    try fm.createDirectory(at: subB, withIntermediateDirectories: true)

    // 通常ファイルを作成し、結果から除外されることを確認する
    let file = tempBase.appendingPathComponent("readme.txt")
    try "test".write(to: file, atomically: true, encoding: .utf8)

    let registered = RegisteredDirectory(
      path: tempBase.path,
      parentOpenMode: .editor,
      parentEditor: "cursor",
      subdirsOpenMode: .editor,
      subdirsEditor: "vscode",
      scanForApps: false
    )

    let scanner = DirectoryScanner()
    let result = try scanner.scan(directories: [registered])

    // 親 1 件 + 子ディレクトリ 2 件
    #expect(result.directories.count == 3)
    #expect(result.directories.contains { $0.path == tempBase.path && $0.editor == "cursor" })
    #expect(
      result.directories.contains { $0.path == subA.path && $0.editor == "vscode" })
    #expect(
      result.directories.contains { $0.path == subB.path && $0.editor == "vscode" })
    #expect(result.apps.isEmpty)
  }

  @Test func scanWithRealAppBundle() throws {
    let fm = FileManager.default
    let tempBase = fm.temporaryDirectory.appendingPathComponent(
      "ignitero-scanner-test-\(UUID().uuidString)")
    try fm.createDirectory(at: tempBase, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tempBase) }

    // 擬似的な .app バンドルディレクトリを作成する
    let appBundle = tempBase.appendingPathComponent("TestApp.app")
    try fm.createDirectory(at: appBundle, withIntermediateDirectories: true)

    // 通常のサブディレクトリを作成する
    let subDir = tempBase.appendingPathComponent("project")
    try fm.createDirectory(at: subDir, withIntermediateDirectories: true)

    let registered = RegisteredDirectory(
      path: tempBase.path,
      parentOpenMode: .finder,
      subdirsOpenMode: .editor,
      subdirsEditor: "cursor",
      scanForApps: true
    )

    let scanner = DirectoryScanner()
    let result = try scanner.scan(directories: [registered])

    // 親 1 件 + project サブディレクトリ 1 件（.app はディレクトリ結果から除外）
    let subdirs = result.directories.filter { $0.path != tempBase.path }
    #expect(subdirs.count == 1)
    #expect(subdirs[0].name == "project")

    // .app バンドルはアプリとして検出される
    #expect(result.apps.count == 1)
    #expect(result.apps[0].name == "TestApp")
    #expect(result.apps[0].path == appBundle.path)
  }
}
