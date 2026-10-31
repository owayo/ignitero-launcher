import Foundation

// MARK: - AI利用枠の色分けの規則

/// ai-usage の 4 段階の警告色 (緑・黄・橙・赤) に対応する段階。
///
/// しきい値と境界の扱いは ai-usage (`Native/ai-usage/src/render/palette.rs`・`reset.rs`) と
/// 同じにする。ここは段階の判定だけを持ち、色の値は ``AIUsageColors`` が決める。
public enum AIUsageLevel: Int, Comparable, Sendable, CaseIterable {
  case normal
  case caution
  case warning
  case critical

  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

  /// 利用枠の使用率 (%) の段階。60・80・90% ちょうどは上の段階に入る。
  /// 比べられない値 (NaN) は ``normal`` になる (ai-usage の `Level::of` と同じ)。
  public static func usage(_ percent: Double) -> AIUsageLevel {
    if percent >= 90 { return .critical }
    if percent >= 80 { return .warning }
    if percent >= 60 { return .caution }
    return .normal
  }

  /// 使用率の数字を太字にするか。ai-usage と同じく上の 2 段階 (80% 以上) だけ。
  public var isEmphasized: Bool { self >= .warning }
}

/// 利用枠の周期。リセットまでの残り時間の色のしきい値を決める。
public enum AIUsagePeriod: Sendable, CaseIterable {
  case fiveHour
  case daily
  case weekly
  case monthly

  /// JSON の `kind`。欠落 (nil) と未知の値はどちらも nil を返す。区別は ``resolve(kind:isShortSlot:provider:)`` が行う。
  public init?(kind: String?) {
    switch kind {
    case "five_hour": self = .fiveHour
    case "daily": self = .daily
    case "weekly": self = .weekly
    case "monthly": self = .monthly
    default: return nil
    }
  }

  /// 枠の周期。`kind` が無い旧キャッシュでは、短期枠を 5 時間、長期枠を PixelLab と Grok は月次、
  /// それ以外は週次として扱う (ai-usage の `legacy_long_window_thresholds` と同じ)。
  /// 未知の `kind` は周期を推測せず nil を返す。新しい周期を別の周期のしきい値で塗らないため。
  public static func resolve(kind: String?, isShortSlot: Bool, provider: String) -> AIUsagePeriod? {
    guard let kind else {
      if isShortSlot { return .fiveHour }
      switch AIUsageProvider(rawValue: provider) {
      case .pixellab, .grok: return .monthly
      default: return .weekly
      }
    }
    return AIUsagePeriod(kind: kind)
  }

  /// リセットまでの残り時間の境界 (秒、昇順)。これ未満なら赤・橙・黄になる。
  public var countdownThresholds: (critical: Int, warning: Int, caution: Int) {
    let hour = 3_600
    let day = 86_400
    switch self {
    case .fiveHour: return (hour, 2 * hour, 3 * hour)
    case .daily: return (4 * hour, 8 * hour, 12 * hour)
    case .weekly: return (day, 2 * day, 4 * day)
    case .monthly: return (3 * day, 7 * day, 14 * day)
    }
  }
}

/// リセットまでの残り時間の判定と表記。
public enum AIUsageCountdown {
  /// `date` までの残り秒数。ai-usage の `num_seconds()` と同じく 0 方向へ切り捨てる。
  /// 壊れた日時で整数変換がトラップしないよう、極端な値は丸め込む。
  public static func remainingSeconds(until date: Date, now: Date) -> Int {
    let interval = date.timeIntervalSince(now)
    guard interval.isFinite else { return interval > 0 ? Int.max : Int.min }
    let limit = 1e15
    return Int(min(limit, max(-limit, interval)).rounded(.towardZero))
  }

  /// 残り時間の段階。nil は色を決められない (時刻不明・周期不明) ことを表し、控えめな色で描く。
  /// 期限を過ぎていれば ``AIUsageLevel/normal``。境界ちょうどは余裕のある側に入る。
  public static func level(remainingSeconds: Int?, period: AIUsagePeriod?) -> AIUsageLevel? {
    guard let seconds = remainingSeconds else { return nil }
    if seconds <= 0 { return .normal }
    guard let thresholds = period?.countdownThresholds else { return nil }
    if seconds < thresholds.critical { return .critical }
    if seconds < thresholds.warning { return .warning }
    if seconds < thresholds.caution { return .caution }
    return .normal
  }

