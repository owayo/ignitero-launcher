import AppKit
import QuartzCore
import Testing

@testable import IgniteroCore

@Suite("Compact AI usage layout", .serialized)
@MainActor
struct EmbeddedToolsLayoutTests {
  @Test(arguments: [680.0, 760.0])
  func fiveAccountsFitWithoutVerticalScrolling(width: Double) async throws {
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/EmbeddedTools.json")
    let root = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [String: Any])
    var data = try #require(root["data"] as? [String: Any])
    var report = try #require(data["report"] as? [String: Any])
    let accounts = try #require(report["accounts"] as? [[String: Any]])
    let normal = try #require(accounts.first)
    var rows = (0..<5).map { index in
      var row = normal
      row["label"] = "Home Account \(index + 1)"
      return row
    }
    rows[4]["ok"] = false
    rows[4]["error"] = String(repeating: "A detailed error message. ", count: 30)
    report["accounts"] = rows
    data["report"] = report
    let model = EmbeddedToolsModel()
    model.usage = try JSONDecoder().decode(
      AIUsageSnapshot.self, from: JSONSerialization.data(withJSONObject: data))
    let panel = EmbeddedToolsPanel(model: model)
    panel.setContentSize(NSSize(width: width, height: 440))
    panel.setFrameOrigin(NSPoint(x: -20000, y: -20000))
    panel.orderFrontRegardless()
    defer { panel.close() }
    for _ in 0..<5 {
      panel.layoutIfNeeded()
      CATransaction.flush()
      try await Task.sleep(for: .milliseconds(20))
    }
    let content = try #require(panel.contentView)
    let scrollViews = descendants(content).compactMap { $0 as? NSScrollView }
    #expect(!scrollViews.isEmpty)
    for scroll in scrollViews {
      let document = try #require(scroll.documentView)
      #expect(document.frame.height <= scroll.contentView.bounds.height + 1)
    }
    #expect(content.bounds.height == 440)
  }

  private func descendants(_ view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + descendants($0) }
  }
}
