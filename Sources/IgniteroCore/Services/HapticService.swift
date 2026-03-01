import AppKit

/// トラックパッド触覚フィードバックを提供するサービス。
///
/// macOS の `NSHapticFeedbackManager` を使用して、
/// 選択移動・確定・キャンセル時に適切な触覚フィードバックを再生する。
public enum HapticService {

  /// 選択移動時の軽い触覚フィードバック（矢印キーナビゲーション）。
  public static func selectionChanged() {
    NSHapticFeedbackManager.defaultPerformer.perform(
      .alignment,
      performanceTime: .now
    )
  }

  /// 確定時の触覚フィードバック（Enter キー）。
  public static func confirmed() {
    NSHapticFeedbackManager.defaultPerformer.perform(
      .levelChange,
      performanceTime: .now
    )
  }
}
