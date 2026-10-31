import CoreGraphics
import CoreML
import Foundation
import Vision

/// On-device macOS recognition; no additional model or runtime is required.
public struct VisionOCRService: OCRRecognizing {
  public init() {}

  @concurrent
  public func recognize(_ image: CGImage) async throws -> OCRDocument {
    try Task.checkCancellation()
    var request = RecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = [
      Locale.Language(identifier: "ja-JP"), Locale.Language(identifier: "en-US"),
    ]
    request.automaticallyDetectsLanguage = true
    request.usesLanguageCorrection = true
    request.minimumTextHeightFraction = 0
    // Keep first-use recognition independent of Neural Engine compilation.
    // Prefer a supported GPU, with CPU as the fallback, for each stage.
    for (stage, devices) in request.supportedComputeStageDevices {
      let device =
        devices.first {
          if case .gpu = $0 { return true }
          return false
        }
        ?? devices.first {
          if case .cpu = $0 { return true }
          return false
        }
      if let device { request.setComputeDevice(device, for: stage) }
    }
    let observations = try await request.perform(on: image)
    try Task.checkCancellation()
    let lines = observations.compactMap { observation -> OCRDocument.Page.Line? in
      guard let candidate = observation.topCandidates(1).first else { return nil }
      return .init(text: candidate.string, confidence: Double(candidate.confidence))
    }
    return OCRDocument(pages: [.init(lines: lines)])
  }
}
