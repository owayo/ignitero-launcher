import Foundation
import Testing

@testable import IgniteroCore

// MARK: - テストヘルパー

private func makeTempDir() throws -> String {
  let dir = FileManager.default.temporaryDirectory
    .appendingPathComponent("ignitero-scanner-test-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  return dir.path
}

private func cleanup(_ path: String) {
  try? FileManager.default.removeItem(atPath: path)
}

/// Info.plist 付きの擬似 .app バンドルを作成する
private func createFakeApp(
  at directory: String,
  name: String,
  displayName: String? = nil,
  bundleName: String? = nil,
  iconFile: String? = nil,
  iconName: String? = nil
) throws -> String {
  let appPath = (directory as NSString).appendingPathComponent(name)
  let contentsPath = (appPath as NSString).appendingPathComponent("Contents")
  try FileManager.default.createDirectory(
    atPath: contentsPath, withIntermediateDirectories: true)

  var plistDict: [String: Any] = [:]
  if let displayName { plistDict["CFBundleDisplayName"] = displayName }
  if let bundleName { plistDict["CFBundleName"] = bundleName }
  if let iconFile { plistDict["CFBundleIconFile"] = iconFile }
  if let iconName { plistDict["CFBundleIconName"] = iconName }

  let plistPath = (contentsPath as NSString).appendingPathComponent("Info.plist")
  let plistData = try PropertyListSerialization.data(
    fromPropertyList: plistDict, format: .xml, options: 0)
  try plistData.write(to: URL(fileURLWithPath: plistPath))

  return appPath
}

/// ローカライズ済み InfoPlist.strings を持つ擬似 .app を作成する
private func createLocalizedApp(
  at directory: String,
  name: String,
  bundleName: String,
  localizedName: String,
  locale: String = "ja"
) throws -> String {
  let appPath = try createFakeApp(at: directory, name: name, bundleName: bundleName)
  let contentsPath = (appPath as NSString).appendingPathComponent("Contents")
  let lprojPath = (contentsPath as NSString).appendingPathComponent(
    "Resources/\(locale).lproj")
  try FileManager.default.createDirectory(
    atPath: lprojPath, withIntermediateDirectories: true)

  let stringsContent = """
    "CFBundleDisplayName" = "\(localizedName)";
    "CFBundleName" = "\(localizedName)";
    """
  let stringsPath = (lprojPath as NSString).appendingPathComponent("InfoPlist.strings")
  try stringsContent.write(toFile: stringsPath, atomically: true, encoding: .utf8)

  return appPath
}

// MARK: - プロトコル準拠テスト

@Suite("AppScanner Protocol")
struct AppScannerProtocolTests {

  @Test func conformsToAppScannerProtocol() {
    let scanner = AppScanner()
    #expect(scanner is any AppScannerProtocol)
  }

  @Test func isSendable() {
    let scanner = AppScanner()
    let _: any Sendable = scanner
    #expect(true)  // コンパイルできれば Sendable 準拠
  }
}

// MARK: - ScanTarget テスト

@Suite("AppScanner ScanTarget")
struct AppScannerScanTargetTests {

  @Test func defaultScanTargets() {
    let targets = AppScanner.defaultScanTargets
    #expect(targets.count == 3)

    let paths = targets.map(\.path)
    #expect(paths.contains("/Applications"))
    #expect(paths.contains("/System/Applications"))

    // ~/Applications は展開済みのパスで比較
    let homeApps = NSString(string: "~/Applications").expandingTildeInPath
    #expect(paths.contains(homeApps))
  }

  @Test func defaultDepths() {
    let targets = AppScanner.defaultScanTargets
    let applicationsTarget = targets.first { $0.path == "/Applications" }
    let systemTarget = targets.first { $0.path == "/System/Applications" }
    let homeTarget = targets.first {
      $0.path == NSString(string: "~/Applications").expandingTildeInPath
    }

    #expect(applicationsTarget?.maxDepth == 2)
    #expect(systemTarget?.maxDepth == 3)
    #expect(homeTarget?.maxDepth == 3)
  }

  @Test func customScanTargets() {
    let customTargets = [
      AppScanner.ScanTarget(path: "/tmp/apps", maxDepth: 1)
    ]
    let scanner = AppScanner(scanTargets: customTargets)
    #expect(scanner.scanTargets.count == 1)
    #expect(scanner.scanTargets[0].path == "/tmp/apps")
    #expect(scanner.scanTargets[0].maxDepth == 1)
  }
}

// MARK: - App Bundle 検出テスト

@Suite("AppScanner Bundle Discovery")
struct AppScannerBundleDiscoveryTests {

  @Test func findsAppBundlesAtDepth1() throws {
    let tmpDir = try makeTempDir()
    defer { cleanup(tmpDir) }

    _ = try createFakeApp(at: tmpDir, name: "TestApp.app", bundleName: "TestApp")
    _ = try createFakeApp(at: tmpDir, name: "Another.app", bundleName: "Another")

    let scanner = AppScanner()
    let bundles = scanner.findAppBundles(in: tmpDir, maxDepth: 1)

    #expect(bundles.count == 2)
    #expect(bundles.contains { $0.hasSuffix("TestApp.app") })
    #expect(bundles.contains { $0.hasSuffix("Another.app") })
  }

  @Test func findsAppBundlesAtDepth2() throws {
    let tmpDir = try makeTempDir()
    defer { cleanup(tmpDir) }

    // 深さ 1
    _ = try createFakeApp(at: tmpDir, name: "TopLevel.app", bundleName: "TopLevel")

    // 深さ 2（サブディレクトリ配下）
    let subDir = (tmpDir as NSString).appendingPathComponent("SubFolder")
    try FileManager.default.createDirectory(
      atPath: subDir, withIntermediateDirectories: true)
    _ = try createFakeApp(at: subDir, name: "Nested.app", bundleName: "Nested")

    let scanner = AppScanner()
    let bundles = scanner.findAppBundles(in: tmpDir, maxDepth: 2)

    #expect(bundles.count == 2)
    #expect(bundles.contains { $0.hasSuffix("TopLevel.app") })
    #expect(bundles.contains { $0.hasSuffix("Nested.app") })
  }

  @Test func respectsMaxDepthLimit() throws {
    let tmpDir = try makeTempDir()
    defer { cleanup(tmpDir) }

    // 深さ 1
    _ = try createFakeApp(at: tmpDir, name: "TopLevel.app", bundleName: "TopLevel")

    // 深さ 2（サブディレクトリ配下）
    let subDir = (tmpDir as NSString).appendingPathComponent("SubFolder")
    try FileManager.default.createDirectory(
      atPath: subDir, withIntermediateDirectories: true)
    _ = try createFakeApp(at: subDir, name: "Nested.app", bundleName: "Nested")

    let scanner = AppScanner()
    let bundles = scanner.findAppBundles(in: tmpDir, maxDepth: 1)

    // maxDepth=1 なので depth 2 のアプリは見つからない
    #expect(bundles.count == 1)
    #expect(bundles[0].hasSuffix("TopLevel.app"))
  }

  @Test func doesNotDescendIntoAppBundles() throws {
    let tmpDir = try makeTempDir()
    defer { cleanup(tmpDir) }

    // .app バンドル内の .app は無視する
    let outerApp = try createFakeApp(
      at: tmpDir, name: "Outer.app", bundleName: "Outer")
    _ = try createFakeApp(at: outerApp, name: "Inner.app", bundleName: "Inner")

    let scanner = AppScanner()
    let bundles = scanner.findAppBundles(in: tmpDir, maxDepth: 3)

    #expect(bundles.count == 1)
    #expect(bundles[0].hasSuffix("Outer.app"))
  }

  @Test func emptyDirectoryReturnsEmptyArray() throws {
    let tmpDir = try makeTempDir()
    defer { cleanup(tmpDir) }

    let scanner = AppScanner()
    let bundles = scanner.findAppBundles(in: tmpDir, maxDepth: 2)

    #expect(bundles.isEmpty)
  }

  @Test func nonExistentDirectoryReturnsEmptyArray() {
    let scanner = AppScanner()
    let bundles = scanner.findAppBundles(
      in: "/nonexistent/path/that/does/not/exist", maxDepth: 2)

    #expect(bundles.isEmpty)
  }

  @Test func ignoresNonAppItems() throws {
    let tmpDir = try makeTempDir()
    defer { cleanup(tmpDir) }

    _ = try createFakeApp(at: tmpDir, name: "RealApp.app", bundleName: "RealApp")

    // 通常のディレクトリ（.app でない）
    let normalDir = (tmpDir as NSString).appendingPathComponent("NotAnApp")
    try FileManager.default.createDirectory(
      atPath: normalDir, withIntermediateDirectories: true)

    // 通常のファイル
    let filePath = (tmpDir as NSString).appendingPathComponent("readme.txt")
    try "hello".write(toFile: filePath, atomically: true, encoding: .utf8)

    let scanner = AppScanner()
    let bundles = scanner.findAppBundles(in: tmpDir, maxDepth: 2)

    #expect(bundles.count == 1)
    #expect(bundles[0].hasSuffix("RealApp.app"))
  }
}

// MARK: - Info.plist 抽出テスト

@Suite("AppScanner Info.plist Extraction")
struct AppScannerPlistExtractionTests {

  @Test func extractsDisplayName() throws {
    let tmpDir = try makeTempDir()
    defer { cleanup(tmpDir) }

    let appPath = try createFakeApp(
      at: tmpDir, name: "MyApp.app",
      displayName: "My Application",
      bundleName: "MyApp"
    )

    let scanner = AppScanner()
    let (displayName, bundleName) = scanner.plistNames(for: appPath)

    #expect(displayName == "My Application")
    #expect(bundleName == "MyApp")
  }

  @Test func extractsBundleNameWhenNoDisplayName() throws {
    let tmpDir = try makeTempDir()
    defer { cleanup(tmpDir) }

    let appPath = try createFakeApp(
      at: tmpDir, name: "Simple.app",
      bundleName: "SimpleApp"
    )

    let scanner = AppScanner()
    let (displayName, bundleName) = scanner.plistNames(for: appPath)

    #expect(displayName == nil)
    #expect(bundleName == "SimpleApp")
  }

  @Test func returnsNilsForMissingPlist() throws {
    let tmpDir = try makeTempDir()
    defer { cleanup(tmpDir) }

    // Info.plist なしの .app
    let appPath = (tmpDir as NSString).appendingPathComponent("NoPlist.app")
    let contentsPath = (appPath as NSString).appendingPathComponent("Contents")
    try FileManager.default.createDirectory(
      atPath: contentsPath, withIntermediateDirectories: true)

    let scanner = AppScanner()
    let (displayName, bundleName) = scanner.plistNames(for: appPath)

    #expect(displayName == nil)
    #expect(bundleName == nil)
  }

  @Test func extractsIconFile() throws {
    let tmpDir = try makeTempDir()
    defer { cleanup(tmpDir) }

    let appPath = try createFakeApp(
      at: tmpDir, name: "IconApp.app",
      bundleName: "IconApp",
      iconFile: "AppIcon"
    )

    // Resources ディレクトリにアイコンファイルを作成
    let resourcesPath = (appPath as NSString).appendingPathComponent("Contents/Resources")
    try FileManager.default.createDirectory(
      atPath: resourcesPath, withIntermediateDirectories: true)
    let icnsPath = (resourcesPath as NSString).appendingPathComponent("AppIcon.icns")
    try "fake-icns".write(toFile: icnsPath, atomically: true, encoding: .utf8)

    let scanner = AppScanner()
    let iconPath = scanner.iconFilePath(for: appPath)

    #expect(iconPath != nil)
    #expect(iconPath!.hasSuffix("AppIcon.icns"))
  }

  @Test func extractsIconFileWithIcnsExtension() throws {
    let tmpDir = try makeTempDir()
    defer { cleanup(tmpDir) }

    let appPath = try createFakeApp(
      at: tmpDir, name: "IconApp2.app",
      bundleName: "IconApp2",
      iconFile: "AppIcon.icns"
    )

    // Resources ディレクトリにアイコンファイルを作成
    let resourcesPath = (appPath as NSString).appendingPathComponent("Contents/Resources")
    try FileManager.default.createDirectory(
      atPath: resourcesPath, withIntermediateDirectories: true)
    let icnsPath = (resourcesPath as NSString).appendingPathComponent("AppIcon.icns")
    try "fake-icns".write(toFile: icnsPath, atomically: true, encoding: .utf8)

    let scanner = AppScanner()
    let iconPath = scanner.iconFilePath(for: appPath)

    #expect(iconPath != nil)
    #expect(iconPath!.hasSuffix("AppIcon.icns"))
  }

  @Test func extractsIconName() throws {
    let tmpDir = try makeTempDir()
    defer { cleanup(tmpDir) }

    let appPath = try createFakeApp(
      at: tmpDir, name: "IconNameApp.app",
      bundleName: "IconNameApp",
      iconName: "AppIcon"
    )

    // Resources ディレクトリにアイコンファイルを作成
    let resourcesPath = (appPath as NSString).appendingPathComponent("Contents/Resources")
    try FileManager.default.createDirectory(
      atPath: resourcesPath, withIntermediateDirectories: true)
    let icnsPath = (resourcesPath as NSString).appendingPathComponent("AppIcon.icns")
    try "fake-icns".write(toFile: icnsPath, atomically: true, encoding: .utf8)

    let scanner = AppScanner()
    let iconPath = scanner.iconFilePath(for: appPath)

    #expect(iconPath != nil)
    #expect(iconPath!.hasSuffix("AppIcon.icns"))
  }

  @Test func returnsNilIconForMissingFile() throws {
    let tmpDir = try makeTempDir()
    defer { cleanup(tmpDir) }

    let appPath = try createFakeApp(
      at: tmpDir, name: "NoIcon.app",
      bundleName: "NoIcon",
      iconFile: "MissingIcon"
    )

    let scanner = AppScanner()
    let iconPath = scanner.iconFilePath(for: appPath)

    // ファイルが実在しないため nil
    #expect(iconPath == nil)
  }
}

// MARK: - ローカライズ名テスト

@Suite("AppScanner Localized Names")
struct AppScannerLocalizedNameTests {

  @Test func readsLocalizedNameFromLproj() throws {
    let tmpDir = try makeTempDir()
    defer { cleanup(tmpDir) }

    let appPath = try createLocalizedApp(
      at: tmpDir,
      name: "Localized.app",
      bundleName: "Localized",
      localizedName: "ローカライズアプリ",
      locale: "ja"
    )

    let scanner = AppScanner()
    let localizedName = scanner.localizedNameFromLproj(for: appPath, locale: "ja")

    #expect(localizedName == "ローカライズアプリ")
  }

  @Test func returnsNilForMissingLproj() throws {
    let tmpDir = try makeTempDir()
    defer { cleanup(tmpDir) }

    let appPath = try createFakeApp(
      at: tmpDir, name: "NoLproj.app", bundleName: "NoLproj")

    let scanner = AppScanner()
    let localizedName = scanner.localizedNameFromLproj(for: appPath, locale: "ja")

    #expect(localizedName == nil)
  }

  @Test("InfoPlist.strings に CFBundleName のみある場合はその値を返す")
  func bundleNameOnlyInLprojIsReturned() throws {
    let tmpDir = try makeTempDir()
    defer { cleanup(tmpDir) }

    let appPath = try createFakeApp(
      at: tmpDir, name: "BundleNameOnly.app", bundleName: "BundleNameOnly")
    let lprojPath =
      ((appPath as NSString).appendingPathComponent("Contents/Resources/ja.lproj"))
    try FileManager.default.createDirectory(
      atPath: lprojPath, withIntermediateDirectories: true)
    let stringsContent = """
      "CFBundleName" = "バンドル名のみ";
      """
    let stringsPath = (lprojPath as NSString).appendingPathComponent("InfoPlist.strings")
    try stringsContent.write(toFile: stringsPath, atomically: true, encoding: .utf8)

    let scanner = AppScanner()
    let localizedName = scanner.localizedNameFromLproj(for: appPath, locale: "ja")

    #expect(localizedName == "バンドル名のみ")
  }

  @Test("InfoPlist.strings に CFBundleDisplayName が優先される")
  func displayNamePreferredOverBundleNameInLproj() throws {
    let tmpDir = try makeTempDir()
    defer { cleanup(tmpDir) }

    let appPath = try createFakeApp(
      at: tmpDir, name: "BothNames.app", bundleName: "BothNames")
    let lprojPath =
      ((appPath as NSString).appendingPathComponent("Contents/Resources/ja.lproj"))
    try FileManager.default.createDirectory(
      atPath: lprojPath, withIntermediateDirectories: true)
    let stringsContent = """
      "CFBundleDisplayName" = "表示名";
      "CFBundleName" = "バンドル名";
      """
    let stringsPath = (lprojPath as NSString).appendingPathComponent("InfoPlist.strings")
    try stringsContent.write(toFile: stringsPath, atomically: true, encoding: .utf8)

    let scanner = AppScanner()
    let localizedName = scanner.localizedNameFromLproj(for: appPath, locale: "ja")

    #expect(localizedName == "表示名")
  }

  @Test("InfoPlist.strings の対象キーがない場合は nil")
  func unrelatedKeysOnlyReturnsNil() throws {
    let tmpDir = try makeTempDir()
    defer { cleanup(tmpDir) }

    let appPath = try createFakeApp(
      at: tmpDir, name: "UnrelatedKeys.app", bundleName: "UnrelatedKeys")
    let lprojPath =
      ((appPath as NSString).appendingPathComponent("Contents/Resources/ja.lproj"))
    try FileManager.default.createDirectory(
      atPath: lprojPath, withIntermediateDirectories: true)
    let stringsContent = """
      "CFBundleHelpBookName" = "ヘルプ";
      "NSHumanReadableCopyright" = "© 2026";
      """
    let stringsPath = (lprojPath as NSString).appendingPathComponent("InfoPlist.strings")
    try stringsContent.write(toFile: stringsPath, atomically: true, encoding: .utf8)

    let scanner = AppScanner()
    let localizedName = scanner.localizedNameFromLproj(for: appPath, locale: "ja")

    #expect(localizedName == nil)
  }

  @Test("InfoPlist.strings がバイナリ plist 形式でも読み取れる")
  func binaryPlistFormatIsRead() throws {
    let tmpDir = try makeTempDir()
    defer { cleanup(tmpDir) }

    let appPath = try createFakeApp(
      at: tmpDir, name: "BinaryPlist.app", bundleName: "BinaryPlist")
    let lprojPath =
      ((appPath as NSString).appendingPathComponent("Contents/Resources/ja.lproj"))
    try FileManager.default.createDirectory(
      atPath: lprojPath, withIntermediateDirectories: true)
    let dict: [String: String] = [
      "CFBundleDisplayName": "バイナリ表示名",
      "CFBundleName": "バイナリバンドル名",
    ]
    let plistData = try PropertyListSerialization.data(
      fromPropertyList: dict, format: .binary, options: 0)
    let stringsPath = (lprojPath as NSString).appendingPathComponent("InfoPlist.strings")
    try plistData.write(to: URL(fileURLWithPath: stringsPath))

    let scanner = AppScanner()
    let localizedName = scanner.localizedNameFromLproj(for: appPath, locale: "ja")

    #expect(localizedName == "バイナリ表示名")
  }

  @Test("指定ロケールの lproj が無くても InfoPlist.strings 自体が無いと nil")
  func unknownLocaleReturnsNil() throws {
    let tmpDir = try makeTempDir()
    defer { cleanup(tmpDir) }

    let appPath = try createLocalizedApp(
      at: tmpDir, name: "JaOnly.app", bundleName: "JaOnly",
      localizedName: "日本語アプリ", locale: "ja")

    let scanner = AppScanner()
    // 存在しないロケールを指定すると、優先順位リストにそれしかないため nil
    let localizedName = scanner.localizedNameFromLproj(for: appPath, locale: "fr")

    #expect(localizedName == nil)
  }
}

// MARK: - App 情報抽出テスト

@Suite("AppScanner App Info Extraction")
struct AppScannerAppInfoExtractionTests {

  @Test func extractsAppInfoWithDisplayName() throws {
    let tmpDir = try makeTempDir()
    defer { cleanup(tmpDir) }

    let appPath = try createFakeApp(
      at: tmpDir, name: "DisplayNameApp.app",
      displayName: "Display Name App",
      bundleName: "DisplayNameApp"
    )

    let scanner = AppScanner()
    let appItem = scanner.extractAppInfo(from: appPath)

    #expect(appItem != nil)
    #expect(appItem!.path == appPath)
    let systemName = scanner.localizedSystemName(for: appPath)
    let expectedName = systemName ?? "Display Name App"
    #expect(appItem!.name == expectedName)
  }

  @Test func extractsAppInfoWithBundleNameOnly() throws {
    let tmpDir = try makeTempDir()
    defer { cleanup(tmpDir) }

    let appPath = try createFakeApp(
      at: tmpDir, name: "BundleOnly.app",
      bundleName: "BundleOnlyApp"
    )

    let scanner = AppScanner()
    let appItem = scanner.extractAppInfo(from: appPath)

    #expect(appItem != nil)
    let systemName = scanner.localizedSystemName(for: appPath)
    let expectedName = systemName ?? "BundleOnlyApp"
    #expect(appItem!.name == expectedName)
    let expectedOriginalName: String? =
      expectedName == "BundleOnlyApp"
      ? nil
      : "BundleOnlyApp"
    #expect(appItem!.originalName == expectedOriginalName)
  }

  @Test func fallsBackToFileNameWhenNoPlist() throws {
    let tmpDir = try makeTempDir()
    defer { cleanup(tmpDir) }

    // Info.plist なしのバンドル
    let appPath = (tmpDir as NSString).appendingPathComponent("FallbackApp.app")
    let contentsPath = (appPath as NSString).appendingPathComponent("Contents")
    try FileManager.default.createDirectory(
      atPath: contentsPath, withIntermediateDirectories: true)

    let scanner = AppScanner()
    let appItem = scanner.extractAppInfo(from: appPath)

    #expect(appItem != nil)
    #expect(appItem!.name == "FallbackApp")
    #expect(appItem!.path == appPath)
  }
}

// MARK: - 除外アプリフィルタリングテスト

@Suite("AppScanner Excluded Apps")
struct AppScannerExcludedAppsTests {

  @Test func filtersExcludedApps() async throws {
    let tmpDir = try makeTempDir()
    defer { cleanup(tmpDir) }

    _ = try createFakeApp(at: tmpDir, name: "Keep.app", bundleName: "Keep")
    let excludedPath = try createFakeApp(
      at: tmpDir, name: "Exclude.app", bundleName: "Exclude")
    _ = try createFakeApp(at: tmpDir, name: "AlsoKeep.app", bundleName: "AlsoKeep")

    let scanner = AppScanner(
      scanTargets: [AppScanner.ScanTarget(path: tmpDir, maxDepth: 1)]
    )
    let results = try await scanner.scanApplications(excludedApps: [excludedPath])

    #expect(results.count == 2)
    #expect(!results.contains { $0.path == excludedPath })
    #expect(results.contains { $0.path.hasSuffix("Keep.app") })
    #expect(results.contains { $0.path.hasSuffix("AlsoKeep.app") })
  }

  @Test func filtersExcludedAppsByDisplayName() async throws {
    let tmpDir = try makeTempDir()
    defer { cleanup(tmpDir) }

    _ = try createFakeApp(at: tmpDir, name: "Keep.app", displayName: "Keep")
    let excludedPath = try createFakeApp(
      at: tmpDir,
      name: "Exclude.app",
      displayName: "Exclude Display",
      bundleName: "ExcludeBundle"
    )

    let scanner = AppScanner(
      scanTargets: [AppScanner.ScanTarget(path: tmpDir, maxDepth: 1)]
    )
    let results = try await scanner.scanApplications(excludedApps: ["Exclude Display"])

    #expect(results.count == 1)
    #expect(!results.contains { $0.path == excludedPath })
    #expect(results.contains { $0.path.hasSuffix("Keep.app") })
  }

  @Test func filtersExcludedAppsByBundleFileName() async throws {
    let tmpDir = try makeTempDir()
    defer { cleanup(tmpDir) }

    _ = try createFakeApp(at: tmpDir, name: "Keep.app", bundleName: "Keep")
    let excludedPath = try createFakeApp(
      at: tmpDir,
      name: "Exclude.app",
      bundleName: "Exclude"
    )

    let scanner = AppScanner(
      scanTargets: [AppScanner.ScanTarget(path: tmpDir, maxDepth: 1)]
    )
    let results = try await scanner.scanApplications(excludedApps: ["Exclude.app"])

    #expect(results.count == 1)
    #expect(!results.contains { $0.path == excludedPath })
    #expect(results.contains { $0.path.hasSuffix("Keep.app") })
  }

  @Test func emptyExcludedAppsKeepsAll() async throws {
    let tmpDir = try makeTempDir()
    defer { cleanup(tmpDir) }

    _ = try createFakeApp(at: tmpDir, name: "App1.app", bundleName: "App1")
    _ = try createFakeApp(at: tmpDir, name: "App2.app", bundleName: "App2")

    let scanner = AppScanner(
      scanTargets: [AppScanner.ScanTarget(path: tmpDir, maxDepth: 1)]
    )
    let results = try await scanner.scanApplications(excludedApps: [])

    #expect(results.count == 2)
  }
}

// MARK: - フルスキャンパイプラインテスト

@Suite("AppScanner Full Scan")
struct AppScannerFullScanTests {

  @Test func scanMultipleDirectories() async throws {
    let tmpDir1 = try makeTempDir()
    let tmpDir2 = try makeTempDir()
    defer {
      cleanup(tmpDir1)
      cleanup(tmpDir2)
    }

    _ = try createFakeApp(at: tmpDir1, name: "App1.app", bundleName: "App1")
    _ = try createFakeApp(at: tmpDir2, name: "App2.app", bundleName: "App2")

    let scanner = AppScanner(
      scanTargets: [
        AppScanner.ScanTarget(path: tmpDir1, maxDepth: 1),
        AppScanner.ScanTarget(path: tmpDir2, maxDepth: 1),
      ]
    )
    let results = try await scanner.scanApplications(excludedApps: [])

    #expect(results.count == 2)
    #expect(results.contains { $0.name == "App1" })
    #expect(results.contains { $0.name == "App2" })
  }

  @Test func resultsSortedByName() async throws {
    let tmpDir = try makeTempDir()
    defer { cleanup(tmpDir) }

    _ = try createFakeApp(at: tmpDir, name: "Zebra.app", bundleName: "Zebra")
    _ = try createFakeApp(at: tmpDir, name: "Alpha.app", bundleName: "Alpha")
    _ = try createFakeApp(at: tmpDir, name: "Middle.app", bundleName: "Middle")

    let scanner = AppScanner(
      scanTargets: [AppScanner.ScanTarget(path: tmpDir, maxDepth: 1)]
    )
    let results = try await scanner.scanApplications(excludedApps: [])

    #expect(results.count == 3)
    #expect(results[0].name == "Alpha")
    #expect(results[1].name == "Middle")
    #expect(results[2].name == "Zebra")
  }

  @Test func deduplicatesAppsByPath() async throws {
    let tmpDir = try makeTempDir()
    defer { cleanup(tmpDir) }

    _ = try createFakeApp(at: tmpDir, name: "DupApp.app", bundleName: "DupApp")

    // 同じディレクトリを2回スキャン
    let scanner = AppScanner(
      scanTargets: [
        AppScanner.ScanTarget(path: tmpDir, maxDepth: 1),
        AppScanner.ScanTarget(path: tmpDir, maxDepth: 1),
      ]
    )
    let results = try await scanner.scanApplications(excludedApps: [])

    #expect(results.count == 1)
  }

  @Test func scanEmptyDirectoriesReturnsEmpty() async throws {
    let tmpDir = try makeTempDir()
    defer { cleanup(tmpDir) }

    let scanner = AppScanner(
      scanTargets: [AppScanner.ScanTarget(path: tmpDir, maxDepth: 2)]
    )
    let results = try await scanner.scanApplications(excludedApps: [])

    #expect(results.isEmpty)
  }

  @Test func scanNonExistentDirectorySkipsGracefully() async throws {
    let scanner = AppScanner(
      scanTargets: [
        AppScanner.ScanTarget(
          path: "/nonexistent/path/\(UUID().uuidString)", maxDepth: 2)
      ]
    )
    let results = try await scanner.scanApplications(excludedApps: [])

    #expect(results.isEmpty)
  }
}

// MARK: - ローカライズ名解決テスト

@Suite("AppScanner Localized System Name")
struct AppScannerLocalizedSystemNameTests {

  @Test func returnsNameForExistingApp() throws {
    let tmpDir = try makeTempDir()
    defer { cleanup(tmpDir) }

    let appPath = try createFakeApp(
      at: tmpDir, name: "FakeApp.app", bundleName: "FakeApp")

    let scanner = AppScanner()
    let name = scanner.localizedSystemName(for: appPath)

    if let name {
      #expect(!name.isEmpty)
      // Finder の拡張子表示設定にかかわらず .app は除去される
      #expect(!name.hasSuffix(".app"))
    } else {
      #expect(name == nil)
    }
  }

  @Test func returnsNilForNonExistentPath() {
    let scanner = AppScanner()
    let name = scanner.localizedSystemName(
      for: "/nonexistent/path/\(UUID().uuidString).app")

    #expect(name == nil)
  }
}

// MARK: - AppItem 除外判定テスト

@Suite("AppScanner isExcluded(app:)")
struct AppScannerIsExcludedItemTests {

  private let scanner = AppScanner()

  @Test("パス・バンドルファイル名・バンドル名・表示名・元名のいずれでも除外できる")
  func matchesAllIdentifierForms() {
    let app = AppItem(
      name: "プレビュー",
      path: "/Applications/Preview.app",
      originalName: "Preview"
    )

    #expect(scanner.isExcluded(app, excludedApps: ["/Applications/Preview.app"]))
    #expect(scanner.isExcluded(app, excludedApps: ["Preview.app"]))
    #expect(scanner.isExcluded(app, excludedApps: ["Preview"]))
    #expect(scanner.isExcluded(app, excludedApps: ["プレビュー"]))
  }

  @Test("該当しないアプリは除外されない")
  func doesNotMatchUnrelatedApp() {
    let app = AppItem(name: "Safari", path: "/Applications/Safari.app")

    #expect(!scanner.isExcluded(app, excludedApps: ["Preview", "Mail.app"]))
    #expect(!scanner.isExcluded(app, excludedApps: []))
  }

  @Test("scanApplications の除外結果とフィルタ適用結果が一致する")
  func filterMatchesScanResults() async throws {
    let tmpDir = try makeTempDir()
    defer { cleanup(tmpDir) }

    _ = try createFakeApp(at: tmpDir, name: "Keep.app", bundleName: "Keep")
    _ = try createFakeApp(at: tmpDir, name: "Exclude.app", bundleName: "Exclude")

    let scanner = AppScanner(
      scanTargets: [AppScanner.ScanTarget(path: tmpDir, maxDepth: 1)]
    )
    let excluded = ["Exclude.app"]

    let scanFiltered = try await scanner.scanApplications(excludedApps: excluded)
    let allApps = try await scanner.scanApplications(excludedApps: [])
    let postFiltered = allApps.filter { !scanner.isExcluded($0, excludedApps: excluded) }

    #expect(scanFiltered.map(\.path) == postFiltered.map(\.path))
  }
}
