import AppKit
import Testing

@testable import IgniteroCore

@Suite(
  "OCR range selection", .serialized,
  .enabled(if: ProcessInfo.processInfo.environment["IGNITERO_OCR_UI"] == "1"))
@MainActor
struct OCRSelectionUITests {
  @Test func draggingTheOverlayReturnsOnlyTheSelectedImage() async throws {
    _ = NSApplication.shared
    let screen = try #require(NSScreen.screens.first)
    let context = try #require(
      CGContext(
        data: nil, width: 1000, height: 600, bitsPerComponent: 8, bytesPerRow: 4000,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 500, height: 600))
    context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
    context.fill(CGRect(x: 500, y: 0, width: 500, height: 600))
    let image = try #require(context.makeImage())
    let selector = OCRRegionSelector()
    defer { selector.cancel() }
    let task = Task {
      try await selector.select(from: [
        OCRCapturedScreen(displayID: 1, frame: screen.frame, image: image)
      ])
    }
    let deadline = ContinuousClock.now + .seconds(5)
    var target: NSWindow?
    while target == nil, ContinuousClock.now < deadline {
      target = NSApp.windows.first { $0.isVisible && $0.level == .screenSaver }
      if target == nil { try await Task.sleep(for: .milliseconds(10)) }
    }
    let panel = try #require(target)
    let view = try #require(panel.contentView)
    let start = CGPoint(x: view.bounds.width * 0.6, y: view.bounds.height * 0.2)
    let end = CGPoint(x: view.bounds.width * 0.9, y: view.bounds.height * 0.6)
    for (type, point) in [
      (NSEvent.EventType.leftMouseDown, start), (.leftMouseDragged, end), (.leftMouseUp, end),
    ] {
      let event = try #require(
        NSEvent.mouseEvent(
          with: type, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0,
          windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
      switch type {
      case .leftMouseDown: view.mouseDown(with: event)
      case .leftMouseDragged: view.mouseDragged(with: event)
      default: view.mouseUp(with: event)
      }
    }
    let cropped = try #require(try await task.value)
    #expect(cropped.width >= 299 && cropped.width <= 301)
    #expect(cropped.height >= 239 && cropped.height <= 241)
    let color = try #require(
      NSBitmapImageRep(cgImage: cropped).colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
    #expect(color.blueComponent > 0.95)
    #expect(color.redComponent < 0.05)
    #expect(!panel.isVisible)
  }
}
