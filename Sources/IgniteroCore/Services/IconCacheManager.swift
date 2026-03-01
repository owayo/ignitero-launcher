import AppKit
import CryptoKit
import Foundation

public struct IconCacheManager: Sendable {
  private let cacheDirectory: String

  public init(cacheDirectory: String = "~/.cache/ignitero/icons/") {
    self.cacheDirectory = NSString(string: cacheDirectory).expandingTildeInPath
  }

  public func cachedIconPath(for appPath: String) -> String {
    let hash = SHA256.hash(data: Data(appPath.utf8))
    let hashString = hash.prefix(16).map { String(format: "%02x", $0) }.joined()
    return (cacheDirectory as NSString).appendingPathComponent("\(hashString).png")
  }

  public func ensureCacheDirectory() throws {
    if !FileManager.default.fileExists(atPath: cacheDirectory) {
      try FileManager.default.createDirectory(
        atPath: cacheDirectory, withIntermediateDirectories: true)
    }
  }

  /// キャッシュ PNG のピクセルサイズ（Retina 対応のため 128px）
  private static let cachePixelSize = 128

  public func cacheIcon(from icnsPath: String, for appPath: String) throws -> String {
    let outputPath = cachedIconPath(for: appPath)

    if FileManager.default.fileExists(atPath: outputPath) {
      return outputPath
    }

    try ensureCacheDirectory()

    guard let image = NSImage(contentsOfFile: icnsPath) else {
      throw IconCacheError.failedToLoadImage(icnsPath)
    }

    // 高解像度: 128x128 ピクセルで描画してキャッシュ
    let px = Self.cachePixelSize
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: px,
      pixelsHigh: px,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    )

    guard let bitmap else {
      throw IconCacheError.failedToConvertToPNG(icnsPath)
    }

    bitmap.size = NSSize(width: px, height: px)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    image.draw(
      in: NSRect(x: 0, y: 0, width: px, height: px),
      from: .zero,
      operation: .copy,
      fraction: 1.0
    )
    NSGraphicsContext.restoreGraphicsState()

    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
      throw IconCacheError.failedToConvertToPNG(icnsPath)
    }

    try pngData.write(to: URL(fileURLWithPath: outputPath))
    return outputPath
  }
}

public enum IconCacheError: Error, Sendable {
  case failedToLoadImage(String)
  case failedToConvertToPNG(String)
}
