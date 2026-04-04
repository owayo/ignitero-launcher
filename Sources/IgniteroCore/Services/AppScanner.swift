import Foundation
import os

// MARK: - AppScannerProtocol

public protocol AppScannerProtocol: Sendable {
  func scanApplications(excludedApps: [String]) throws -> [AppItem]
}

// MARK: - AppScanner

public struct AppScanner: AppScannerProtocol, Sendable {
  private static let logger = Logger(subsystem: "com.ignitero.launcher", category: "AppScanner")

  // MARK: - ScanTarget

  public struct ScanTarget: Sendable, Equatable {
    public let path: String
    public let maxDepth: Int

    public init(path: String, maxDepth: Int) {
      self.path = path
      self.maxDepth = maxDepth
    }
  }

  // MARK: - Properties

  public let scanTargets: [ScanTarget]
  private let iconCacheManager: IconCacheManager

  // MARK: - Default Targets

  public static let defaultScanTargets: [ScanTarget] = [
    ScanTarget(path: "/Applications", maxDepth: 2),
    ScanTarget(path: "/System/Applications", maxDepth: 3),
    ScanTarget(
      path: NSString(string: "~/Applications").expandingTildeInPath,
      maxDepth: 3
    ),
  ]

  // MARK: - Initialization

  public init(
    scanTargets: [ScanTarget]? = nil,
    iconCacheManager: IconCacheManager = IconCacheManager()
  ) {
    self.scanTargets = scanTargets ?? Self.defaultScanTargets
    self.iconCacheManager = iconCacheManager
  }

  // MARK: - Core Scan

  public func scanApplications(excludedApps: [String]) throws -> [AppItem] {
    let excludedSet = Set(excludedApps)
    var seenPaths = Set<String>()
    var results: [AppItem] = []

    for target in scanTargets {
      let bundles = findAppBundles(in: target.path, maxDepth: target.maxDepth)
      for bundlePath in bundles {
        // 重複排除
        guard !seenPaths.contains(bundlePath) else { continue }
        seenPaths.insert(bundlePath)

        // 除外アプリフィルタ
        guard !excludedSet.contains(bundlePath) else {
          Self.logger.debug("Excluded app: \(bundlePath)")
          continue
        }

        if var appItem = extractAppInfo(from: bundlePath) {
          // アイコンキャッシュ生成
          if let iconSrc = iconFilePath(for: bundlePath) {
            do {
              let cachedPath = try iconCacheManager.cacheIcon(
                from: iconSrc, for: bundlePath)
              appItem = AppItem(
                name: appItem.name,
                path: appItem.path,
                iconPath: cachedPath,
                originalName: appItem.originalName
              )
            } catch {
              Self.logger.warning(
                "Failed to cache icon for \(bundlePath): \(error.localizedDescription)")
            }
          }
          results.append(appItem)
        }
      }
    }

    // 名前でソート
    results.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    return results
  }

  // MARK: - Bundle Discovery

  /// 指定ディレクトリ内の .app バンドルを再帰的に検索する
  public func findAppBundles(in directory: String, maxDepth: Int) -> [String] {
    let fm = FileManager.default
    guard fm.fileExists(atPath: directory) else { return [] }

    var results: [String] = []
    scanDirectory(directory, currentDepth: 1, maxDepth: maxDepth, results: &results)
    return results
  }

  private func scanDirectory(
    _ path: String,
    currentDepth: Int,
    maxDepth: Int,
    results: inout [String]
  ) {
    guard currentDepth <= maxDepth else { return }

    let fm = FileManager.default
    guard
      let contents = try? fm.contentsOfDirectory(atPath: path)
    else { return }

    for item in contents {
      // 隠しファイルをスキップ
      guard !item.hasPrefix(".") else { continue }

      let fullPath = (path as NSString).appendingPathComponent(item)

      var isDirectory: ObjCBool = false
      guard fm.fileExists(atPath: fullPath, isDirectory: &isDirectory),
        isDirectory.boolValue
      else { continue }

      if item.hasSuffix(".app") {
        results.append(fullPath)
        // .app バンドル内には降りない
      } else {
        // 通常のディレクトリはさらに深く探索
        scanDirectory(
          fullPath,
          currentDepth: currentDepth + 1,
          maxDepth: maxDepth,
          results: &results
        )
      }
    }
  }

  // MARK: - Info.plist Extraction

  /// Info.plist から CFBundleDisplayName と CFBundleName を抽出する
  public func plistNames(for appPath: String) -> (
    displayName: String?, bundleName: String?
  ) {
    let plistPath = (appPath as NSString).appendingPathComponent("Contents/Info.plist")
    guard let plistData = FileManager.default.contents(atPath: plistPath),
      let plist =
        try? PropertyListSerialization.propertyList(
          from: plistData, options: [], format: nil) as? [String: Any]
    else {
      return (nil, nil)
    }

    let displayName = plist["CFBundleDisplayName"] as? String
    let bundleName = plist["CFBundleName"] as? String
    return (displayName, bundleName)
  }

