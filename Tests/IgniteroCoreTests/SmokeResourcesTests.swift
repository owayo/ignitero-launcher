import Foundation
import Testing

@Suite("配布リソース検証スクリプト")
struct SmokeResourcesTests {
  private func verify(layout: String?, selfTestStatus: Int32) throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("ignitero smoke \(UUID().uuidString)")
    defer { try? fm.removeItem(at: root) }
    let app = root.appendingPathComponent(".build/Probe.app")
    let executable = app.appendingPathComponent("Contents/MacOS/Probe")
    let packagedBundle = app.appendingPathComponent("Contents/Resources/Example.bundle")
    try fm.createDirectory(
      at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fm.createDirectory(at: packagedBundle, withIntermediateDirectories: true)
    let buildBundle = layout.map { root.appendingPathComponent(".build/\($0)/Example.bundle") }
    if let buildBundle {
      try fm.createDirectory(at: buildBundle, withIntermediateDirectories: true)
    }
    let relativeBundle = ".build/\(layout ?? "missing")/Example.bundle"
    let probe = """
      #!/bin/bash
      touch probe-ran
      [ ! -d "\(relativeBundle)" ] || exit 91
      [ -d "\(relativeBundle).smoke-hidden" ] || exit 92
      [ -d .build/Probe.app/Contents/Resources/Example.bundle ] || exit 93
      exit \(selfTestStatus)
      """
    try probe.write(to: executable, atomically: true, encoding: .utf8)
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

    let script = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("scripts/smoke_resources.sh")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [script.path, ".build/Probe.app", "Probe"]
    process.currentDirectoryURL = root
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    let reader = output.fileHandleForReading
    defer { try? reader.close() }
    try process.run()
    let diagnostic = String(decoding: reader.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()

    #expect(fm.fileExists(atPath: packagedBundle.path))
    if let buildBundle {
      #expect(process.terminationStatus == selfTestStatus, "\(diagnostic)")
      #expect(fm.fileExists(atPath: root.appendingPathComponent("probe-ran").path))
      #expect(fm.fileExists(atPath: buildBundle.path))
      #expect(!fm.fileExists(atPath: buildBundle.path + ".smoke-hidden"))
    } else {
      #expect(process.terminationStatus != 0)
      #expect(!fm.fileExists(atPath: root.appendingPathComponent("probe-ran").path))
    }
  }

  @Test(
    "旧配置と新配置を退避し、自己診断の成否にかかわらず復元する",
    arguments: ["arm64-apple-macosx/release", "out/Products/Release"], [Int32(0), Int32(7)])
  func hidesAndRestoresBuildBundles(layout: String, status: Int32) throws {
    try verify(layout: layout, selfTestStatus: status)
  }

  @Test("退避対象がない場合は検証成功にせず自己診断も起動しない")
  func rejectsMissingBuildBundles() throws {
    try verify(layout: nil, selfTestStatus: 0)
  }
}
