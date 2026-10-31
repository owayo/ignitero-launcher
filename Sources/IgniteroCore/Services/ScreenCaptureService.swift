import AppKit
import ScreenCaptureKit

public struct OCRCapturedScreen: Sendable {
  public let displayID: CGDirectDisplayID
  public let frame: CGRect
  public let image: CGImage
}

public enum OCRCaptureError: LocalizedError, Equatable {
  case permissionRequired
  case noDisplay

  public var errorDescription: String? {
    switch self {
    case .permissionRequired: "画面上の文字を読み取るには、画面収録の許可が必要です。"
    case .noDisplay: "画面を取得できませんでした。もう一度お試しください。"
    }
  }
}

@MainActor
public protocol OCRScreenCapturing {
  func captureScreens() async throws -> [OCRCapturedScreen]
}

@MainActor
public struct ScreenCaptureService: OCRScreenCapturing {
  public init() {}

  public func captureScreens() async throws -> [OCRCapturedScreen] {
    guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
      throw OCRCaptureError.permissionRequired
    }
    let screens = NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, CGRect)? in
      guard
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
      else { return nil }
      return (number.uint32Value, screen.frame)
    }
    let content = try await SCShareableContent.excludingDesktopWindows(
      false, onScreenWindowsOnly: true)
    let excluded = content.applications.filter {
      $0.processID == ProcessInfo.processInfo.processIdentifier
    }
    var captures: [OCRCapturedScreen] = []
    for (id, frame) in screens {
      try Task.checkCancellation()
      guard let display = content.displays.first(where: { $0.displayID == id }) else {
        throw OCRCaptureError.noDisplay
      }
      let filter = SCContentFilter(
        display: display, excludingApplications: excluded, exceptingWindows: [])
      let config = SCStreamConfiguration()
      let info = SCShareableContent.info(for: filter)
      config.width = Int((info.contentRect.width * CGFloat(info.pointPixelScale)).rounded(.up))
      config.height = Int((info.contentRect.height * CGFloat(info.pointPixelScale)).rounded(.up))
      config.showsCursor = false
      let image = try await SCScreenshotManager.captureImage(
        contentFilter: filter, configuration: config)
      captures.append(OCRCapturedScreen(displayID: id, frame: frame, image: image))
    }
    guard !captures.isEmpty else { throw OCRCaptureError.noDisplay }
    return captures
  }
}

public enum OCRSelectionGeometry {
  /// Selection coordinates are display-local, with a top-left origin. Derive
  /// scale from the actual snapshot; scaled displays need not have a 2x ratio.
  public static func pixelRect(selection: CGRect, screenSize: CGSize, imageSize: CGSize) -> CGRect?
  {
    guard screenSize.width > 0, screenSize.height > 0,
      imageSize.width > 0, imageSize.height > 0,
      [
        selection.minX, selection.minY, selection.maxX, selection.maxY,
        screenSize.width, screenSize.height, imageSize.width, imageSize.height,
      ].allSatisfy(\.isFinite)
    else { return nil }
    let clipped = selection.standardized.intersection(CGRect(origin: .zero, size: screenSize))
    guard !clipped.isNull, clipped.width >= 4, clipped.height >= 4 else { return nil }
    let sx = imageSize.width / screenSize.width
    let sy = imageSize.height / screenSize.height
    return CGRect(
      x: floor(clipped.minX * sx), y: floor(clipped.minY * sy),
      width: ceil(clipped.maxX * sx) - floor(clipped.minX * sx),
      height: ceil(clipped.maxY * sy) - floor(clipped.minY * sy)
    ).intersection(CGRect(origin: .zero, size: imageSize))
  }
}
