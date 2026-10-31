import AppKit
import Foundation
import Testing

@testable import IgniteroCore

/// AI利用枠の色分けの規則。期待値は ai-usage (`Native/ai-usage/src/render/palette.rs`・
/// `reset.rs`・`manual_resets.rs`) のテストと同じ境界値で固定する。
@Suite("AI usage color rules")
struct AIUsageStyleTests {
  private static let now = Date(timeIntervalSince1970: 1_781_481_600)  // 2026-06-15T00:00:00Z

  private func reset(
    _ kind: String?, _ remaining: UInt64?, _ expiresAt: String?, paused: Bool? = false
  ) -> AIUsageReset {
    AIUsageReset(kind: kind, remaining: remaining, expires_at: expiresAt, paused: paused)
  }

  // MARK: 使用率

  @Test func usageLevelsEscalateAt60_80_90Percent() {
    let cases: [(Double, AIUsageLevel, Bool)] = [
      (0, .normal, false), (59.9, .normal, false),
      (60, .caution, false), (79.9, .caution, false),
      (80, .warning, true), (89.9, .warning, true),
      (90, .critical, true), (150, .critical, true),
      (.nan, .normal, false),
    ]
    for (percent, level, emphasized) in cases {
      #expect(AIUsageLevel.usage(percent) == level, "\(percent)")
      #expect(AIUsageLevel.usage(percent).isEmphasized == emphasized, "\(percent)")
    }
  }

  // MARK: リセットまでの残り時間

