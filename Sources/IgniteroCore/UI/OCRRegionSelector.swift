import AppKit

@MainActor
public protocol OCRRegionSelecting: AnyObject {
  func select(from screens: [OCRCapturedScreen]) async throws -> CGImage?
  func cancel()
}

/// The snapshots are captured before these windows exist. Each drag remains on
/// its original display; no global-to-local coordinate conversion is necessary.
@MainActor
public final class OCRRegionSelector: OCRRegionSelecting {
  private var panels: [OCRSelectionPanel] = []
  private var continuation: CheckedContinuation<CGImage?, any Error>?
  private var screenObserver: (any NSObjectProtocol)?
  private var keyMonitor: Any?

  public init() {}

  public func select(from screens: [OCRCapturedScreen]) async throws -> CGImage? {
    cancel()
    let currentFrames = NSScreen.screens.map(\.frame)
    guard screens.allSatisfy({ currentFrames.contains($0.frame) }) else {
      throw OCRCaptureError.noDisplay
    }
    return try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard event.keyCode == 53 else { return event }
        Task { @MainActor in self?.cancel() }
        return nil
      }
      screenObserver = NotificationCenter.default.addObserver(
        forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
      ) { [weak self] _ in
        Task { @MainActor in self?.finish(nil, error: OCRCaptureError.noDisplay) }
      }
      for screen in screens {
        let view = OCRSelectionView(snapshot: screen.image)
        let panel = OCRSelectionPanel(
          contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
          backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.isOpaque = true
        panel.hasShadow = false
        panel.contentView = view
        panel.onCancel = { [weak self] in self?.cancel() }
        view.onSelect = { [weak self] rect in
          let pixelRect = OCRSelectionGeometry.pixelRect(
            selection: rect, screenSize: screen.frame.size,
            imageSize: CGSize(width: screen.image.width, height: screen.image.height))
          self?.finish(pixelRect.flatMap { screen.image.cropping(to: $0) })
        }
        panels.append(panel)
        panel.orderFrontRegardless()
      }
      NSApp.activate()
      let mouse = NSEvent.mouseLocation
      (panels.first { $0.frame.contains(mouse) } ?? panels.first)?.makeKey()
      if panels.isEmpty { finish(nil) }
    }
  }

  public func cancel() { finish(nil) }

  private func finish(_ image: CGImage?, error: (any Error)? = nil) {
    let continuation = self.continuation
    self.continuation = nil
    if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    screenObserver = nil
    if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    keyMonitor = nil
    for panel in panels { panel.orderOut(nil) }
    panels.removeAll()
    if let error {
      continuation?.resume(throwing: error)
    } else {
      continuation?.resume(returning: image)
    }
  }
}

@MainActor
private final class OCRSelectionPanel: NSPanel {
  var onCancel: (() -> Void)?
  override var canBecomeKey: Bool { true }
  override func cancelOperation(_ sender: Any?) { onCancel?() }
  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 { onCancel?() } else { super.keyDown(with: event) }
  }
}

@MainActor
private final class OCRSelectionView: NSView {
  private let snapshot: NSImage
  private var start: CGPoint?
  private var selection: CGRect?
  var onSelect: ((CGRect) -> Void)?
  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }

  init(snapshot: CGImage) {
    self.snapshot = NSImage(cgImage: snapshot, size: .zero)
    super.init(frame: .zero)
    autoresizingMask = [.width, .height]
  }

  required init?(coder: NSCoder) { nil }

  override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

  override func draw(_ dirtyRect: NSRect) {
    snapshot.draw(
      in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
    NSColor.black.withAlphaComponent(0.4).setFill()
    bounds.fill()
    if let selection {
      NSGraphicsContext.saveGraphicsState()
      NSBezierPath(rect: selection).addClip()
      snapshot.draw(
        in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
      NSGraphicsContext.restoreGraphicsState()
      NSColor.white.setStroke()
      let border = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
      border.lineWidth = 1
      border.stroke()
    }
    let text = "読み取る範囲をドラッグしてください　Escでキャンセル"
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 16, weight: .medium),
      .foregroundColor: NSColor.white,
      .backgroundColor: NSColor.black.withAlphaComponent(0.7),
    ]
    (text as NSString).draw(at: CGPoint(x: 24, y: 48), withAttributes: attributes)
  }

  override func mouseDown(with event: NSEvent) {
    window?.makeKey()
    start = convert(event.locationInWindow, from: nil)
    selection = nil
  }

  override func mouseDragged(with event: NSEvent) {
    guard let start else { return }
    let current = convert(event.locationInWindow, from: nil)
    selection = CGRect(
      x: min(start.x, current.x), y: min(start.y, current.y),
      width: abs(current.x - start.x), height: abs(current.y - start.y)
    ).intersection(bounds)
    needsDisplay = true
  }

  override func mouseUp(with event: NSEvent) {
    mouseDragged(with: event)
    guard let selection, selection.width >= 4, selection.height >= 4 else {
      start = nil
      selection = nil
      needsDisplay = true
      return
    }
    onSelect?(selection)
  }
}
