import Foundation
import Testing

@testable import IgniteroCore

// MARK: - EditorType Tests

@Suite("EditorType")
struct EditorTypeTests {

  @Test func allCasesCount() {
    #expect(EditorType.allCases.count == 5)
  }

  @Test func allCasesContainsExpected() {
    let cases = EditorType.allCases
    #expect(cases.contains(.windsurf))
    #expect(cases.contains(.cursor))
    #expect(cases.contains(.vscode))
    #expect(cases.contains(.antigravity))
    #expect(cases.contains(.zed))
  }

  @Test func rawValues() {
    #expect(EditorType.windsurf.rawValue == "windsurf")
    #expect(EditorType.cursor.rawValue == "cursor")
    #expect(EditorType.vscode.rawValue == "vscode")
    #expect(EditorType.antigravity.rawValue == "antigravity")
    #expect(EditorType.zed.rawValue == "zed")
  }

  @Test func codable() throws {
    for editor in EditorType.allCases {
      let data = try JSONEncoder().encode(editor)
      let decoded = try JSONDecoder().decode(EditorType.self, from: data)
      #expect(decoded == editor)
    }
  }
}

// MARK: - TerminalType Tests

@Suite("TerminalType")
struct TerminalTypeAllCasesTests {

  @Test func allCasesCount() {
    #expect(TerminalType.allCases.count == 5)
  }

  @Test func allCasesContainsExpected() {
    let cases = TerminalType.allCases
    #expect(cases.contains(.terminal))
    #expect(cases.contains(.iterm2))
    #expect(cases.contains(.ghostty))
    #expect(cases.contains(.warp))
    #expect(cases.contains(.cmux))
  }
}

// MARK: - EditorInfo Tests

@Suite("EditorInfo")
struct EditorInfoTests {

  @Test func creation() {
    let info = EditorInfo(
      id: .windsurf,
      name: "Windsurf",
      appName: "Windsurf.app",
      installed: true,
      iconPath: "/path/to/icon.png"
    )
    #expect(info.id == .windsurf)
    #expect(info.name == "Windsurf")
    #expect(info.appName == "Windsurf.app")
    #expect(info.installed == true)
    #expect(info.iconPath == "/path/to/icon.png")
  }

  @Test func defaultIconPath() {
    let info = EditorInfo(
      id: .cursor,
      name: "Cursor",
      appName: "Cursor.app",
      installed: false
    )
    #expect(info.iconPath == nil)
  }
}

// MARK: - TerminalInfo Tests

@Suite("TerminalInfo")
struct TerminalInfoTests {

  @Test func creation() {
    let info = TerminalInfo(
      id: .iterm2,
      name: "iTerm2",
      appName: "iTerm.app",
      installed: true,
      iconPath: "/path/to/icon.png"
    )
    #expect(info.id == .iterm2)
    #expect(info.name == "iTerm2")
    #expect(info.appName == "iTerm.app")
    #expect(info.installed == true)
    #expect(info.iconPath == "/path/to/icon.png")
  }

  @Test func defaultIconPath() {
    let info = TerminalInfo(
      id: .terminal,
      name: "Terminal",
      appName: "Terminal.app",
      installed: true
    )
    #expect(info.iconPath == nil)
  }
}

// MARK: - LaunchService App Name Mapping Tests

@Suite("LaunchService App Name Mapping")
struct LaunchServiceAppNameTests {

  @Test func editorAppNames() {
    #expect(LaunchService.appName(for: .windsurf) == "Windsurf.app")
    #expect(LaunchService.appName(for: .cursor) == "Cursor.app")
    #expect(LaunchService.appName(for: .vscode) == "Visual Studio Code.app")
    #expect(LaunchService.appName(for: .antigravity) == "Antigravity.app")
    #expect(LaunchService.appName(for: .zed) == "Zed.app")
  }

  @Test func editorDisplayNames() {
    #expect(LaunchService.displayName(for: .windsurf) == "Windsurf")
    #expect(LaunchService.displayName(for: .cursor) == "Cursor")
    #expect(LaunchService.displayName(for: .vscode) == "Visual Studio Code")
    #expect(LaunchService.displayName(for: .antigravity) == "Antigravity")
    #expect(LaunchService.displayName(for: .zed) == "Zed")
  }

  @Test func terminalAppNames() {
    #expect(LaunchService.appName(for: .terminal) == "Terminal.app")
    #expect(LaunchService.appName(for: .iterm2) == "iTerm.app")
    #expect(LaunchService.appName(for: .ghostty) == "Ghostty.app")
    #expect(LaunchService.appName(for: .warp) == "Warp.app")
    #expect(LaunchService.appName(for: .cmux) == "cmux.app")
  }

  @Test func terminalDisplayNames() {
    #expect(LaunchService.displayName(for: .terminal) == "Terminal")
    #expect(LaunchService.displayName(for: .iterm2) == "iTerm2")
    #expect(LaunchService.displayName(for: .ghostty) == "Ghostty")
    #expect(LaunchService.displayName(for: .warp) == "Warp")
    #expect(LaunchService.displayName(for: .cmux) == "cmux")
  }
}

