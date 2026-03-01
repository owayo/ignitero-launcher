import os

/// アプリケーションのパフォーマンス計測ユーティリティ。
///
/// `OSSignposter` による signpost 計測と `ContinuousClock` による
/// ミリ秒単位の実行時間計測を提供する。
/// Instruments の Time Profiler / os_signpost で可視化可能。
public enum PerformanceMonitor: Sendable {

  // MARK: - Private

  private static let signposter = OSSignposter(
    subsystem: "com.ignitero.launcher",
    category: "Performance"
  )

  private static let logger = Logger(
    subsystem: "com.ignitero.launcher",
    category: "Performance"
  )

  // MARK: - Signpost API

  /// signpost インターバルを開始し、状態を返す。
  ///
  /// Instruments で計測区間を可視化するために使用する。
  /// 返された `OSSignpostIntervalState` を `endInterval(_:_:)` に渡して終了する。
  ///
  /// - Parameter name: signpost の名前（StaticString）
  /// - Returns: インターバル状態
  public static func beginInterval(_ name: StaticString) -> OSSignpostIntervalState {
    let id = signposter.makeSignpostID()
    let state = signposter.beginInterval(name, id: id)
    return state
  }

  /// signpost インターバルを終了する。
  ///
  /// - Parameters:
  ///   - name: `beginInterval` で使用したものと同じ名前
  ///   - state: `beginInterval` から返された状態
  public static func endInterval(_ name: StaticString, _ state: OSSignpostIntervalState) {
    signposter.endInterval(name, state)
  }

  // MARK: - Measurement API

  /// 同期ブロックの実行時間をミリ秒単位で計測する。
  ///
  /// `ContinuousClock` を使用して高精度な時間計測を行い、
  /// 結果を `os.Logger` に出力する。
  ///
  /// - Parameters:
  ///   - name: 計測名（ログ出力に使用）
  ///   - block: 計測対象の処理
  /// - Returns: 実行時間（ミリ秒）
  @discardableResult
  public static func measure(_ name: String, block: () throws -> Void) rethrows -> Double {
    let start = ContinuousClock.now
    try block()
    let duration = ContinuousClock.now - start
    let ms = durationToMilliseconds(duration)
    logger.info("\(name): \(ms, format: .fixed(precision: 2))ms")
    return ms
  }

  /// 非同期ブロックの実行時間をミリ秒単位で計測する。
  ///
  /// - Parameters:
  ///   - name: 計測名（ログ出力に使用）
  ///   - block: 計測対象の非同期処理
  /// - Returns: 実行時間（ミリ秒）
  @discardableResult
  public static func measureAsync(
    _ name: String,
    block: () async throws -> Void
  ) async rethrows -> Double {
    let start = ContinuousClock.now
    try await block()
    let duration = ContinuousClock.now - start
    let ms = durationToMilliseconds(duration)
    logger.info("\(name): \(ms, format: .fixed(precision: 2))ms")
    return ms
  }

  // MARK: - Private Helpers

  /// `Duration` をミリ秒の `Double` 値に変換する。
  private static func durationToMilliseconds(_ duration: Duration) -> Double {
    let components = duration.components
    let secondsMs = Double(components.seconds) * 1000.0
    let attosecondsMs = Double(components.attoseconds) / 1_000_000_000_000_000.0
    return secondsMs + attosecondsMs
  }
}
