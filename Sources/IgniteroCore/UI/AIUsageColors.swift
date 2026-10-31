import SwiftUI

/// AI利用枠の表示色。
///
/// どの要素を何段階の色にするかは ai-usage と同じ (``AIUsageLevel`` / ``AIUsageCountdown`` /
/// ``AIUsageManualResets``)。色の値だけをネイティブの背景に合わせて変える。端末の色
/// (xterm 256 色の 35・178・208・196) をそのまま白い背景に置くと、文字のコントラストが
/// 2〜4:1 しかなく読めないため。
///
/// - ダーク: ai-usage の端末色を基準にする。赤だけは 196 (#FF0000) だと背景に対して
///   4.2:1 しかないため、明るくした #FF4D4D を使う。
/// - ライト: 同じ色相のまま暗くし、白い背景で 5.4:1 以上にする。
/// - コントラストを上げる設定: さらに明暗の差を広げる (約 10:1)。
///
/// 値は sRGB の 24 bit で持ち、テストで実際のウィンドウ背景とのコントラスト比を検査する。
public enum AIUsageColors {
  /// 段階の色 (sRGB)。使用率の数字・バーの点灯部・リセットまでの残り時間に使う。
  public static func levelRGB(_ level: AIUsageLevel, dark: Bool, increasedContrast: Bool)
    -> UInt32
  {
    switch (dark, increasedContrast) {
    case (false, false):
      switch level {
      case .normal: 0x007A45
      case .caution: 0x856300
      case .warning: 0xA84A00
      case .critical: 0xC8102E
      }
    case (true, false):
      switch level {
      case .normal: 0x00AF5F
      case .caution: 0xD7AF00
      case .warning: 0xFF8700
      case .critical: 0xFF4D4D
      }
    case (false, true):
      switch level {
      case .normal: 0x004C2A
      case .caution: 0x4D3B00
      case .warning: 0x6B2D00
      case .critical: 0x7D1610
      }
    case (true, true):
      switch level {
      case .normal: 0x62E6A1
      case .caution: 0xFFE080
      case .warning: 0xFFB36B
      case .critical: 0xFF9D98
      }
    }
  }

  /// プロバイダの印 (ブランドアイコン) の色 (sRGB)。nil は前景色 (`.primary`) で描く。
  ///
  /// ai-usage と同じく、ブランド色が背景に沈むものは読める色へ替える。
  /// Codex (OpenAI) と Grok (xAI) は白黒のブランドなので、端末の白に当たる前景色にする。
  /// PixelLab の黄緑 (#84CC16) は白い背景で 2:1 しかないため、ライトでは同系の濃い緑にする。
  /// コントラストを上げる設定では、形と名前で見分けられるため全て前景色にする。
  public static func markerRGB(_ provider: AIUsageProvider, dark: Bool, increasedContrast: Bool)
    -> UInt32?
  {
    if increasedContrast { return nil }
    switch provider {
    case .claude: return 0xD97757
    case .antigravity: return 0x4285F4
    case .pixellab: return dark ? 0x84CC16 : 0x4D7C0F
    case .codex, .grok: return nil
    }
  }

  public static func level(
    _ level: AIUsageLevel, scheme: ColorScheme, contrast: ColorSchemeContrast
  ) -> Color {
    color(levelRGB(level, dark: scheme == .dark, increasedContrast: contrast == .increased))
  }

  public static func marker(
    _ provider: AIUsageProvider, scheme: ColorScheme, contrast: ColorSchemeContrast
  ) -> Color {
    markerRGB(provider, dark: scheme == .dark, increasedContrast: contrast == .increased)
      .map(color) ?? .primary
  }

  static func color(_ rgb: UInt32) -> Color {
    Color(
      .sRGB,
      red: Double((rgb >> 16) & 0xFF) / 255,
      green: Double((rgb >> 8) & 0xFF) / 255,
      blue: Double(rgb & 0xFF) / 255,
      opacity: 1)
  }
}