  /// Info.plist からアイコンファイルのパスを解決する
  public func iconFilePath(for appPath: String) -> String? {
    let plistPath = (appPath as NSString).appendingPathComponent("Contents/Info.plist")
    guard let plistData = FileManager.default.contents(atPath: plistPath),
      let plist =
        try? PropertyListSerialization.propertyList(
          from: plistData, options: [], format: nil) as? [String: Any]
    else {
      return nil
    }

    let fm = FileManager.default
    let resourcesPath = (appPath as NSString).appendingPathComponent("Contents/Resources")

    // CFBundleIconFile を優先
    if let iconFile = plist["CFBundleIconFile"] as? String {
      let resolvedPath = resolveIconFile(iconFile, in: resourcesPath)
      if let resolvedPath, fm.fileExists(atPath: resolvedPath) {
        return resolvedPath
      }
    }

    // CFBundleIconName にフォールバック
    if let iconName = plist["CFBundleIconName"] as? String {
      let resolvedPath = resolveIconFile(iconName, in: resourcesPath)
      if let resolvedPath, fm.fileExists(atPath: resolvedPath) {
        return resolvedPath
      }
    }

    return nil
  }

  private func resolveIconFile(_ iconFile: String, in resourcesPath: String) -> String? {
    // 拡張子が .icns の場合そのまま使用
    if iconFile.hasSuffix(".icns") {
      return (resourcesPath as NSString).appendingPathComponent(iconFile)
    }
    // 拡張子なしの場合 .icns を付与
    return (resourcesPath as NSString).appendingPathComponent("\(iconFile).icns")
  }

  // MARK: - Localized Name Resolution

  /// mdls を使用してローカライズされた表示名を取得する
  public func localizedNameViaMdls(for appPath: String) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/mdls")
    process.arguments = ["-name", "kMDItemDisplayName", "-raw", appPath]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
      // パイプバッファが満杯になった場合のデッドロックを防ぐため、
      // waitUntilExit の前に readDataToEndOfFile を呼ぶ。
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else { return nil }
      return Self.parseLocalizedName(from: data)
    } catch {
      Self.logger.debug("mdls failed for \(appPath): \(error.localizedDescription)")
      return nil
    }
  }

  /// mdls の出力データからローカライズ名をパースする。
  private static func parseLocalizedName(from data: Data) -> String? {
    guard
      let output = String(data: data, encoding: .utf8)?.trimmingCharacters(
        in: .whitespacesAndNewlines)
    else { return nil }

    // mdls は見つからない場合 "(null)" を返す
    if output.isEmpty || output == "(null)" {
      return nil
    }

    return output
  }

  /// .lproj/InfoPlist.strings からローカライズ名を取得する
  public func localizedNameFromLproj(for appPath: String, locale: String? = nil) -> String? {
    let resourcesPath = (appPath as NSString).appendingPathComponent("Contents/Resources")
    let fm = FileManager.default

    // 優先するロケールリスト
    let preferredLocales: [String]
    if let locale {
      preferredLocales = [locale]
    } else {
      preferredLocales =
        Locale.preferredLanguages.compactMap { lang -> String in
          // "ja-JP" -> "ja" 形式にする
          String(lang.prefix(while: { $0 != "-" }))
        } + ["en"]
    }

    for lang in preferredLocales {
      let lprojPath = (resourcesPath as NSString).appendingPathComponent("\(lang).lproj")
      let stringsPath = (lprojPath as NSString).appendingPathComponent("InfoPlist.strings")

      guard fm.fileExists(atPath: stringsPath) else { continue }

      // strings ファイルをパースする
      if let name = parseStringsFile(at: stringsPath, key: "CFBundleDisplayName") {
        return name
      }
      if let name = parseStringsFile(at: stringsPath, key: "CFBundleName") {
        return name
      }
    }

    return nil
  }

  private func parseStringsFile(at path: String, key: String) -> String? {
    guard let data = FileManager.default.contents(atPath: path) else { return nil }

    // まず NSDictionary として読み込みを試行（バイナリ plist 形式にも対応）
    if let dict = NSDictionary(contentsOfFile: path) as? [String: String] {
      return dict[key]
    }

    // テキスト形式の .strings ファイルをパース
    guard let content = String(data: data, encoding: .utf8) else { return nil }

    // パターン: "KEY" = "VALUE";
    let pattern = #""\#(key)"\s*=\s*"([^"]*)";"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(
        in: content,
        range: NSRange(content.startIndex..., in: content)
      ),
      let valueRange = Range(match.range(at: 1), in: content)
    else { return nil }

    return String(content[valueRange])
  }

  // MARK: - App Info Assembly

  /// .app バンドルから AppItem を組み立てる
  public func extractAppInfo(from appPath: String) -> AppItem? {
    let (displayName, bundleName) = plistNames(for: appPath)

    // ローカライズ名の取得を試行
    let localizedName =
      localizedNameViaMdls(for: appPath)
      ?? localizedNameFromLproj(for: appPath)

    // 名前の優先順位: ローカライズ名 > CFBundleDisplayName > CFBundleName > ファイル名
    let name =
      localizedName
      ?? displayName
      ?? bundleName
      ?? fileNameWithoutExtension(appPath)

    // originalName: bundleName（ローカライズ名と異なる場合のみ設定）
    let originalName: String?
    if let bundleName, bundleName != name {
      originalName = bundleName
    } else if let displayName, displayName != name {
      originalName = displayName
    } else {
      originalName = nil
    }

    return AppItem(
      name: name,
      path: appPath,
      iconPath: nil,  // アイコンは scanApplications で後から設定
      originalName: originalName
    )
  }

  private func fileNameWithoutExtension(_ path: String) -> String {
    let fileName = (path as NSString).lastPathComponent
    if fileName.hasSuffix(".app") {
      return String(fileName.dropLast(4))
    }
    return fileName
  }
}

// MARK: - AppScannerError

public enum AppScannerError: Error, Sendable {
  case scanFailed(String)
  case plistParsingFailed(String)
}
