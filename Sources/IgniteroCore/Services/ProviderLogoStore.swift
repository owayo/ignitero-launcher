import AppKit
import SwiftUI
import os

extension EnvironmentValues {
  /// AI利用枠の画面がブランドアイコンを読むストア。nil なら ``ProviderLogoStore/shared``。
  /// テストで `.app` 以外から実際のアイコンを描くときに差し替える。
  @Entry var providerLogoStore: ProviderLogoStore? = nil
}

/// AI利用枠のプロバイダのブランドアイコン (SVG) を読み込む。
///
/// SVG は `.app` の `Contents/Resources/ProviderLogos/` にある。`make bundle` / `make dev` が
/// `scripts/setup_provider_logos.py` で版とハッシュを確かめてから同梱する
/// (取得元・版・ハッシュは `Resources/provider-logos.lock.json`)。取得した SVG は
/// リポジトリにコミットしない。SwiftPM のリソースバンドルではないので `Bundle.module` も
/// ``ResourceBundle`` も通らない。
///
/// 読めない場合は nil を返し、画面はアイコンなしの文字だけで描く (fail-open)。
/// 結果は成功・失敗とも記憶し、描画のたびにファイルを読まない。
@MainActor
public final class ProviderLogoStore {
  /// アプリが使うストア。`Bundle.main` の `Contents/Resources/ProviderLogos` を読む。
  public static let shared = ProviderLogoStore(directory: defaultDirectory)

  /// `.app` 内の SVG の置き場所。`.app` 以外 (`swift test` など) では存在しない。
  public static var defaultDirectory: URL? {
    Bundle.main.resourceURL?.appendingPathComponent("ProviderLogos", isDirectory: true)
  }

  private static let logger = Logger(
    subsystem: "com.ignitero.launcher", category: "ProviderLogoStore")

  private let directory: URL?
  private var images: [AIUsageProvider: NSImage] = [:]
  private var failures: Set<AIUsageProvider> = []

  public init(directory: URL?) {
    self.directory = directory
  }

  /// プロバイダのアイコン。テンプレート画像なので、描画側で色を付ける。
  public func image(for provider: AIUsageProvider) -> NSImage? {
    if let image = images[provider] { return image }
    if failures.contains(provider) { return nil }
    guard let image = Self.load(provider, from: directory) else {
      failures.insert(provider)
      // 縮退が無音にならないよう、プロバイダごとに 1 度だけ記録する。
      Self.logger.warning(
        "ブランドアイコンを読み込めなかった: \(provider.logoResourceName, privacy: .public).svg"
      )
      return nil
    }
    images[provider] = image
    return image
  }

  static func load(_ provider: AIUsageProvider, from directory: URL?) -> NSImage? {
    guard
      let url = directory?.appendingPathComponent(
        "\(provider.logoResourceName).svg", isDirectory: false),
      let data = try? Data(contentsOf: url),
      let image = NSImage(data: data),
      image.isValid, image.size.width > 0, image.size.height > 0
    else { return nil }
    image.isTemplate = true
    return image
  }

  /// `image` を `side` ピクセル四方に縦横比を保って描いたとき、不透明な画素が占める割合。
  /// SVG を読めても形が描かれない (`isValid` だけでは分からない) 破損を自己診断とテストで検出する。
  public static func coverage(of image: NSImage, side: Int = 32) -> Double {
    guard
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap)
    else { return 0 }
    let scale = min(Double(side) / image.size.width, Double(side) / image.size.height)
    let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    image.draw(
      in: NSRect(
        x: (Double(side) - size.width) / 2, y: (Double(side) - size.height) / 2,
        width: size.width, height: size.height))
    NSGraphicsContext.restoreGraphicsState()
    var opaque = 0
    for y in 0..<side {
      for x in 0..<side where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
        opaque += 1
      }
    }
    return Double(opaque) / Double(side * side)
  }
}
