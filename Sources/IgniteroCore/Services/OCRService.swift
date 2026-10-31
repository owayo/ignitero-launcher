import CoreGraphics
import Dispatch
import Foundation
import OcrusFFI

public struct OCRDocument: Decodable, Sendable {
  public struct Page: Decodable, Sendable {
    public struct Line: Decodable, Sendable {
      public let text: String
      public let confidence: Double
    }
    public let lines: [Line]
  }
  public let pages: [Page]

  public var text: String {
    pages.flatMap(\.lines).map(\.text).joined(separator: "\n")
  }
}

public enum OCRError: LocalizedError, Sendable {
  case missingModels
  case invalidImage
  case engine(String)
  case enginePanic

  public var errorDescription: String? {
    switch self {
    case .missingModels: "OCR用データが見つかりません。アプリを再インストールしてください。"
    case .invalidImage: "この画像を読み取れません。範囲を小さくしてもう一度お試しください。"
    case .engine, .enginePanic: "文字を読み取れませんでした。もう一度お試しください。"
    }
  }
}

public protocol OCRRecognizing: Sendable {
  func recognize(_ image: CGImage) async throws -> OCRDocument
}

/// All blocking Rust work uses a dedicated executor, including model loading and
/// bitmap conversion. No subprocess, image file or Python runtime is involved.
public actor OCRService: OCRRecognizing {
  private nonisolated let queue = DispatchSerialQueue(
    label: "com.ignitero.ocr", qos: .userInitiated)
  public nonisolated var unownedExecutor: UnownedSerialExecutor {
    queue.asUnownedSerialExecutor()
  }

  private let modelDirectory: URL?
  private var engine: NativeOCREngine?

  public init(modelDirectory: URL? = nil) {
    self.modelDirectory = modelDirectory
  }

  /// Packaging diagnostic: deliberately does not use developer-machine fallbacks.
  public static func validateBundledModels(bundle: Bundle = .main) throws {
    guard let directory = bundle.resourceURL?.appendingPathComponent("OcrusModels") else {
      throw OCRError.missingModels
    }
    _ = try NativeOCREngine(directory: directory)
  }

  public static func resolveModelDirectory(
    bundle: Bundle = .main,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    home: URL = FileManager.default.homeDirectoryForCurrentUser
  ) -> URL? {
    var candidates: [URL] = []
    if let bundled = bundle.resourceURL?.appendingPathComponent("OcrusModels") {
      candidates.append(bundled)
    }
    if let path = environment["OCRUS_MODEL_DIR"], !path.isEmpty {
      candidates.append(URL(fileURLWithPath: path, isDirectory: true))
    }
    candidates.append(home.appendingPathComponent(".ocrus/models", isDirectory: true))
    return candidates.first { directory in
      ["rec.ocnn", "dict.txt"].allSatisfy {
        FileManager.default.isReadableFile(atPath: directory.appendingPathComponent($0).path)
      }
    }
  }

  public func recognize(_ image: CGImage) async throws -> OCRDocument {
    try Task.checkCancellation()
    if engine == nil {
      guard let directory = modelDirectory ?? Self.resolveModelDirectory() else {
        throw OCRError.missingModels
      }
      engine = try NativeOCREngine(directory: directory)
    }
    let token = try OCRCancellation()
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      do {
        let document = try engine!.recognize(image, token: token)
        try Task.checkCancellation()
        return document
      } catch OCRError.enginePanic {
        // Cancellation and input errors leave the model reusable. Only a panic
        // poisons the Rust handle and requires recreating it.
        engine = nil
        throw OCRError.enginePanic
      }
    } onCancel: {
      token.cancel()
    }
  }
}

/// Rust guarantees that cancellation may be requested from another thread.
/// Both the operation and cancellation handler retain this token until done.
private final class OCRCancellation: @unchecked Sendable {
  let pointer: OpaquePointer

  init() throws {
    guard let pointer = ocrus_cancel_create() else { throw OCRError.engine("cancel allocation") }
    self.pointer = pointer
  }

  func cancel() { ocrus_cancel_request(pointer) }
  deinit { ocrus_cancel_free(pointer) }
}

/// Owned by OCRService's serial executor. Sendable only permits destruction when
/// the actor is released; calls using this handle never overlap.
private final class NativeOCREngine: @unchecked Sendable {
  private let pointer: OpaquePointer

  init(directory: URL) throws {
    guard ocrus_abi_version() == 1 else { throw OCRError.engine("unsupported ABI") }
    var pointer: OpaquePointer?
    var error: UnsafeMutablePointer<CChar>?
    defer { ocrus_string_free(error) }
    let status = directory.path.withCString {
      ocrus_engine_create($0, 0, 4, &pointer, &error)
    }
    guard status == 0, let pointer else {
      throw OCRError.engine(error.map { String(cString: $0) } ?? "model load failed")
    }
    self.pointer = pointer
  }

  deinit { ocrus_engine_free(pointer) }

  func recognize(_ image: CGImage, token: OCRCancellation) throws -> OCRDocument {
    let width = image.width
    let height = image.height
    guard width > 0, height > 0, width <= 40_000_000 / height,
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
    else { throw OCRError.invalidImage }
    let stride = width * 4
    var pixels = Data(count: stride * height)
    let document: OCRDocument = try pixels.withUnsafeMutableBytes { bytes in
      guard
        let context = CGContext(
          data: bytes.baseAddress, width: width, height: height,
          bitsPerComponent: 8, bytesPerRow: stride, space: colorSpace,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        )
      else { throw OCRError.invalidImage }
      context.setFillColor(CGColor(gray: 1, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      var json: UnsafeMutablePointer<CChar>?
      var error: UnsafeMutablePointer<CChar>?
      defer {
        ocrus_string_free(json)
        ocrus_string_free(error)
      }
      let status = ocrus_recognize_pixels(
        pointer, bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count,
        UInt32(width), UInt32(height), stride, 0, token.pointer, &json, &error)
      if status == 3 { throw CancellationError() }
      if status == 4 { throw OCRError.enginePanic }
      guard status == 0, let json else {
        throw OCRError.engine(error.map { String(cString: $0) } ?? "recognition failed")
      }
      return try JSONDecoder().decode(OCRDocument.self, from: Data(String(cString: json).utf8))
    }
    return document
  }
}
