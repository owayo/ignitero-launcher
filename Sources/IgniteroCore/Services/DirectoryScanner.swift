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

      // Attempt to list directory contents; skip on failure
      let contents: [String]
      do {
        contents = try fileSystemProvider.contentsOfDirectory(atPath: normalizedPath)
      } catch {
        Self.logger.warning(
          "Skipping directory \(normalizedPath): \(error.localizedDescription)")
        continue
      }

      // Add parent directory as a DirectoryItem (skip if mode is .none)
      if registered.parentOpenMode != .none {
        let parentName = lastPathComponent(of: normalizedPath)
        let parentEditor = editorForOpenMode(
          registered.parentOpenMode, editor: registered.parentEditor)
        allDirectories.append(
          DirectoryItem(name: parentName, path: normalizedPath, editor: parentEditor))
      }

      // Process immediate children
      for entry in contents {
        // Skip hidden entries
        guard !entry.hasPrefix(".") else { continue }

        let childPath = normalizedPath + "/" + entry

        // Check if it's a .app bundle
        if entry.hasSuffix(".app") {
          if registered.scanForApps {
            let appName = String(entry.dropLast(4))  // Remove ".app" suffix
            allApps.append(AppItem(name: appName, path: childPath))
          }
          // .app bundles are not included as directory items regardless of scanForApps
          continue
        }

        // Only include directories (not regular files), skip if subdirs mode is .none
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