  /// 残り時間の表記。1 日以上は「あとD日H時間」、それ未満は「あとH時間M分」「あとM分」。
  /// ai-usage と同じく切り捨てで数える。色は丸める前の秒数で決めるため、
  /// 週次の「あと3日23時間」は黄、ちょうど 4 日から緑になり、表記としきい値が食い違わない。
  public static func text(remainingSeconds seconds: Int) -> String {
    guard seconds > 0 else { return "リセット待ち" }
    guard seconds >= 60 else { return "あと1分未満" }
    let days = seconds / 86_400
    let hours = seconds % 86_400 / 3_600
    let minutes = seconds % 3_600 / 60
    if days > 0 { return "あと\(days)日\(hours)時間" }
    if hours > 0 { return "あと\(hours)時間\(minutes)分" }
    return "あと\(minutes)分"
  }
}

/// ai-usage が返す日時 (`to_rfc3339()`。小数秒は 0・3・6・9 桁) の解析。
public enum AIUsageDate {
  private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
  private static let whole = Date.ISO8601FormatStyle()

  public static func parse(_ text: String?) -> Date? {
    guard let text else { return nil }
    return (try? fractional.parse(text)) ?? (try? whole.parse(text))
  }
}

// MARK: - 手動リセット

/// 手動リセットの種類。ai-usage の `ResetKind` と同じ 4 種類で、未知の値は ``other``。
public enum AIUsageResetKind: CaseIterable, Sendable {
  case full
  case fiveHour
  case weekly
  case other

  public init(kind: String?) {
    switch kind {
    case "full": self = .full
    case "five_hour": self = .fiveHour
    case "weekly": self = .weekly
    default: self = .other
    }
  }

  public var title: String {
    switch self {
    case .full: "全枠"
    case .fiveHour: "5時間"
    case .weekly: "1週間"
    case .other: "その他"
    }
  }
}

/// 種類と一時停止の有無ごとにまとめた手動リセット。
public struct AIUsageResetGroup: Equatable, Sendable {
  public struct Deadline: Equatable, Sendable {
    /// 有効期限。nil は不明。
    public let expiry: Date?
    /// その期限で切れる残回数。
    public let count: UInt64
  }

  public let kind: AIUsageResetKind
  public let paused: Bool
  /// 残回数の合計。1 件でも不明なら nil (取得できた 0 回と区別する)。
  public let total: UInt64?
  /// 有効期限ごとの残回数。期限不明を先頭に、期限の早い順。残回数 0 の付与分は含めない。
  public let deadlines: [Deadline]

  /// 一覧の行の表記 (「全枠 2回」「全枠 停止中 1回」「5時間 不明」)。
  public var countText: String {
    let label = paused ? "\(kind.title) 停止中" : kind.title
    return "\(label) \(total.map { "\($0)回" } ?? "不明")"
  }
}

/// 手動リセットの集計と有効期限の判定。ai-usage の `render/manual_resets.rs` と同じ規則。
public enum AIUsageManualResets {
  /// 種類 (全枠・5時間・1週間・その他) と一時停止の有無でまとめる。
  ///
  /// 期限を過ぎた付与分は数えない (キャッシュが古くても失効分を残回数に含めない)。
  /// 通常の付与分のグループは、該当が無くても残回数 0 として残す。一時停止中のグループは
  /// 残回数が 0 のときは出さない。
  public static func summarize(_ resets: [AIUsageReset], now: Date) -> [AIUsageResetGroup] {
    var groups: [AIUsageResetGroup] = []
    for kind in AIUsageResetKind.allCases {
      let entries = resets.filter { AIUsageResetKind(kind: $0.kind) == kind }
      if entries.isEmpty { continue }
      for paused in [false, true] {
        let subset = entries.filter { ($0.paused ?? false) == paused }
        if paused && subset.isEmpty { continue }
        var total: UInt64? = 0
        var counts: [Date?: UInt64] = [:]
        for reset in subset {
          let expiry = AIUsageDate.parse(reset.expires_at)
          if let expiry, expiry <= now { continue }
          if let sum = total, let count = reset.remaining {
            let (value, overflow) = sum.addingReportingOverflow(count)
            total = overflow ? nil : value
          } else {
            total = nil
          }
          if let count = reset.remaining, count > 0 {
            let (value, overflow) = counts[expiry, default: 0].addingReportingOverflow(count)
            counts[expiry] = overflow ? .max : value
          }
        }
        if paused && total == 0 { continue }
        let deadlines = counts.map { AIUsageResetGroup.Deadline(expiry: $0.key, count: $0.value) }
          .sorted { lhs, rhs in
            switch (lhs.expiry, rhs.expiry) {
            case (nil, nil): false
            case (nil, _): true
            case (_, nil): false
            case (let left?, let right?): left < right
            }
          }
        groups.append(
          AIUsageResetGroup(kind: kind, paused: paused, total: total, deadlines: deadlines))
      }
    }
    return groups
  }

