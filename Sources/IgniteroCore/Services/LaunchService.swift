import AppKit
import Foundation
import os

// MARK: - Launching プロトコル

public protocol Launching: Sendable {
  func launchApp(at path: String) async throws
  func openDirectory(_ path: String, editor: EditorType?) async throws
  func openInTerminal(_ path: String, terminal: TerminalType) async throws
  func executeCommand(
    _ command: String, workingDirectory: String?, terminal: TerminalType
  ) async throws
  func availableEditors() -> [EditorInfo]
  func availableTerminals() -> [TerminalInfo]
}

// MARK: - LaunchService 本体

public struct LaunchService: Launching, Sendable {
  private static let logger = Logger(subsystem: "com.ignitero.launcher", category: "Launch")
  private static let commandScriptPrefix = "ignitero-"
  private static let commandScriptExtension = "command"
  private static let staleCommandScriptTTL: TimeInterval = 5 * 60
  private static let terminalSystemPath = "/System/Applications/Utilities/Terminal.app"
  private static let terminalLegacyPath = "/Applications/Utilities/Terminal.app"
  private static let cmuxCLIPath: String = {
    // Homebrew (Apple Silicon → Intel フォールバック) → アプリバンドル内 CLI の順に探索
    let candidates = [
      "/opt/homebrew/bin/cmux",
      "/usr/local/bin/cmux",
      "/Applications/cmux.app/Contents/Resources/bin/cmux",
    ]
    let fm = FileManager.default
    return candidates.first { fm.fileExists(atPath: $0) }
      ?? "/Applications/cmux.app/Contents/Resources/bin/cmux"
  }()

  public init() {}

  // MARK: - エディタアプリ名マッピング

  public static func appName(for editor: EditorType) -> String {
    switch editor {
    case .windsurf: "Windsurf.app"
    case .cursor: "Cursor.app"
    case .vscode: "Visual Studio Code.app"
    case .antigravity: "Antigravity.app"
    case .zed: "Zed.app"
    }
  }

  public static func displayName(for editor: EditorType) -> String {
    switch editor {
    case .windsurf: "Windsurf"
    case .cursor: "Cursor"
    case .vscode: "Visual Studio Code"
    case .antigravity: "Antigravity"
    case .zed: "Zed"
    }
  }

  // MARK: - ターミナルアプリ名マッピング

  public static func appName(for terminal: TerminalType) -> String {
    switch terminal {
    case .terminal: "Terminal.app"
    case .iterm2: "iTerm.app"
    case .ghostty: "Ghostty.app"
    case .warp: "Warp.app"
    case .cmux: "cmux.app"
    }
  }

  public static func displayName(for terminal: TerminalType) -> String {
    switch terminal {
    case .terminal: "Terminal"
    case .iterm2: "iTerm2"
    case .ghostty: "Ghostty"
    case .warp: "Warp"
    case .cmux: "cmux"
    }
  }

  // MARK: - アプリケーションパス

  public static func applicationPath(for editor: EditorType) -> String {
    "/Applications/\(appName(for: editor))"
  }

  public static func applicationPath(for terminal: TerminalType) -> String {
    switch terminal {
    case .terminal:
      if FileManager.default.fileExists(atPath: terminalSystemPath) {
        terminalSystemPath
      } else {
        terminalLegacyPath
      }
    case .iterm2: "/Applications/iTerm.app"
    case .ghostty: "/Applications/Ghostty.app"
    case .warp: "/Applications/Warp.app"
    case .cmux: "/Applications/cmux.app"
    }
  }

  // MARK: - ワークスペース検出

  public static func workspaceGlobPattern(for directoryPath: String) -> String {
    let normalized = normalizedDirectoryPath(directoryPath)
    return (normalized as NSString).appendingPathComponent("*.code-workspace")
  }

  private func findWorkspaceFile(in directoryPath: String) -> String? {
    let fm = FileManager.default
    let normalized = Self.normalizedDirectoryPath(directoryPath)
    guard let contents = try? fm.contentsOfDirectory(atPath: normalized) else {
      return nil
    }
    return contents.first { $0.hasSuffix(".code-workspace") }
      .map { (normalized as NSString).appendingPathComponent($0) }
  }

