import Foundation
import os

// MARK: - FileSystem Error

public enum FileSystemError: Error, Sendable {
  case directoryNotFound(String)
}

// MARK: - FileSystem Provider Protocol

public protocol FileSystemProvider: Sendable {
  func contentsOfDirectory(atPath path: String) throws -> [String]
  func isDirectory(atPath path: String) -> Bool
  func fileExists(atPath path: String) -> Bool
}

// MARK: - Default FileSystem Provider

public struct DefaultFileSystemProvider: FileSystemProvider, Sendable {
  public init() {}

  public func contentsOfDirectory(atPath path: String) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: path)
  }

  public func isDirectory(atPath path: String) -> Bool {
    var isDir: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
    return exists && isDir.boolValue
  }

  public func fileExists(atPath path: String) -> Bool {
    FileManager.default.fileExists(atPath: path)
  }
}

// MARK: - Scan Result

public struct ScanResult: Sendable, Equatable {
  public let directories: [DirectoryItem]
  public let apps: [AppItem]

  public init(directories: [DirectoryItem], apps: [AppItem]) {
    self.directories = directories
    self.apps = apps
  }
}

// MARK: - DirectoryScanner Protocol

public protocol DirectoryScannerProtocol: Sendable {
  func scan(directories: [RegisteredDirectory]) throws -> ScanResult
}

// MARK: - DirectoryScanner

public struct DirectoryScanner: DirectoryScannerProtocol, Sendable {
  private static let logger = Logger(
    subsystem: "com.ignitero.launcher", category: "DirectoryScanner")

  private let fileSystemProvider: FileSystemProvider

  public init(fileSystemProvider: FileSystemProvider = DefaultFileSystemProvider()) {
    self.fileSystemProvider = fileSystemProvider
  }

  public func scan(directories: [RegisteredDirectory]) throws -> ScanResult {
    var allDirectories: [DirectoryItem] = []
    var allApps: [AppItem] = []

    for registered in directories {
      let normalizedPath = normalizePath(registered.path)

      // ディレクトリ内容の取得を試行。失敗時はスキップ
      let contents: [String]
      do {
        contents = try fileSystemProvider.contentsOfDirectory(atPath: normalizedPath)
      } catch {
        Self.logger.warning(
          "Skipping directory \(normalizedPath): \(error.localizedDescription)")
        continue
      }

      // 親ディレクトリを DirectoryItem として追加（mode が .none ならスキップ）
      if registered.parentOpenMode != .none {
        let parentName = lastPathComponent(of: normalizedPath)
        let parentEditor = editorForOpenMode(
          registered.parentOpenMode, editor: registered.parentEditor)
        allDirectories.append(
          DirectoryItem(name: parentName, path: normalizedPath, editor: parentEditor))
      }

      // 直下の子エントリを処理
      for entry in contents {
        // 隠しエントリをスキップ
        guard !entry.hasPrefix(".") else { continue }

        let childPath = normalizedPath + "/" + entry

        // .app バンドルかどうかを判定
        if entry.hasSuffix(".app") {
          if registered.scanForApps {
            let appName = String(entry.dropLast(4))  // ".app" サフィックスを除去
            allApps.append(AppItem(name: appName, path: childPath))
          }
          // .app バンドルは scanForApps の設定に関わらずディレクトリ項目には含めない
          continue
        }

        // ディレクトリのみ対象（通常ファイルは除外）。subdirs mode が .none ならスキップ
        guard registered.subdirsOpenMode != .none,
          fileSystemProvider.isDirectory(atPath: childPath)
        else { continue }

        let subEditor = editorForOpenMode(
          registered.subdirsOpenMode, editor: registered.subdirsEditor)
        allDirectories.append(
          DirectoryItem(name: entry, path: childPath, editor: subEditor))
      }
    }

    return ScanResult(directories: allDirectories, apps: allApps)
  }

  // MARK: - Private Helpers

  private func normalizePath(_ path: String) -> String {
    if path.hasSuffix("/") {
      return String(path.dropLast())
    }
    return path
  }

  private func lastPathComponent(of path: String) -> String {
    (path as NSString).lastPathComponent
  }

  private func editorForOpenMode(_ mode: OpenMode, editor: String?) -> String? {
    switch mode {
    case .editor:
      return editor
    case .finder, .none:
      return nil
    }
  }
}
