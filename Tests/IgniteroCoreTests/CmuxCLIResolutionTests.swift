import Foundation
import Testing

@testable import IgniteroCore

@Suite("cmux CLI の探索")
struct CmuxCLIResolutionTests {
  private func makeCLI(at url: URL, executable: Bool) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "#!/bin/sh\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: url.path)
  }

  @Test("Applications 以外の配置と起動後の CLI 追加を認識する")
  func bundledCLIOutsideSystemApplicationsBecomesAvailable() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("ignitero-cmux-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let app = root.appendingPathComponent("Home/Applications/cmux.app")
    let cli = app.appendingPathComponent("Contents/Resources/bin/cmux")

    let missing = LaunchService.resolveCmuxCLIPath(applicationPath: app.path, preferredPaths: [])
    #expect(!LaunchService.runCmuxPing(cliPath: missing))
    try makeCLI(at: cli, executable: true)
    let installed = LaunchService.resolveCmuxCLIPath(applicationPath: app.path, preferredPaths: [])
    #expect(LaunchService.runCmuxPing(cliPath: installed))
  }

  @Test("実行不能な優先 CLI を飛ばして同梱 CLI を使用する")
  func skipsNonExecutablePreferredCLI() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("ignitero-cmux-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let app = root.appendingPathComponent("cmux.app")
    let cli = app.appendingPathComponent("Contents/Resources/bin/cmux")
    let preferred = root.appendingPathComponent("bin/cmux")
    try makeCLI(at: cli, executable: true)
    try makeCLI(at: preferred, executable: false)

    let selected = LaunchService.resolveCmuxCLIPath(
      applicationPath: app.path, preferredPaths: [preferred.path])
    #expect(selected == cli.path)
    #expect(LaunchService.runCmuxPing(cliPath: selected))
  }

  @Test("実行可能な Homebrew 候補の優先順位を維持する")
  func preservesPreferredCLIOrder() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("ignitero-cmux-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let first = root.appendingPathComponent("first/cmux")
    let second = root.appendingPathComponent("second/cmux")
    try makeCLI(at: first, executable: true)
    try makeCLI(at: second, executable: true)
    let selected = LaunchService.resolveCmuxCLIPath(
      applicationPath: root.appendingPathComponent("cmux.app").path,
      preferredPaths: [first.path, second.path])
    #expect(selected == first.path)
  }
}