  // MARK: - AppleScript 生成

  public static func appleScript(
    for terminal: TerminalType,
    command: String,
    workingDirectory: String?
  ) -> String {
    let fullCommand: String
    if let wd = workingDirectory {
      fullCommand = "cd \(shellEscaped(wd)) && \(command)"
    } else {
      fullCommand = command
    }
    let scriptCommand = appleScriptEscaped(fullCommand)

    switch terminal {
    case .terminal:
      return """
        tell application "Terminal"
          do script "\(scriptCommand)"
          activate
        end tell
        """
    case .iterm2:
      return """
        tell application "iTerm"
          create window with default profile
          tell current session of current window
            write text "\(scriptCommand)"
          end tell
          activate
        end tell
        """
    case .ghostty:
      // Ghostty 1.3.0 以降の公式 AppleScript API を使用
      return """
        tell application "Ghostty"
          activate
          set w to make new window
          set term to focused terminal of selected tab of w
          input text "\(scriptCommand)\\n" to term
        end tell
        """
    case .cmux:
      return """
        tell application "cmux"
          activate
          set w to new window
          set term to focused terminal of selected tab of w
          input text "\(scriptCommand)\\n" to term
        end tell
        """
    default:
      return ""
    }
  }

  // MARK: - .command スクリプト生成

  public static func commandScript(
    command: String,
    workingDirectory: String?
  ) -> String {
    var lines = ["#!/bin/bash"]
    if let wd = workingDirectory {
      lines.append("cd \(shellEscaped(wd))")
    }
    lines.append(command)
    lines.append("exit")
    return lines.joined(separator: "\n") + "\n"
  }

  private static func shellEscaped(_ value: String) -> String {
    // POSIX シェル向けに単一引用符でラップし、内部の単一引用符を安全にエスケープする。
    let escaped = value.replacingOccurrences(of: "'", with: "'\"'\"'")
    return "'\(escaped)'"
  }

  private static func normalizedDirectoryPath(_ path: String) -> String {
    if path != "/", path.hasSuffix("/") {
      return String(path.dropLast())
    }
    return path
  }

  private static func appleScriptEscaped(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\n", with: "\\n")
      .replacingOccurrences(of: "\r", with: "")
  }

  /// 一時 .command ファイルの増殖を防ぐため、古いスクリプトを削除する。
  @discardableResult
  static func cleanupStaleCommandScripts(
    in directory: URL = FileManager.default.temporaryDirectory,
    olderThan threshold: TimeInterval = staleCommandScriptTTL,
    now: Date = Date()
  ) -> Int {
    let fm = FileManager.default
    guard
      let files = try? fm.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [
          .isRegularFileKey, .contentModificationDateKey, .creationDateKey,
        ],
        options: [.skipsHiddenFiles]
      )
    else {
      return 0
    }

    var removedCount = 0
    for fileURL in files {
      let fileName = fileURL.lastPathComponent
      guard
        fileName.hasPrefix(commandScriptPrefix),
        fileURL.pathExtension == commandScriptExtension
      else { continue }

      guard
        let values = try? fileURL.resourceValues(forKeys: [
          .isRegularFileKey, .contentModificationDateKey, .creationDateKey,
        ]),
        values.isRegularFile ?? false
      else { continue }

      let modifiedAt = values.contentModificationDate ?? values.creationDate ?? now
      guard now.timeIntervalSince(modifiedAt) >= threshold else { continue }

      do {
        try fm.removeItem(at: fileURL)
        removedCount += 1
      } catch {
        Self.logger.debug(
          "Failed to remove stale command script: \(fileURL.path, privacy: .public)")
      }
    }

