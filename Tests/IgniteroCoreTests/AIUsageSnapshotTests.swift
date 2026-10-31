import AppKit
import QuartzCore
import Testing

@testable import IgniteroCore

/// AI利用枠の画面を PNG に書き出す任意の確認用テスト。通常のテストでは実行しない。
///
/// `IGNITERO_AI_USAGE_SNAPSHOT_DIR=<出力先> swift test --filter AIUsageSnapshotTests` で、
/// ライト・ダーク・コントラストを上げた外観の画像を書き出す。ブランドアイコンを描くには
/// `IGNITERO_PROVIDER_LOGO_DIR` に正規化済みの SVG の置き場所 (`make bundle` 後の
/// `.build/IgniteroLauncher.app/Contents/Resources/ProviderLogos` など) を渡す。
/// 画像は目視の確認用で、合否は判定しない。
@Suite(
  "AI usage snapshots", .serialized,
  .enabled(if: ProcessInfo.processInfo.environment["IGNITERO_AI_USAGE_SNAPSHOT_DIR"] != nil))
@MainActor
struct AIUsageSnapshotTests {
  /// コントラストを上げる設定 (`colorSchemeContrast`) は外観では切り替わらないため、
  /// その色は AIUsageStyleTests のコントラスト比の検査で確かめる。
  @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
  func writeSnapshot(appearance: NSAppearance.Name) async throws {
    let environment = ProcessInfo.processInfo.environment
    let output = URL(
      fileURLWithPath: try #require(environment["IGNITERO_AI_USAGE_SNAPSHOT_DIR"]),
      isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let model = EmbeddedToolsModel()
    model.usage = try JSONDecoder().decode(AIUsageSnapshot.self, from: Self.fixture(now: Date()))
    let store = ProviderLogoStore(
      directory: environment["IGNITERO_PROVIDER_LOGO_DIR"].map {
        URL(fileURLWithPath: $0, isDirectory: true)
      })
    let panel = EmbeddedToolsPanel(model: model, logoStore: store)
    panel.appearance = NSAppearance(named: appearance)
    panel.setContentSize(NSSize(width: 760, height: 560))
    panel.setFrameOrigin(NSPoint(x: -20000, y: -20000))
    panel.orderFrontRegardless()
    defer { panel.close() }
    for _ in 0..<5 {
      panel.layoutIfNeeded()
      CATransaction.flush()
      try await Task.sleep(for: .milliseconds(50))
    }
    let view = try #require(panel.contentView)
    let content = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: content)
    // cacheDisplay はウィンドウの背景を含まないため、外観の背景色の上に重ねる。
    // NSImageRep.draw(in:) は copy で合成して背景を透明に戻すため、sourceOver を明示する。
    var background = NSColor.white
    panel.effectiveAppearance.performAsCurrentDrawingAppearance {
      background = NSColor.windowBackgroundColor.usingColorSpace(.sRGB) ?? .white
    }
    let bounds = NSRect(origin: .zero, size: view.bounds.size)
    let image = NSImage(size: bounds.size)
    image.lockFocus()
    background.setFill()
    bounds.fill()
    content.draw(
      in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
      hints: nil)
    image.unlockFocus()
    let tiff = try #require(image.tiffRepresentation)
    let png = try #require(
      NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    let name = appearance.rawValue.replacingOccurrences(of: "NSAppearanceName", with: "")
    try png.write(to: output.appendingPathComponent("ai-usage-\(name).png"))
  }

  /// 全プロバイダと、色の段階・不明・失敗・手動リセットの期限を 1 画面に並べる。
  private static func fixture(now: Date) throws -> Data {
    func at(_ seconds: TimeInterval) -> String {
      now.addingTimeInterval(seconds).formatted(.iso8601)
    }
    let hour: TimeInterval = 3_600
    let day: TimeInterval = 86_400
    let accounts: [[String: Any]] = [
      [
        "profile": "Home", "provider": "claude", "ok": true, "label": "Home",
        "five_hour": ["kind": "five_hour", "used_percent": 45, "resets_at": at(2.5 * hour)],
        "weekly": ["kind": "weekly", "used_percent": 82, "resets_at": at(4 * day - 60)],
        "manual_resets": [
          ["kind": "full", "remaining": 2, "expires_at": at(5 * day), "paused": false],
          ["kind": "five_hour", "remaining": 0, "expires_at": NSNull(), "paused": false],
        ],
      ],
      [
        "profile": "Work", "provider": "codex", "ok": true, "email": "you@example.com",
        "five_hour": ["kind": "five_hour", "used_percent": 15, "resets_at": at(4 * hour)],
        "weekly": ["kind": "weekly", "used_percent": 61, "resets_at": at(20 * hour)],
        "manual_resets": [
          ["kind": "full", "remaining": 1, "expires_at": at(20 * day), "paused": false]
        ],
      ],
      [
        "profile": "Home", "provider": "antigravity", "ok": true, "group_label": "Gemini",
        "weekly": ["kind": "weekly", "used_percent": 95, "resets_at": at(2 * day + 5 * hour)],
      ],
      [
        "profile": "Home", "provider": "pixellab", "ok": true,
        "weekly": ["kind": "monthly", "used_percent": 30, "resets_at": at(10 * day)],
      ],
      [
        "profile": "Home", "provider": "grok", "ok": true,
        "weekly": ["kind": "weekly", "used_percent": NSNull(), "resets_at": at(-30)],
      ],
      [
        "profile": "Old", "provider": "claude", "ok": false, "error": "Session expired",
      ],
    ]
    let snapshot: [String: Any] = [
      "report": ["generated_at": now.formatted(.iso8601), "accounts": accounts],
      "warnings": [],
    ]
    return try JSONSerialization.data(withJSONObject: snapshot)
  }
}
