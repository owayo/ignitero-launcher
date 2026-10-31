import AppKit

/// Owns each request from capture through editing. A cancelled or superseded
/// request can never overwrite the next result or the user's clipboard.
@MainActor
public final class OCRCoordinator {
  public let model = OCRResultModel()
  public private(set) var isSelecting = false
  public private(set) var isActive = false
  public var onActivityChanged: ((Bool) -> Void)?
  private let service: any OCRRecognizing
  private let visionService: any OCRRecognizing
  private let capture: any OCRScreenCapturing
  private let selector: any OCRRegionSelecting
  private var request: Task<Void, Never>?
  private var requestID = UUID()
  public private(set) var panel: OCRResultPanel?

  public init(
    service: any OCRRecognizing = OCRService(),
    visionService: any OCRRecognizing = VisionOCRService(),
    capture: any OCRScreenCapturing = ScreenCaptureService(),
    selector: any OCRRegionSelecting = OCRRegionSelector()
  ) {
    self.service = service
    self.visionService = visionService
    self.capture = capture
    self.selector = selector
  }

  public func start() {
    if isSelecting {
      cancel()
      return
    }
    cancel()
    let id = UUID()
    requestID = id
    isActive = true
    onActivityChanged?(true)
    model.phase = .capturing
    model.vision.reset()
    model.ocrus.reset()
    model.image = nil
    model.message = ""
    model.needsPermission = false
    request = Task { [weak self] in
      guard let self else { return }
      do {
        let screens = try await capture.captureScreens()
        guard requestID == id, !Task.isCancelled else { return }
        isSelecting = true
        let image = try await selector.select(from: screens)
        guard requestID == id, !Task.isCancelled else { return }
        isSelecting = false
        guard let image else {
          cancel()
          return
        }
        model.image = NSImage(cgImage: image, size: .zero)
        model.phase = .recognizing
        showPanel()
        async let vision: Void = read(image, using: visionService, into: model.vision, id: id)
        async let ocrus: Void = read(image, using: service, into: model.ocrus, id: id)
        _ = await (vision, ocrus)
        guard requestID == id, !Task.isCancelled else { return }
        model.phase = .ready
      } catch is CancellationError {
        if requestID == id { cancel() }
      } catch {
        guard requestID == id, !Task.isCancelled else { return }
        isSelecting = false
        model.phase = .failed
        model.needsPermission = (error as? OCRCaptureError) == .permissionRequired
        model.message = error.localizedDescription
        showPanel()
      }
      if requestID == id { request = nil }
    }
  }

  public func cancel() {
    let wasActive = isActive
    isActive = false
    requestID = UUID()
    request?.cancel()
    request = nil
    selector.cancel()
    isSelecting = false
    panel?.orderOut(nil)
    model.image = nil
    model.vision.reset()
    model.ocrus.reset()
    if wasActive { onActivityChanged?(false) }
  }

  private func showPanel() {
    if panel == nil {
      panel = OCRResultPanel(model: model) { [weak self] in self?.start() }
      panel?.onDismiss = { [weak self] in self?.cancel() }
    }
    panel?.present()
  }

  private func read(
    _ image: CGImage, using service: any OCRRecognizing, into result: OCRBackendModel, id: UUID
  ) async {
    let start = ContinuousClock.now
    do {
      let document = try await service.recognize(image)
      guard requestID == id, !Task.isCancelled else { return }
      result.text = document.text
      if document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        result.phase = .failed
        result.message = "文字が見つかりませんでした。"
      } else {
        result.phase = .ready
      }
    } catch {
      guard requestID == id, !Task.isCancelled else { return }
      result.phase = .failed
      result.message = "読み取りに失敗しました。もう一度お試しください。"
    }
    guard requestID == id, !Task.isCancelled else { return }
    let elapsed = (ContinuousClock.now - start).components
    result.elapsedSeconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
  }
}