  /// 一覧に出す 1 件の有効期限。statusline と同じく利用できる付与分を優先し、
  /// それが無ければ一時停止中の付与分から選ぶ。付与分が無ければ nil。
  /// 戻り値の `expiry` が nil なら、残っている付与分の期限がどれも不明。
  public static func nearestDeadline(in groups: [AIUsageResetGroup]) -> NearestDeadline? {
    let usePaused = !groups.contains { !$0.paused && !$0.deadlines.isEmpty }
    let candidates = groups.filter { $0.paused == usePaused }.flatMap { $0.deadlines }
    guard !candidates.isEmpty else { return nil }
    return NearestDeadline(expiry: candidates.compactMap(\.expiry).min())
  }

  public struct NearestDeadline: Equatable, Sendable {
    public let expiry: Date?
  }

  /// 期限を強調 (赤) するか。残り 0 秒超 7 日未満だけ。ちょうど 7 日・期限切れ・不明は強調しない
  /// (ai-usage の `manual_reset_deadline` と同じ)。
  public static func isDeadlineUrgent(_ expiry: Date?, now: Date) -> Bool {
    guard let expiry else { return false }
    let remaining = expiry.timeIntervalSince(now)
    return remaining > 0 && remaining < 7 * 86_400
  }

  /// 一覧の狭い列に出す期限の日付。今年なら「11/05」、それ以外は「2027/01/05」。
  /// 時刻は詳細とツールチップで示す。
  public static func shortDateText(_ date: Date, now: Date, calendar: Calendar = .current) -> String
  {
    let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
    let style =
      sameYear
      ? Date.VerbatimFormatStyle(
        format: "\(month: .twoDigits)/\(day: .twoDigits)", timeZone: calendar.timeZone,
        calendar: calendar)
      : Date.VerbatimFormatStyle(
        format: "\(year: .defaultDigits)/\(month: .twoDigits)/\(day: .twoDigits)",
        timeZone: calendar.timeZone, calendar: calendar)
    return date.formatted(style)
  }
}

// MARK: - プロバイダ

/// ai-usage が返すプロバイダ。JSON の `provider` (小文字) を rawValue に持つ。
public enum AIUsageProvider: String, CaseIterable, Sendable {
  case claude
  case codex
  case antigravity
  case pixellab
  case grok

  /// 表示名。ai-usage の `Provider::label` と同じ綴り (`PixelLab` は L が大文字)。
  public var label: String {
    switch self {
    case .claude: "Claude"
    case .codex: "Codex"
    case .antigravity: "Antigravity"
    case .pixellab: "PixelLab"
    case .grok: "Grok"
    }
  }

  /// ブランドアイコンの SVG のファイル名 (拡張子なし)。ai-usage の statusline の `--logos` と
  /// 同じ対応にする (Codex は OpenAI のマーク)。
  public var logoResourceName: String {
    switch self {
    case .claude: "claude"
    case .codex: "openai"
    case .antigravity: "antigravity"
    case .pixellab: "pixellab"
    case .grok: "grok"
    }
  }

  /// 未知のプロバイダでも行を描けるよう、表示名は JSON の値から作る。
  public static func label(for provider: String) -> String {
    AIUsageProvider(rawValue: provider)?.label ?? provider.capitalized
  }
}
