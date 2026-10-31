import AppKit
import Testing

@testable import IgniteroCore

@MainActor
private final class FixedScreenCapture: OCRScreenCapturing {
  let image: CGImage
  var failure: OCRCaptureError?
  init(image: CGImage) { self.image = image }
  func captureScreens() async throws -> [OCRCapturedScreen] {
    if let failure { throw failure }
    return [
      OCRCapturedScreen(
        displayID: 1, frame: CGRect(x: -800, y: 200, width: 100, height: 100), image: image)
    ]
  }
}

@MainActor
private final class FixedRegionSelector: OCRRegionSelecting {
  let image: CGImage
  init(image: CGImage) { self.image = image }
  func select(from screens: [OCRCapturedScreen]) async -> CGImage? { image }
  func cancel() {}
}

private actor ControlledOCR: OCRRecognizing {
  var pending: [CheckedContinuation<OCRDocument, any Error>?] = []
  var count: Int { pending.count }
  func recognize(_ image: CGImage) async throws -> OCRDocument {
    try await withCheckedThrowingContinuation { pending.append($0) }
  }
  func finish(_ index: Int, text: String) {
    pending[index]?.resume(
      returning: OCRDocument(pages: [.init(lines: [.init(text: text, confidence: 1)])]))
    pending[index] = nil
  }
  func fail(_ index: Int) {
    pending[index]?.resume(throwing: OCRError.engine("fixture error"))
    pending[index] = nil
  }
}

private struct ImmediateOCR: OCRRecognizing {
  func recognize(_ image: CGImage) async throws -> OCRDocument {
    OCRDocument(pages: [.init(lines: [.init(text: "Vision", confidence: 1)])])
  }
}

@Suite("OCR request lifecycle", .serialized)
@MainActor
struct OCRLifecycleTests {
  @Test func cancellingAnInactiveOCRDoesNotHideAnotherPicker() {
    let windowManager = WindowManager()
    windowManager.showPicker()
    let coordinator = OCRCoordinator()
    coordinator.onActivityChanged = { active in
      if !active { windowManager.hidePicker() }
    }
    coordinator.cancel()
    #expect(windowManager.isPickerVisible)
  }

  @Test func permissionFailureOffersSettingsWithoutRunningOCR() async throws {
    _ = NSApplication.shared
    let image = CGContext(
      data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
      .makeImage()!
    let service = ControlledOCR()
    let capture = FixedScreenCapture(image: image)
    capture.failure = .permissionRequired
    let coordinator = OCRCoordinator(
      service: service, visionService: ImmediateOCR(), capture: capture,
      selector: FixedRegionSelector(image: image))
    defer { coordinator.cancel() }
    coordinator.start()
    try await waitUntil { coordinator.model.phase == .failed }
    #expect(coordinator.model.needsPermission)
    #expect(await service.count == 0)
    #expect(coordinator.isActive)
    coordinator.cancel()
    #expect(!coordinator.isActive)
  }

  @Test func staleRecognitionCannotReplaceTheNextResult() async throws {
    _ = NSApplication.shared
    let image = CGContext(
      data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
      .makeImage()!
    let service = ControlledOCR()
    let coordinator = OCRCoordinator(
      service: service, visionService: ImmediateOCR(), capture: FixedScreenCapture(image: image),
      selector: FixedRegionSelector(image: image))
    defer { coordinator.cancel() }
    coordinator.start()
    try await waitUntil { await service.count == 1 }
    coordinator.start()
    try await waitUntil { await service.count == 2 }
    await service.finish(1, text: "current")
    try await waitUntil { coordinator.model.ocrus.text == "current" }
    await service.finish(0, text: "stale")
    try await Task.sleep(for: .milliseconds(50))
    #expect(coordinator.model.ocrus.text == "current")
    #expect(coordinator.model.phase == .ready)
    coordinator.cancel()
    #expect(coordinator.panel?.isVisible == false)
  }

  @Test func bothEnginesStartTogetherAndVisionIsShownBeforeOcrusFinishes() async throws {
    _ = NSApplication.shared
    let image = makeImage()
    let vision = ControlledOCR()
    let ocrus = ControlledOCR()
    let coordinator = OCRCoordinator(
      service: ocrus, visionService: vision,
      capture: FixedScreenCapture(image: image), selector: FixedRegionSelector(image: image))
    defer { coordinator.cancel() }
    coordinator.start()
    try await waitUntil {
      let visionCount = await vision.count
      let ocrusCount = await ocrus.count
      return visionCount == 1 && ocrusCount == 1
    }
    await vision.finish(0, text: "Vision result")
    try await waitUntil { coordinator.model.vision.phase == .ready }
    #expect(coordinator.model.vision.text == "Vision result")
    #expect(coordinator.model.ocrus.phase == .recognizing)
    #expect(coordinator.model.phase == .recognizing)
    await ocrus.fail(0)
    try await waitUntil { coordinator.model.phase == .ready }
    #expect(coordinator.model.vision.text == "Vision result")
    #expect(coordinator.model.ocrus.phase == .failed)
  }

  @Test func cancelledParallelResultsCannotReappear() async throws {
    _ = NSApplication.shared
    let image = makeImage()
    let vision = ControlledOCR()
    let ocrus = ControlledOCR()
    let coordinator = OCRCoordinator(
      service: ocrus, visionService: vision,
      capture: FixedScreenCapture(image: image), selector: FixedRegionSelector(image: image))
    coordinator.start()
    try await waitUntil {
      let visionCount = await vision.count
      let ocrusCount = await ocrus.count
      return visionCount == 1 && ocrusCount == 1
    }
    coordinator.cancel()
    await vision.finish(0, text: "late Vision")
    await ocrus.finish(0, text: "late ocrus")
    try await Task.sleep(for: .milliseconds(50))
    #expect(coordinator.model.vision.text.isEmpty)
    #expect(coordinator.model.ocrus.text.isEmpty)
    #expect(!coordinator.isActive)
  }

  private func makeImage() -> CGImage {
    CGContext(
      data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
      .makeImage()!
  }

  private func waitUntil(_ condition: () async -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(10)
    while !(await condition()) {
      if ContinuousClock.now >= deadline { throw OCRError.engine("test timed out") }
      try await Task.sleep(for: .milliseconds(10))
    }
  }
}
