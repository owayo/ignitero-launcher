import Foundation
import os

// MARK: - ファイルシステムエラー

public enum FileSystemError: Error, Sendable {
  case directoryNotFound(String)
}

// MARK: - ファイルシステムプロバイダープロトコル

public protocol FileSystemProvider: Sendable {
  func contentsOfDirectory(atPath path: String) throws -> [String]
  func isDirectory(atPath path: String) -> Bool
  func fileExists(atPath path: String) -> Bool
}

// MARK: - デフォルトファイルシステムプロバイダー

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

// MARK: - スキャン結果

public struct ScanResult: Sendable, Equatable {
  public let directories: [DirectoryItem]
  public let apps: [AppItem]

  public init(directories: [DirectoryItem], apps: [AppItem]) {
    self.directories = directories
    self.apps = apps
  }
}

// MARK: - DirectoryScanner プロトコル

public protocol DirectoryScannerProtocol: Sendable {
  /// 登録ディレクトリをスキャンする。呼び出し元のアクターを占有しない。
  @concurrent
  func scan(directories: [RegisteredDirectory]) async throws -> ScanResult
}

// MARK: - DirectoryScanner 本体

public struct DirectoryScanner: DirectoryScannerProtocol, Sendable {
  private static let logger = Logger(
    subsystem: "com.ignitero.launcher", category: "DirectoryScanner")

  private let fileSystemProvider: FileSystemProvider

  public init(fileSystemProvider: FileSystemProvider = DefaultFileSystemProvider()) {
    self.fileSystemProvider = fileSystemProvider
  }

  @concurrent
  public func scan(directories: [RegisteredDirectory]) async throws -> ScanResult {
    // 出現順を保ったままパスで一意化する。`directories` テーブルの主キーは path で、
    // 保存は配列順の INSERT OR REPLACE（後勝ち）のため、同一パスを重複したまま渡すと
    // 後から現れたエントリが先のエントリを無音で上書きしてしまう。
    // 明示登録の親エントリ（検索キーワード・エディタ指定を持つ）は、別の登録の子として
    // 自動列挙されたエントリより優先する。同種同士は先勝ちで決定的にする。
    var directoryOrder: [String] = []
    var directoryByPath: [String: (item: DirectoryItem, isExplicit: Bool)] = [:]
    var allApps: [AppItem] = []

    func addDirectory(_ item: DirectoryItem, isExplicit: Bool) {
      guard let existing = directoryByPath[item.path] else {
        directoryOrder.append(item.path)
        directoryByPath[item.path] = (item, isExplicit)
        return
      }
      // 明示登録が自動列挙を置き換える場合のみ差し替える。
      guard isExplicit, !existing.isExplicit else { return }
      directoryByPath[item.path] = (item, isExplicit)
    }

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
        let parentName = parentDirectoryName(
          for: registered,
          normalizedPath: normalizedPath
        )
        let parentEditor = editorForOpenMode(
          registered.parentOpenMode, editor: registered.parentEditor)
        addDirectory(
          DirectoryItem(name: parentName, path: normalizedPath, editor: parentEditor),
          isExplicit: true)
      }

      // 直下の子エントリを処理
      for entry in contents {
        // 隠しエントリをスキップ
        guard !entry.hasPrefix(".") else { continue }

        let childPath = (normalizedPath as NSString).appendingPathComponent(entry)

        // .app バンドルかどうかを判定（.app 拡張子の通常ファイルを誤って起動対象にしない）
        if entry.hasSuffix(".app") {
          if registered.scanForApps, fileSystemProvider.isDirectory(atPath: childPath) {
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
        addDirectory(
          DirectoryItem(name: entry, path: childPath, editor: subEditor),
          isExplicit: false)
      }
    }

    return ScanResult(
      directories: directoryOrder.compactMap { directoryByPath[$0]?.item },
      apps: allApps
    )
  }

  // MARK: - 非公開ヘルパー

  private func normalizePath(_ path: String) -> String {
    if path != "/", path.hasSuffix("/") {
      return String(path.dropLast())
    }
    return path
  }

  private func lastPathComponent(of path: String) -> String {
    (path as NSString).lastPathComponent
  }

  private func parentDirectoryName(
    for registered: RegisteredDirectory,
    normalizedPath: String
  ) -> String {
    if let keyword = registered.parentSearchKeyword?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !keyword.isEmpty
    {
      return keyword
    }
    return lastPathComponent(of: normalizedPath)
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
