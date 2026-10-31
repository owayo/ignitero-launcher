import AppKit
import Foundation
import Testing

@testable import IgniteroCore

@Suite("OCR geometry")
struct OCRGeometryTests {
  @Test func actualSnapshotScaleAndClipping() {
    let size = CGSize(width: 1000, height: 800)
    #expect(
      OCRSelectionGeometry.pixelRect(
        selection: CGRect(x: 10.25, y: 20.25, width: 100.5, height: 50.5),
        screenSize: size, imageSize: CGSize(width: 2000, height: 1600)
      ) == CGRect(x: 20, y: 40, width: 202, height: 102))
    #expect(
      OCRSelectionGeometry.pixelRect(
        selection: CGRect(x: -10, y: -10, width: 30, height: 30),
        screenSize: size, imageSize: size
      ) == CGRect(x: 0, y: 0, width: 20, height: 20))
    #expect(
      OCRSelectionGeometry.pixelRect(
        selection: CGRect(x: 4, y: 8, width: 8, height: 16),
        screenSize: size, imageSize: CGSize(width: 1500, height: 1200)
      ) == CGRect(x: 6, y: 12, width: 12, height: 24))
  }

  @Test func invalidOrTinySelectionsDoNotProduceImages() {
    for rect in [
      CGRect(x: 0, y: 0, width: 3, height: 20),
      CGRect(x: 200, y: 0, width: 20, height: 20),
      CGRect(x: CGFloat.nan, y: 0, width: 20, height: 20),
    ] {
      #expect(
        OCRSelectionGeometry.pixelRect(
          selection: rect, screenSize: CGSize(width: 100, height: 100),
          imageSize: CGSize(width: 200, height: 200)) == nil)
    }
  }

  @Test func resultRetainsUnicodeAndLineBreaks() throws {
    let json =
      #"{"pages":[{"lines":[{"text":"日本語","confidence":0.9},{"text":"Error: test","confidence":0.8}]}]}"#
    let result = try JSONDecoder().decode(OCRDocument.self, from: Data(json.utf8))
    #expect(result.text == "日本語\nError: test")
  }
}

@Suite("Native OCR integration", .serialized)
@MainActor
struct OCRNativeTests {
  @Test func launcherFindsOCRByEnglishAndJapaneseKeywords() {
    let viewModel = LauncherViewModel()
    for query in ["ocr", "ＯＣＲ", "文字認識"] {
      viewModel.searchQuery = query
      viewModel.updateSearch()
      #expect(viewModel.searchResults.first?.kind == .ocr)
      #expect(viewModel.searchResults.first?.path == "")
    }
  }
  @Test func missingModelReturnsAnErrorAcrossTheABI() async {
    let service = OCRService(modelDirectory: URL(fileURLWithPath: "/nonexistent-ocr-models"))
    let image = makeImage()
    await #expect(throws: (any Error).self) { try await service.recognize(image) }
  }

  @Test func cancellationBeforeRecognitionNeverLoadsModels() async {
    let service = OCRService(modelDirectory: URL(fileURLWithPath: "/nonexistent-ocr-models"))
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await service.recognize(makeImage())
    }
    await #expect(throws: CancellationError.self) { try await task.value }
  }

  @Test func hostingViewIsContainedAndWindowSizeStaysBounded() async throws {
    _ = NSApplication.shared
    let model = OCRResultModel()
    model.phase = .ready
    model.vision.phase = .ready
    model.vision.text = String(repeating: "Visionの認識結果\n", count: 200)
    model.ocrus.phase = .ready
    model.ocrus.text = String(repeating: "日本語の認識結果\n", count: 200)
    let panel = OCRResultPanel(model: model, onSelectAgain: {})
    let originalFrame = panel.frame
    defer { panel.close() }
    #expect(panel.contentView?.subviews.count == 1)
    #expect(type(of: panel.contentView!) == NSView.self)
    #expect(
      String(describing: type(of: panel.contentView!.subviews[0])).hasPrefix("SafeHostingView"))
    panel.orderFront(nil)
    for index in 0..<4 {
      model.ocrus.text += String(repeating: "line \(index)\n", count: 40)
      try await Task.sleep(for: .milliseconds(30))
      #expect(panel.frame == originalFrame)
    }
    panel.contentView?.layoutSubtreeIfNeeded()
    #expect(panel.frame == originalFrame)
    if let path = ProcessInfo.processInfo.environment["IGNITERO_OCR_PREVIEW"],
      let view = panel.contentView,
      let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
    {
      view.cacheDisplay(in: view.bounds, to: bitmap)
      try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["IGNITERO_OCR_INTEGRATION"] == "1"))
  func nativeModelRecognizesRenderedJapaneseAndCanBeReused() async throws {
    let image = makeImage(text: "日本語の文字をコピーします")
    let service = OCRService()
    let first = try await service.recognize(image)
    let second = try await service.recognize(image)
    #expect(first.text == "日本語の文字をコピーします")
    #expect(second.text == first.text)
  }

  @Test func macOSVisionRecognizesJapaneseAndEnglish() async throws {
    let image = NSImage(size: NSSize(width: 700, height: 150))
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 700, height: 150).fill()
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 32), .foregroundColor: NSColor.black,
    ]
    ("日本語の文字をコピーします" as NSString).draw(at: NSPoint(x: 16, y: 90), withAttributes: attributes)
    ("Error: connection refused" as NSString).draw(
      at: NSPoint(x: 16, y: 28), withAttributes: attributes)
    image.unlockFocus()
    let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    let result = try await VisionOCRService().recognize(cgImage)
    #expect(result.text.contains("日本語の文字をコピーします"))
    #expect(result.text.contains("Error: connection refused"))
  }

  private func makeImage(text: String? = nil) -> CGImage {
    let image = NSImage(size: NSSize(width: 640, height: 80))
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 640, height: 80).fill()
    if let text {
      (text as NSString).draw(
        at: NSPoint(x: 16, y: 22),
        withAttributes: [
          .font: NSFont.systemFont(ofSize: 32), .foregroundColor: NSColor.black,
        ])
    }
    image.unlockFocus()
    return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
  }
}