// MARK: - Workspace Detection Tests

@Suite("LaunchService Workspace Detection")
struct LaunchServiceWorkspaceTests {

  @Test func workspaceGlobPattern() {
    let pattern = LaunchService.workspaceGlobPattern(for: "/Users/test/project")
    #expect(pattern == "/Users/test/project/*.code-workspace")
  }

  @Test func workspaceGlobPatternTrailingSlash() {
    let pattern = LaunchService.workspaceGlobPattern(for: "/Users/test/project/")
    #expect(pattern == "/Users/test/project/*.code-workspace")
  }
}

// MARK: - AppleScript Command Generation Tests

@Suite("LaunchService AppleScript Generation")
struct LaunchServiceAppleScriptTests {

  @Test func terminalAppleScript() {
    let script = LaunchService.appleScript(
      for: .terminal,
      command: "cd /Users/test/project",
      workingDirectory: nil
    )
    #expect(script.contains("tell application \"Terminal\""))
    #expect(script.contains("do script \"cd /Users/test/project\""))
    #expect(script.contains("activate"))
  }

  @Test func iterm2AppleScript() {
    let script = LaunchService.appleScript(
      for: .iterm2,
      command: "cd /Users/test/project",
      workingDirectory: nil
    )
    #expect(script.contains("tell application \"iTerm\""))
    #expect(script.contains("write text \"cd /Users/test/project\""))
    #expect(script.contains("activate"))
  }

  @Test func terminalAppleScriptWithWorkingDirectory() {
    let script = LaunchService.appleScript(
      for: .terminal,
      command: "npm run dev",
      workingDirectory: "/Users/test/app"
    )
    #expect(script.contains("cd '/Users/test/app' && npm run dev"))
  }

  @Test func iterm2AppleScriptWithWorkingDirectory() {
    let script = LaunchService.appleScript(
      for: .iterm2,
      command: "make build",
      workingDirectory: "/Users/test/project"
    )
    #expect(script.contains("cd '/Users/test/project' && make build"))
  }

  @Test func appleScriptEscapesDoubleQuotesInCommand() {
    let script = LaunchService.appleScript(
      for: .terminal,
      command: "echo \"hello\"",
      workingDirectory: nil
    )
    #expect(script.contains("do script \"echo \\\"hello\\\"\""))
  }

  @Test func appleScriptEscapesBackslashesInCommand() {
    let script = LaunchService.appleScript(
      for: .terminal,
      command: "echo C:\\temp\\file.txt",
      workingDirectory: nil
    )
    #expect(script.contains("do script \"echo C:\\\\temp\\\\file.txt\""))
  }

  @Test func appleScriptEscapesWorkingDirectoryWithSingleQuote() {
    let script = LaunchService.appleScript(
      for: .terminal,
      command: "pwd",
      workingDirectory: "/Users/test/O'Neil Project"
    )
    #expect(script.contains("cd '/Users/test/O'\\\"'\\\"'Neil Project' && pwd"))
  }
}

// MARK: - AppleScript Escaping Combined Patterns

@Suite("LaunchService AppleScript Escaping Edge Cases")
struct LaunchServiceAppleScriptEscapingEdgeCaseTests {

  @Test func appleScriptEscapesBackslashQuoteCombination() {
    // Input: echo \"hello\" — backslash + double-quote combination
    let script = LaunchService.appleScript(
      for: .terminal,
      command: "echo \\\"hello\\\"",
      workingDirectory: nil
    )
    // Backslash escaped first (\ → \\), then quotes escaped (" → \")
    #expect(script.contains("do script \"echo \\\\\\\"hello\\\\\\\"\""))
  }

  @Test func appleScriptEscapesNewlinesAndCarriageReturns() {
    let script = LaunchService.appleScript(
      for: .terminal,
      command: "echo line1\necho line2\recho line3",
      workingDirectory: nil
    )
    #expect(!script.contains("\r"))
    #expect(script.contains("\\n"))
  }

  @Test func appleScriptEscapesEmptyCommand() {
    let script = LaunchService.appleScript(
      for: .terminal,
      command: "",
      workingDirectory: nil
    )
    #expect(script.contains("do script \"\""))
  }

  @Test func shellEscapesConsecutiveSingleQuotes() {
    let script = LaunchService.commandScript(
      command: "echo test",
      workingDirectory: "/Users/test/O'Neil's"
    )
    #expect(script.contains("cd '/Users/test/O'\"'\"'Neil'\"'\"'s'"))
  }

  @Test func shellEscapesEmptyWorkingDirectory() {
    let script = LaunchService.commandScript(
      command: "echo test",
      workingDirectory: ""
    )
    #expect(script.contains("cd ''"))
  }

  @Test func appleScriptDefaultTerminalReturnsEmpty() {
    let script = LaunchService.appleScript(
      for: .ghostty,
      command: "echo test",
      workingDirectory: nil
    )
    #expect(script.isEmpty)
  }

  @Test func appleScriptWarpReturnsEmpty() {
    let script = LaunchService.appleScript(
      for: .warp,
      command: "echo test",
      workingDirectory: nil
    )
    #expect(script.isEmpty)
  }

