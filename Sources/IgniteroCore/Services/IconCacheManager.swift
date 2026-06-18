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

    // アプリ更新で .icns の中身だけ変わった場合に古いキャッシュを返さないよう、
    // ソースの更新日時がキャッシュより新しければ再生成する。
    // ソース mtime が取得できない場合は既存キャッシュをそのまま使う。
    if Self.cacheIsUpToDate(cachePath: outputPath, sourcePath: icnsPath) {
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

    // 自動更新スキャンと手動再構築が重なった場合に同じパスへ並行書き込みが発生し得るため、
    // 一時ファイル + リネームで原子的に書き込み、中途半端な PNG が残らないようにする。
    try pngData.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
    return outputPath
  }
}

extension IconCacheManager {
  /// キャッシュ PNG がソース .icns に対して最新かを判定する。
  ///
  /// - ソースの mtime が取れない（テスト用の存在しないパス等）→ キャッシュをそのまま使う
  /// - キャッシュの mtime が取れない → 再生成
  /// - ソースが新しければ → 再生成
  fileprivate static func cacheIsUpToDate(cachePath: String, sourcePath: String) -> Bool {
    let fm = FileManager.default
    guard fm.fileExists(atPath: cachePath) else { return false }

    guard
      let srcAttrs = try? fm.attributesOfItem(atPath: sourcePath),
      let srcMtime = srcAttrs[.modificationDate] as? Date
    else {
      // ソース更新日時が分からない場合は無用な再生成を避け、既存キャッシュを返す
      return true
    }

    guard
      let cacheAttrs = try? fm.attributesOfItem(atPath: cachePath),
      let cacheMtime = cacheAttrs[.modificationDate] as? Date
    else {
      return false
    }

    return srcMtime <= cacheMtime
  }
}

public enum IconCacheError: Error, Sendable {
  case failedToLoadImage(String)
  case failedToConvertToPNG(String)
}