    return removedCount
  }

  // MARK: - 実行処理

  public func launchApp(at path: String) async throws {
    let url = URL(fileURLWithPath: path)
    let config = NSWorkspace.OpenConfiguration()
    try await NSWorkspace.shared.openApplication(at: url, configuration: config)
  }

  public func openDirectory(_ path: String, editor: EditorType?) async throws {
    if let editor {
      let editorPath = Self.applicationPath(for: editor)
      let editorURL = URL(fileURLWithPath: editorPath)
      let fm = FileManager.default

      guard fm.fileExists(atPath: editorPath) else {
        Self.logger.error("Editor not found: \(editorPath)")
        throw LaunchError.editorNotFound(editor)
      }

      // .code-workspace ファイルがあればそちらを開く（Zed は非対応のためディレクトリを直接開く）
      let targetURL: URL
      if editor.supportsCodeWorkspace, let workspacePath = findWorkspaceFile(in: path) {
        targetURL = URL(fileURLWithPath: workspacePath)
      } else {
        targetURL = URL(fileURLWithPath: path)
      }

      let config = NSWorkspace.OpenConfiguration()
      try await NSWorkspace.shared.open(
        [targetURL],
        withApplicationAt: editorURL,
        configuration: config
      )
    } else {
      let url = URL(fileURLWithPath: path)
      NSWorkspace.shared.open(url)
    }
  }

  public func openInTerminal(_ path: String, terminal: TerminalType) async throws {
    let terminalPath = Self.applicationPath(for: terminal)

    guard FileManager.default.fileExists(atPath: terminalPath) else {
      throw LaunchError.terminalNotFound(terminal)
    }

    switch terminal {
    case .cmux:
      // cmux を起動（未起動時）→ --cwd でワークスペース作成 → 選択 → 最前面化
      try await Self.ensureCmuxRunning()
      try Self.createCmuxWorkspaceWithCwd(path: path)
    default:
      let terminalURL = URL(fileURLWithPath: terminalPath)
      let dirURL = URL(fileURLWithPath: path)
      let config = NSWorkspace.OpenConfiguration()
      try await NSWorkspace.shared.open(
        [dirURL],
        withApplicationAt: terminalURL,
        configuration: config
      )
    }
  }

  public func executeCommand(
    _ command: String,
    workingDirectory: String?,
    terminal: TerminalType
  ) async throws {
    switch terminal {
    case .terminal, .iterm2, .ghostty, .cmux:
      let script = Self.appleScript(
        for: terminal,
        command: command,
        workingDirectory: workingDirectory
      )
      do {
        try Self.executeAppleScript(script, terminal: terminal)
      } catch {
        // Ghostty / cmux は設定やバージョン差分で AppleScript が無効な場合があるため従来方式にフォールバックする。
        if terminal == .ghostty {
          Self.logger.debug(
            "Ghostty AppleScript failed. Falling back to command script: \(error.localizedDescription, privacy: .public)"
          )
          try await Self.executeCommandViaCommandScript(
            command,
            workingDirectory: workingDirectory,
            terminal: terminal
          )
        } else if terminal == .cmux {
          Self.logger.debug(
            "cmux AppleScript failed. Falling back to CLI: \(error.localizedDescription, privacy: .public)"
          )
          try await Self.executeCommandViaCmuxCLI(
            command,
            workingDirectory: workingDirectory
          )
        } else {
          throw error
        }
      }

    case .warp:
      try await Self.executeCommandViaCommandScript(
        command,
        workingDirectory: workingDirectory,
        terminal: terminal
      )
    }
  }

  private static func executeAppleScript(_ script: String, terminal: TerminalType) throws {
    let process = Process()
    let stderrPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script]
    process.standardError = stderrPipe
    try process.run()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      let stderrText = String(data: stderrData, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let message =
        if let stderrText, !stderrText.isEmpty {
          stderrText
        } else {
          "osascript exited with status \(process.terminationStatus)"
        }
      Self.logger.error(
        "AppleScript execution failed (\(terminal.rawValue), status: \(process.terminationStatus)): \(message, privacy: .public)"
      )
      throw LaunchError.scriptExecutionFailed(message)
    }
  }

  private static func executeCommandViaCommandScript(
    _ command: String,
    workingDirectory: String?,
    terminal: TerminalType
  ) async throws {
    _ = Self.cleanupStaleCommandScripts()
    let scriptContent = Self.commandScript(
      command: command,
      workingDirectory: workingDirectory
    )
    let tempDir = FileManager.default.temporaryDirectory
    let scriptPath = tempDir.appendingPathComponent(
      "\(Self.commandScriptPrefix)\(UUID().uuidString).\(Self.commandScriptExtension)"
    )
    try scriptContent.write(to: scriptPath, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: scriptPath.path
    )

    let terminalPath = Self.applicationPath(for: terminal)
    guard FileManager.default.fileExists(atPath: terminalPath) else {
      throw LaunchError.terminalNotFound(terminal)
    }
    let terminalURL = URL(fileURLWithPath: terminalPath)
    let config = NSWorkspace.OpenConfiguration()
    try await NSWorkspace.shared.open(
      [scriptPath],
      withApplicationAt: terminalURL,
      configuration: config
    )
  }

  private static func executeCommandViaCmuxCLI(
    _ command: String,
    workingDirectory: String?
  ) async throws {
    try await Self.ensureCmuxRunning()
    let fullCommand: String
    if let wd = workingDirectory {
      fullCommand = "cd \(Self.shellEscaped(wd)) && \(command)"
    } else {
      fullCommand = command
    }
    try Self.createAndFocusCmuxWorkspace(command: fullCommand)
  }

  private static let cmuxBundleID = "com.cmuxterm.app"
  private static let cmuxSocketTimeout: TimeInterval = 10
  private static let cmuxSocketPollInterval: useconds_t = 200_000  // 200ミリ秒

  /// cmux が起動していなければ起動し、CLI の ping で疎通確認する。
  /// ソケットパスは cmux CLI が自動検出するため、パスのハードコードは不要。
  private static func ensureCmuxRunning() async throws {
    let isRunning = !NSRunningApplication.runningApplications(
      withBundleIdentifier: cmuxBundleID
    ).isEmpty

    if !isRunning {
      let appPath = applicationPath(for: .cmux)
      guard FileManager.default.fileExists(atPath: appPath) else {
        throw LaunchError.terminalNotFound(.cmux)
      }
      let config = NSWorkspace.OpenConfiguration()
      config.activates = false
      try await NSWorkspace.shared.openApplication(
        at: URL(fileURLWithPath: appPath), configuration: config
      )
    }

    // cmux CLI の ping で疎通確認（CLI がソケットパスを自動検出する）
    let deadline = Date().addingTimeInterval(cmuxSocketTimeout)
    while Date() < deadline {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: cmuxCLIPath)
      process.arguments = ["ping"]
      process.standardOutput = FileHandle.nullDevice
      process.standardError = FileHandle.nullDevice
      try? process.run()
      process.waitUntilExit()
      if process.terminationStatus == 0 {
        return
      }
      usleep(cmuxSocketPollInterval)
    }
    throw LaunchError.scriptExecutionFailed(
      "cmux socket did not become available within \(Int(cmuxSocketTimeout))s"
    )
  }

  /// cmux CLI コマンドを実行し、stdout を返す。事前に ensureCmuxRunning() を呼ぶこと。
  @discardableResult
  private static func executeCmuxCLI(_ arguments: [String]) throws -> String {
    let cliPath = cmuxCLIPath
    guard FileManager.default.fileExists(atPath: cliPath) else {
      throw LaunchError.terminalNotFound(.cmux)
    }
    let process = Process()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: cliPath)
    process.arguments = arguments
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    try process.run()
    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      let stderrText = String(data: stderrData, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let message =
        if let stderrText, !stderrText.isEmpty {
          stderrText
        } else {
          "cmux CLI exited with status \(process.terminationStatus)"
        }
      logger.error("cmux CLI failed: \(message, privacy: .public)")
      throw LaunchError.scriptExecutionFailed(message)
    }
    return String(data: stdoutData, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }

  /// new-workspace の出力（例: "OK <UUID>"）からワークスペース ID を抽出する。
  private static func parseWorkspaceID(from output: String) -> String? {
    // "OK <UUID>" 形式
    let parts = output.split(separator: " ", maxSplits: 1)
    guard parts.count == 2, parts[0] == "OK" else { return nil }
    return String(parts[1])
  }

  /// cmux で指定ディレクトリをカレントディレクトリとしてワークスペースを作成し、最前面にする。
  private static func createCmuxWorkspaceWithCwd(path: String) throws {
    let output = try executeCmuxCLI(["new-workspace", "--cwd", path])
    // 作成したワークスペースを選択
    if let wsID = parseWorkspaceID(from: output) {
      _ = try? executeCmuxCLI(["select-workspace", "--workspace", wsID])
    }
    // AppleScript でアプリを最前面化（最小化解除含む）
    let activateProcess = Process()
    activateProcess.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    activateProcess.arguments = ["-e", "tell application \"cmux\" to activate"]
    activateProcess.standardOutput = FileHandle.nullDevice
    activateProcess.standardError = FileHandle.nullDevice
    try? activateProcess.run()
    activateProcess.waitUntilExit()
  }

  /// cmux でワークスペースを作成し、選択して最前面にする。
  private static func createAndFocusCmuxWorkspace(command: String) throws {
    let output = try executeCmuxCLI(["new-workspace", "--command", command])
    // 作成したワークスペースを選択
    if let wsID = parseWorkspaceID(from: output) {
      _ = try? executeCmuxCLI(["select-workspace", "--workspace", wsID])
    }
    // AppleScript でアプリを最前面化（最小化解除含む）
    let activateProcess = Process()
    activateProcess.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    activateProcess.arguments = ["-e", "tell application \"cmux\" to activate"]
    activateProcess.standardOutput = FileHandle.nullDevice
    activateProcess.standardError = FileHandle.nullDevice
    try? activateProcess.run()
    activateProcess.waitUntilExit()
  }

  public func availableEditors() -> [EditorInfo] {
    let fm = FileManager.default
    return EditorType.allCases.map { editor in
      let appPath = Self.applicationPath(for: editor)
      let installed = fm.fileExists(atPath: appPath)
      let iconPath = installed ? Self.resolveIconPath(for: appPath) : nil
      return EditorInfo(
        id: editor,
        name: Self.displayName(for: editor),
        appName: Self.appName(for: editor),
        installed: installed,
        iconPath: iconPath
      )
    }
  }

  public func availableTerminals() -> [TerminalInfo] {
    let fm = FileManager.default
    return TerminalType.allCases.map { terminal in
      let appPath = Self.applicationPath(for: terminal)
      let installed = fm.fileExists(atPath: appPath)
      let iconPath = installed ? Self.resolveIconPath(for: appPath) : nil
      return TerminalInfo(
        id: terminal,
        name: Self.displayName(for: terminal),
        appName: Self.appName(for: terminal),
        installed: installed,
        iconPath: iconPath
      )
    }
  }

  /// アプリの Info.plist から CFBundleIconFile を読み取り、正しいアイコンパスを返す。
  private static func resolveIconPath(for appPath: String) -> String? {
    let plistPath = "\(appPath)/Contents/Info.plist"
    guard let plist = NSDictionary(contentsOfFile: plistPath),
      let iconFile = plist["CFBundleIconFile"] as? String
    else {
      // フォールバック: AppIcon.icns を試す
      let fallback = "\(appPath)/Contents/Resources/AppIcon.icns"
      return FileManager.default.fileExists(atPath: fallback) ? fallback : nil
    }
    let iconName = iconFile.hasSuffix(".icns") ? iconFile : "\(iconFile).icns"
    let fullPath = "\(appPath)/Contents/Resources/\(iconName)"
    return FileManager.default.fileExists(atPath: fullPath) ? fullPath : nil
  }
}

// MARK: - LaunchError 定義

public enum LaunchError: Error, Sendable {
  case editorNotFound(EditorType)
  case terminalNotFound(TerminalType)
  case scriptExecutionFailed(String)
}