  @Test(arguments: AIUsagePeriod.allCases)
  func countdownThresholdsAreExclusive(period: AIUsagePeriod) {
    // しきい値ちょうどは余裕のある側。境界がずれると赤が 1 段早く/遅く出る。
    let th = period.countdownThresholds
    let cases: [(Int?, AIUsageLevel?)] = [
      (1, .critical), (th.critical - 1, .critical),
      (th.critical, .warning), (th.warning - 1, .warning),
      (th.warning, .caution), (th.caution - 1, .caution),
      (th.caution, .normal),
      (0, .normal), (-1, .normal),  // 期限到来は緑
      (nil, nil),  // 時刻不明は控えめな色
    ]
    for (seconds, level) in cases {
      #expect(
        AIUsageCountdown.level(remainingSeconds: seconds, period: period) == level,
        "\(period) \(String(describing: seconds))")
    }
  }

  @Test func countdownThresholdsMatchAIUsage() {
    let hour = 3_600
    let day = 86_400
    #expect(AIUsagePeriod.fiveHour.countdownThresholds == (hour, 2 * hour, 3 * hour))
    #expect(AIUsagePeriod.daily.countdownThresholds == (4 * hour, 8 * hour, 12 * hour))
    #expect(AIUsagePeriod.weekly.countdownThresholds == (day, 2 * day, 4 * day))
    #expect(AIUsagePeriod.monthly.countdownThresholds == (3 * day, 7 * day, 14 * day))
    // 同じ 2 日後でも、月次は危険域、週次は注意域。
    #expect(AIUsageCountdown.level(remainingSeconds: 2 * day, period: .monthly) == .critical)
    #expect(AIUsageCountdown.level(remainingSeconds: 2 * day, period: .weekly) == .caution)
  }

  @Test func periodComesFromKindAndFallsBackLikeLegacyCaches() {
    #expect(AIUsagePeriod.resolve(kind: "daily", isShortSlot: true, provider: "claude") == .daily)
    #expect(
      AIUsagePeriod.resolve(kind: "monthly", isShortSlot: false, provider: "claude") == .monthly)
    // kind を持たない旧キャッシュ: 短期枠は 5 時間、長期枠は PixelLab / Grok が月次。
    for provider in ["claude", "codex", "antigravity", "pixellab", "grok", "future"] {
      #expect(AIUsagePeriod.resolve(kind: nil, isShortSlot: true, provider: provider) == .fiveHour)
    }
    for provider in ["pixellab", "grok"] {
      #expect(AIUsagePeriod.resolve(kind: nil, isShortSlot: false, provider: provider) == .monthly)
    }
    for provider in ["claude", "codex", "antigravity", "future"] {
      #expect(AIUsagePeriod.resolve(kind: nil, isShortSlot: false, provider: provider) == .weekly)
    }
    // 未知の周期は推測しない。残り時間は出すが色は控えめにし、期限到来だけは緑にする。
    let unknown = AIUsagePeriod.resolve(kind: "quarterly", isShortSlot: false, provider: "claude")
    #expect(unknown == nil)
    #expect(AIUsageCountdown.level(remainingSeconds: 60, period: unknown) == nil)
    #expect(AIUsageCountdown.level(remainingSeconds: 0, period: unknown) == .normal)
  }

  @Test func remainingSecondsTruncateTowardZeroLikeChrono() {
    let now = Self.now
    #expect(AIUsageCountdown.remainingSeconds(until: now.addingTimeInterval(0.9), now: now) == 0)
    #expect(AIUsageCountdown.remainingSeconds(until: now.addingTimeInterval(-0.9), now: now) == 0)
    #expect(AIUsageCountdown.remainingSeconds(until: now.addingTimeInterval(1.5), now: now) == 1)
    // 極端な日時でも整数変換でトラップしない。
    #expect(AIUsageCountdown.remainingSeconds(until: .distantFuture, now: now) > 0)
    #expect(AIUsageCountdown.remainingSeconds(until: .distantPast, now: now) < 0)
  }

  @Test func countdownTextFloorsAndUsesDaysFromOneDay() {
    let cases: [(Int, String)] = [
      (-5, "リセット待ち"), (0, "リセット待ち"),
      (1, "あと1分未満"), (59, "あと1分未満"),
      (60, "あと1分"), (3_599, "あと59分"),
      (3_600, "あと1時間0分"), (86_399, "あと23時間59分"),
      (86_400, "あと1日0時間"), (4 * 86_400 - 1, "あと3日23時間"),
      (4 * 86_400, "あと4日0時間"),
    ]
    for (seconds, text) in cases {
      #expect(AIUsageCountdown.text(remainingSeconds: seconds) == text, "\(seconds)")
    }
    // 表記と色が食い違わない: 週次の「あと3日23時間」は黄、ちょうど 4 日から緑。
    #expect(AIUsageCountdown.level(remainingSeconds: 4 * 86_400 - 1, period: .weekly) == .caution)
    #expect(AIUsageCountdown.level(remainingSeconds: 4 * 86_400, period: .weekly) == .normal)
  }

  // MARK: 日時

  @Test func datesParseEveryRFC3339FormChronoWrites() throws {
    let base = 1_793_458_800.0  // 2026-10-31T15:00:00Z
    let cases: [(String, Double)] = [
      ("2026-10-31T15:00:00+00:00", base),
      ("2026-10-31T15:00:00Z", base),
      ("2026-10-31T15:00:00.5Z", base + 0.5),
      ("2026-10-31T15:00:00.123+00:00", base + 0.123),
      ("2026-10-31T15:00:00.123456789+00:00", base + 0.123457),
      ("2026-11-01T00:00:00+09:00", base),
    ]
    for (text, expected) in cases {
      let date = try #require(AIUsageDate.parse(text), "\(text)")
      #expect(abs(date.timeIntervalSince1970 - expected) < 0.001, "\(text)")
    }
    #expect(AIUsageDate.parse(nil) == nil)
    #expect(AIUsageDate.parse("invalid") == nil)
  }

  // MARK: 手動リセット

  @Test func deadlineIsUrgentOnlyBelowSevenDays() {
    let now = Self.now
    let week: TimeInterval = 7 * 86_400
    let cases: [(TimeInterval?, Bool)] = [
      (0.001, true), (week - 0.001, true),
      (week, false), (week + 0.001, false),
      (0, false), (-0.001, false), (nil, false),
    ]
    for (remaining, urgent) in cases {
      #expect(
        AIUsageManualResets.isDeadlineUrgent(remaining.map { now.addingTimeInterval($0) }, now: now)
          == urgent, "\(String(describing: remaining))")
    }
  }

  @Test func expiredGrantsAreDroppedAndEachDeadlineIsKept() throws {
    let resets = [
      reset("full", 9, "2026-06-15T00:00:00Z"),  // ちょうど now に失効
      reset("full", 1, "2026-06-16T04:00:00Z"),
      reset("full", 2, "2026-06-20T05:00:00Z"),
      reset("five_hour", 0, nil),
    ]
    let groups = AIUsageManualResets.summarize(resets, now: Self.now)
    #expect(groups.map(\.countText) == ["全枠 3回", "5時間 0回"])
    let soon = try #require(AIUsageDate.parse("2026-06-16T04:00:00Z"))
    let later = try #require(AIUsageDate.parse("2026-06-20T05:00:00Z"))
    #expect(groups[0].deadlines == [.init(expiry: soon, count: 1), .init(expiry: later, count: 2)])
    #expect(groups[1].deadlines.isEmpty)
    // すべて失効した後も、通常の付与分のグループは 0 回として残る。
    let after = try #require(AIUsageDate.parse("2026-06-21T00:00:00Z"))
    #expect(
      AIUsageManualResets.summarize(resets, now: after).map(\.countText) == ["全枠 0回", "5時間 0回"])
  }

  @Test func unknownCountsAndExpiriesDoNotMeanZero() {
    let groups = AIUsageManualResets.summarize(
      [reset("full", nil, nil), reset("five_hour", 2, "invalid")], now: Self.now)
    #expect(groups.map(\.countText) == ["全枠 不明", "5時間 2回"])
    #expect(groups[1].deadlines == [.init(expiry: nil, count: 2)])
    #expect(AIUsageManualResets.nearestDeadline(in: groups) == .init(expiry: nil))
  }

  @Test func pausedGrantsAreCountedSeparately() {
    let groups = AIUsageManualResets.summarize(
      [reset("full", 1, "2026-06-20T04:00:00Z", paused: true)], now: Self.now)
    #expect(groups.map(\.countText) == ["全枠 0回", "全枠 停止中 1回"])
    // 残回数 0 の停止中の付与分は出さない。
    let empty = AIUsageManualResets.summarize(
      [reset("full", 0, nil, paused: true)], now: Self.now)
    #expect(empty.map(\.countText) == ["全枠 0回"])
  }

  @Test func kindsKeepAIUsageOrderAndUnknownKindsBecomeOther() {
    let groups = AIUsageManualResets.summarize(
      [
        reset("future_kind", 1, nil), reset("weekly", 1, nil), reset("five_hour", 1, nil),
        reset("full", 1, nil),
      ], now: Self.now)
    #expect(groups.map(\.countText) == ["全枠 1回", "5時間 1回", "1週間 1回", "その他 1回"])
  }

  @Test func countsSaturateInsteadOfOverflowing() {
    let groups = AIUsageManualResets.summarize(
      [reset("full", .max, nil), reset("full", 1, nil)], now: Self.now)
    #expect(groups.first?.total == nil)
    #expect(groups.first?.deadlines == [.init(expiry: nil, count: .max)])
  }

  @Test func nearestDeadlinePrefersAvailableGrantsAcrossKinds() throws {
    let resets = [
      reset("full", 2, "2026-06-20T04:00:00Z"),
      reset("five_hour", 1, "2026-06-16T04:00:00Z"),
      reset("full", 1, "2026-06-18T04:00:00Z"),
      reset("full", 9, "2026-06-15T00:00:00Z"),
    ]
    let earliest = try #require(AIUsageDate.parse("2026-06-16T04:00:00Z"))
    #expect(
      AIUsageManualResets.nearestDeadline(
        in: AIUsageManualResets.summarize(resets, now: Self.now)) == .init(expiry: earliest))
    let after = try #require(AIUsageDate.parse("2026-06-17T00:00:00Z"))
    let next = try #require(AIUsageDate.parse("2026-06-18T04:00:00Z"))
    #expect(
      AIUsageManualResets.nearestDeadline(in: AIUsageManualResets.summarize(resets, now: after))
        == .init(expiry: next))
  }

  @Test func nearestDeadlineUsesPausedGrantsOnlyWithoutAvailableOnes() throws {
    let held = reset("full", 1, "2026-06-16T04:00:00Z", paused: true)
    let available = reset("five_hour", 2, "2026-06-20T04:00:00Z")
    let heldExpiry = try #require(AIUsageDate.parse("2026-06-16T04:00:00Z"))
    let availableExpiry = try #require(AIUsageDate.parse("2026-06-20T04:00:00Z"))
    func nearest(_ resets: [AIUsageReset]) -> AIUsageManualResets.NearestDeadline? {
      AIUsageManualResets.nearestDeadline(
        in: AIUsageManualResets.summarize(resets, now: Self.now))
    }
    #expect(nearest([held, available]) == .init(expiry: availableExpiry))
    #expect(nearest([held]) == .init(expiry: heldExpiry))
    #expect(nearest([held, reset("five_hour", 1, nil)]) == .init(expiry: nil))
    // 残回数が 0 だけなら期限を出さない。
    #expect(nearest([reset("full", 0, nil)]) == nil)
    #expect(nearest([]) == nil)
  }

  @Test func shortDeadlineShowsTheYearOnlyOutsideTheCurrentYear() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
    let sameYear = try #require(AIUsageDate.parse("2026-08-01T12:00:00Z"))
    let nextYear = try #require(AIUsageDate.parse("2027-01-05T00:00:00Z"))
    #expect(
      AIUsageManualResets.shortDateText(sameYear, now: Self.now, calendar: calendar) == "08/01")
    #expect(
      AIUsageManualResets.shortDateText(nextYear, now: Self.now, calendar: calendar)
        == "2027/01/05")
  }

  // MARK: プロバイダ

  @Test func providersUseAIUsageLabelsAndLogos() {
    let expected: [(String, String, String)] = [
      ("claude", "Claude", "claude"),
      ("codex", "Codex", "openai"),
      ("antigravity", "Antigravity", "antigravity"),
      ("pixellab", "PixelLab", "pixellab"),
      ("grok", "Grok", "grok"),
    ]
    #expect(AIUsageProvider.allCases.count == expected.count)
    for (raw, label, logo) in expected {
      let provider = AIUsageProvider(rawValue: raw)
      #expect(provider?.label == label)
      #expect(provider?.logoResourceName == logo)
    }
    #expect(AIUsageProvider.label(for: "future") == "Future")
  }

  // MARK: 色

  /// 文字は背景に対して 4.5:1 以上。実際のウィンドウ背景を外観ごとに解決して測る。
  /// コントラストを上げる設定の外観名は rawValue に "HighContrast" を含まないため、組で渡す。
  @Test(arguments: [
    (NSAppearance.Name.aqua, false), (.darkAqua, false),
    (.accessibilityHighContrastAqua, true), (.accessibilityHighContrastDarkAqua, true),
  ])
  @MainActor
  func levelColorsAreReadableOnTheWindowBackground(
    appearance: NSAppearance.Name, increased: Bool
  ) throws {
    let resolved = try #require(NSAppearance(named: appearance))
    let dark = resolved.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    var background = NSColor.white
    resolved.performAsCurrentDrawingAppearance {
      background = NSColor.windowBackgroundColor.usingColorSpace(.sRGB) ?? .white
    }
    for level in AIUsageLevel.allCases {
      let rgb = AIUsageColors.levelRGB(level, dark: dark, increasedContrast: increased)
      let ratio = Self.contrast(rgb, background)
      #expect(ratio >= 4.5, "\(appearance.rawValue) \(level) \(String(rgb, radix: 16)): \(ratio)")
    }
    // ブランドアイコン (図形) は 3:1 以上。前景色 (nil) は OS が保証する。
    for provider in AIUsageProvider.allCases {
      guard
        let rgb = AIUsageColors.markerRGB(provider, dark: dark, increasedContrast: increased)
      else { continue }
      let ratio = Self.contrast(rgb, background)
      #expect(ratio >= 3, "\(appearance.rawValue) \(provider) \(String(rgb, radix: 16)): \(ratio)")
    }
  }

  @Test func darkPaletteKeepsTheTerminalColorsOfAIUsage() {
    // xterm 256 色の 35・178・208。赤 (196 = #FF0000) だけは 4.5:1 に届かないため明るくする。
    #expect(AIUsageColors.levelRGB(.normal, dark: true, increasedContrast: false) == 0x00AF5F)
    #expect(AIUsageColors.levelRGB(.caution, dark: true, increasedContrast: false) == 0xD7AF00)
    #expect(AIUsageColors.levelRGB(.warning, dark: true, increasedContrast: false) == 0xFF8700)
    #expect(AIUsageColors.levelRGB(.critical, dark: true, increasedContrast: false) == 0xFF4D4D)
  }

  @Test func markersFollowAIUsageBrandColors() {
    #expect(AIUsageColors.markerRGB(.claude, dark: true, increasedContrast: false) == 0xD97757)
    #expect(AIUsageColors.markerRGB(.antigravity, dark: true, increasedContrast: false) == 0x4285F4)
    #expect(AIUsageColors.markerRGB(.pixellab, dark: true, increasedContrast: false) == 0x84CC16)
    // Codex と Grok は端末の白に当たる前景色。コントラストを上げる設定では全て前景色。
    for dark in [false, true] {
      #expect(AIUsageColors.markerRGB(.codex, dark: dark, increasedContrast: false) == nil)
      #expect(AIUsageColors.markerRGB(.grok, dark: dark, increasedContrast: false) == nil)
      for provider in AIUsageProvider.allCases {
        #expect(AIUsageColors.markerRGB(provider, dark: dark, increasedContrast: true) == nil)
      }
    }
  }

  private static func contrast(_ rgb: UInt32, _ background: NSColor) -> Double {
    func channel(_ value: Double) -> Double {
      value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
      0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }
    let foreground = luminance(
      Double((rgb >> 16) & 0xFF) / 255, Double((rgb >> 8) & 0xFF) / 255, Double(rgb & 0xFF) / 255)
    let back = luminance(
      background.redComponent, background.greenComponent, background.blueComponent)
    return (max(foreground, back) + 0.05) / (min(foreground, back) + 0.05)
  }
}