  @Test func appleScriptCmuxReturnsEmpty() {
    let script = LaunchService.appleScript(
      for: .cmux,
      command: "echo test",
      workingDirectory: nil
    )
    #expect(script.isEmpty)
  }
}

// MARK: - .command Script Generation Tests

@Suite("LaunchService Command Script Generation")
struct LaunchServiceCommandScriptTests {

  @Test func ghosttyCommandScript() {
    let script = LaunchService.commandScript(
      command: "cd /Users/test/project",
      workingDirectory: nil
    )
    #expect(script.contains("#!/bin/bash"))
    #expect(script.contains("cd /Users/test/project"))
  }

  @Test func commandScriptWithWorkingDirectory() {
    let script = LaunchService.commandScript(
      command: "npm run dev",
      workingDirectory: "/Users/test/app"
    )
    #expect(script.contains("#!/bin/bash"))
    #expect(script.contains("cd '/Users/test/app'"))
    #expect(script.contains("npm run dev"))
  }

  @Test func commandScriptQuotesWorkingDirectoryWithSpaces() {
    let script = LaunchService.commandScript(
      command: "npm run dev",
      workingDirectory: "/Users/test/My Project"
    )
    #expect(script.contains("cd '/Users/test/My Project'"))
  }

  @Test func commandScriptEscapesSingleQuoteInWorkingDirectory() {
    let script = LaunchService.commandScript(
      command: "pwd",
      workingDirectory: "/Users/test/O'Neil/project"
    )
    #expect(script.contains("cd '/Users/test/O'\"'\"'Neil/project'"))
  }

  @Test func commandScriptEndsWithExit() {
    let script = LaunchService.commandScript(
      command: "echo hello",
      workingDirectory: nil
    )
    #expect(script.hasSuffix("exit\n"))
  }
}

// MARK: - Temporary Script Cleanup Tests

@Suite("LaunchService Temporary Script Cleanup")
struct LaunchServiceTempScriptCleanupTests {

  private func makeTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("ignitero-launch-service-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  @Test func removesOnlyStaleIgniteroCommandScripts() throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let staleScript = dir.appendingPathComponent("ignitero-stale.command")
    let freshScript = dir.appendingPathComponent("ignitero-fresh.command")
    let unrelatedFile = dir.appendingPathComponent("other.command")

    try "#!/bin/bash\necho stale\n".write(to: staleScript, atomically: true, encoding: .utf8)
    try "#!/bin/bash\necho fresh\n".write(to: freshScript, atomically: true, encoding: .utf8)
    try "noop".write(to: unrelatedFile, atomically: true, encoding: .utf8)

    try FileManager.default.setAttributes(
      [.modificationDate: now.addingTimeInterval(-600)],
      ofItemAtPath: staleScript.path
    )
    try FileManager.default.setAttributes(
      [.modificationDate: now.addingTimeInterval(-60)],
      ofItemAtPath: freshScript.path
    )

    let removed = LaunchService.cleanupStaleCommandScripts(
      in: dir,
      olderThan: 300,
      now: now
    )

    #expect(removed == 1)
    #expect(!FileManager.default.fileExists(atPath: staleScript.path))
    #expect(FileManager.default.fileExists(atPath: freshScript.path))
    #expect(FileManager.default.fileExists(atPath: unrelatedFile.path))
  }

  @Test func cleanupReturnsZeroWhenDirectoryDoesNotExist() {
    let missingDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("ignitero-missing-\(UUID().uuidString)")
    let removed = LaunchService.cleanupStaleCommandScripts(in: missingDir, now: Date())
    #expect(removed == 0)
  }
}

// MARK: - Editor Path Tests

@Suite("LaunchService Editor Path")
struct LaunchServiceEditorPathTests {

  @Test func editorApplicationPath() {
    for editor in EditorType.allCases {
      let path = LaunchService.applicationPath(for: editor)
      #expect(path == "/Applications/\(LaunchService.appName(for: editor))")
    }
  }
}

// MARK: - Terminal Path Tests

@Suite("LaunchService Terminal Path")
struct LaunchServiceTerminalPathTests {

  @Test func terminalApplicationPath() {
    let expectedTerminalPath =
      FileManager.default.fileExists(atPath: "/System/Applications/Utilities/Terminal.app")
      ? "/System/Applications/Utilities/Terminal.app"
      : "/Applications/Utilities/Terminal.app"

    #expect(
      LaunchService.applicationPath(for: .terminal) == expectedTerminalPath)
    #expect(LaunchService.applicationPath(for: .iterm2) == "/Applications/iTerm.app")
    #expect(LaunchService.applicationPath(for: .ghostty) == "/Applications/Ghostty.app")
    #expect(LaunchService.applicationPath(for: .warp) == "/Applications/Warp.app")
    #expect(LaunchService.applicationPath(for: .cmux) == "/Applications/cmux.app")
  }
}

// MARK: - Protocol Conformance Tests

@Suite("LaunchService Protocol")
struct LaunchServiceProtocolTests {

  @Test func conformsToLaunching() {
    let service: any Launching = LaunchService()
    #expect(type(of: service) == LaunchService.self)
  }
}
