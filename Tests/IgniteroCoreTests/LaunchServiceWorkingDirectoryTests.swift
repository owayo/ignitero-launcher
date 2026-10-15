import Foundation
import Testing

@testable import IgniteroCore

@Suite("作業ディレクトリと複合コマンドの実行")
struct LaunchServiceWorkingDirectoryTests {
  private func run(_ command: String, shell: String, directory: URL) throws -> (
    status: Int32, output: String
  ) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: shell)
    process.arguments = ["-c", command]
    process.currentDirectoryURL = directory
    let stdout = Pipe()
    let stderr = try FileHandle(forWritingTo: URL(fileURLWithPath: "/dev/null"))
    defer { try? stderr.close() }
    process.standardOutput = stdout
    process.standardError = stderr
    let reader = stdout.fileHandleForReading
    defer { try? reader.close() }
    try process.run()
    let data = reader.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
  }

  @Test(
    "cd の失敗時は複合コマンドのどの部分も実行しない",
    arguments: ["/bin/bash", "/bin/zsh"],
    [
      "printf first; printf second", "false || printf fallback", "printf first\nprintf second",
      "printf background & wait",
    ]
  )
  func missingDirectorySkipsEntireCommand(shell: String, command: String) throws {
    let directory = FileManager.default.temporaryDirectory
    let missing = directory.appendingPathComponent("ignitero-missing-\(UUID().uuidString)")
    let input = LaunchService.shellCommand(command, workingDirectory: missing.path)
    let result = try run(input, shell: shell, directory: directory)
    #expect(result.status != 0)
    #expect(result.output.isEmpty)
  }

  @Test(
    "引用符・空白・日本語を含む作業ディレクトリでコマンド全体を実行する",
    arguments: ["/bin/bash", "/bin/zsh"])
  func validDirectoryPreservesCommandAndShellState(shell: String) throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ignitero-\(UUID().uuidString)-日本語 O'Neil $work")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let command = "export IGNITERO_TEST_VALUE='a; b $HOME'; printf '%s\\n' \"$IGNITERO_TEST_VALUE\""
    let input = LaunchService.shellCommand(command, workingDirectory: directory.path)
    // サブシェルへ閉じ込めず、コマンド内の環境変数と cd が元のシェルにも残ることを確かめる。
    let result = try run(
      input + "\nprintf '%s\\n' \"$IGNITERO_TEST_VALUE\" \"$PWD\"",
      shell: shell, directory: FileManager.default.temporaryDirectory)
    #expect(result.status == 0)
    #expect(
      result.output == "a; b $HOME\na; b $HOME\n\(directory.path)\n")
  }

  @Test("作業ディレクトリを指定しない入力はそのまま実行する")
  func noDirectoryPreservesInput() {
    let command = "printf 'first'; false || printf 'second'\n# 末尾コメント"
    #expect(LaunchService.shellCommand(command, workingDirectory: nil) == command)
  }

  @Test(
    "入力例のチルダは両実行方式でホームディレクトリへ展開する",
    arguments: ["/bin/bash", "/bin/zsh"])
  func tildeDirectoryWorksForBothExecutionMethods(shell: String) throws {
    let command = "printf '%s\\n' \"$PWD\""
    let inputs = [
      LaunchService.shellCommand(command, workingDirectory: "~"),
      LaunchService.commandScript(command: command, workingDirectory: "~"),
    ]
    for input in inputs {
      let result = try run(input, shell: shell, directory: URL(fileURLWithPath: "/"))
      #expect(result.status == 0)
      #expect(result.output == FileManager.default.homeDirectoryForCurrentUser.path + "\n")
    }
  }

  @Test(
    "空コマンドでも有効なディレクトリへの移動を保持する",
    arguments: ["/bin/bash", "/bin/zsh"])
  func emptyCommandChangesDirectory(shell: String) throws {
    let directory = FileManager.default.temporaryDirectory
    let input = LaunchService.shellCommand("", workingDirectory: directory.path)
    let result = try run(
      input + "\nprintf '%s\\n' \"$PWD\"", shell: shell, directory: URL(fileURLWithPath: "/"))
    #expect(result.status == 0)
    #expect(result.output == directory.path + "\n")
  }
}
