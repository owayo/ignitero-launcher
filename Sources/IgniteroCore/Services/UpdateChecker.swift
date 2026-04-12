import Foundation
import os

// MARK: - URLSession プロトコル

/// テスト用に URLSession を差し替え可能にするプロトコル。
public protocol URLSessionProtocol: Sendable {
  func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

// MARK: - URLSession 準拠

extension URLSession: URLSessionProtocol {}

// MARK: - GitHub リリースモデル

/// GitHub Releases API から返されるリリース情報。
public struct GitHubRelease: Codable, Sendable {
  public let tagName: String
  public let prerelease: Bool
  public let htmlURL: String

  enum CodingKeys: String, CodingKey {
    case tagName = "tag_name"
    case prerelease
    case htmlURL = "html_url"
  }
}

// MARK: - アップデート確認結果

/// アップデートチェックの結果。
public struct UpdateCheckResult: Sendable, Equatable {
  /// 最新バージョン（v プレフィックスなし）
  public let latestVersion: String
  /// ダウンロード URL
  public let downloadURL: String

  public init(latestVersion: String, downloadURL: String) {
    self.latestVersion = latestVersion
    self.downloadURL = downloadURL
  }
}

// MARK: - バージョン比較

/// セマンティックバージョニングの比較ユーティリティ。
public enum VersionComparator {
  /// `candidate` が `current` より新しいかどうかを判定する。
  ///
  /// - Parameters:
  ///   - candidate: 比較対象のバージョン文字列
  ///   - current: 現在のバージョン文字列
  /// - Returns: `candidate` が `current` より新しい場合は `true`
  public static func isNewer(_ candidate: String, than current: String) -> Bool {
    let candidateParts = parseVersion(candidate)
    let currentParts = parseVersion(current)

    let maxLength = max(candidateParts.count, currentParts.count)

    for i in 0..<maxLength {
      let c = i < candidateParts.count ? candidateParts[i] : 0
      let v = i < currentParts.count ? currentParts[i] : 0

      if c > v { return true }
      if c < v { return false }
    }

    return false  // 同じバージョン
  }

  /// バージョン文字列を数値配列にパースする。
  ///
  /// "v" プレフィックスを除去し、"." で分割して各セグメントを数値に変換する。
  private static func parseVersion(_ version: String) -> [Int] {
    var v = version
    if v.hasPrefix("v") || v.hasPrefix("V") {
      v = String(v.dropFirst())
    }
    return v.split(separator: ".").compactMap { Int($0) }
  }
}

// MARK: - アップデート確認

/// GitHub Releases API を使用してアップデートを確認するチェッカー。
///
/// 以下の機能を提供する:
/// - GitHub Releases API で最新バージョンを確認
/// - 12時間のキャッシュでAPIコールを削減
/// - プレリリースバージョンのスキップ
/// - ユーザーが非表示にしたバージョンの通知抑制
/// - ネットワークエラー時のサイレント失敗
public struct UpdateChecker: Sendable {
  private static let logger = Logger(
    subsystem: "com.ignitero.launcher", category: "UpdateChecker")

  /// キャッシュの有効期間（12時間）
  private static let cacheExpiry: TimeInterval = 12 * 3600

  /// API リクエストのタイムアウト（10秒）
  private static let requestTimeout: TimeInterval = 10

  // MARK: - 依存関係

  private let session: any URLSessionProtocol
  private let settingsManager: SettingsManager
  private let owner: String
  private let repo: String

  // MARK: - 初期化

  /// UpdateChecker を初期化する。
  ///
  /// - Parameters:
  ///   - session: HTTP リクエストに使用するセッション。テスト時に差し替え可能。
  ///   - settingsManager: キャッシュの読み書きに使用する設定マネージャ
  ///   - owner: GitHub リポジトリのオーナー
  ///   - repo: GitHub リポジトリ名
  public init(
    session: any URLSessionProtocol = URLSession.shared,
    settingsManager: SettingsManager,
    owner: String = "owayo",
    repo: String = "ignitero-launcher"
  ) {
    self.session = session
    self.settingsManager = settingsManager
    self.owner = owner
    self.repo = repo
  }

  // MARK: - 公開 API

  /// アップデートを確認する。
  ///
  /// 以下のロジックで動作する:
  /// 1. キャッシュが12時間以内であればキャッシュ値を使用
  /// 2. GitHub Releases API から最新リリースを取得
  /// 3. プレリリースをフィルタし、最新の安定版を選択
  /// 4. 現在のバージョンより新しい場合のみ結果を返す
  /// 5. ユーザーが非表示にしたバージョンは結果を返さない
  /// 6. ネットワークエラー時はキャッシュ値にフォールバック
  ///
  /// - Parameter currentVersion: 現在のアプリバージョン
  /// - Returns: 新しいバージョンがある場合は `UpdateCheckResult`、なければ `nil`
  @MainActor
  public func checkForUpdate(currentVersion: String) async -> UpdateCheckResult? {
    let cache = settingsManager.settings.updateCache
    let dismissedVersion = cache?.dismissedVersion

    // キャッシュチェック
    if let cache, let checkedAt = cache.checkedAt,
      Date().timeIntervalSince(checkedAt) < Self.cacheExpiry
    {
      Self.logger.debug("Using cached update check result")
      return buildResult(
        cachedVersion: cache.latestVersion,
        currentVersion: currentVersion,
        dismissedVersion: dismissedVersion,
        downloadURL: cache.downloadURL
      )
    }

    // API からフェッチ
    do {
      let result = try await fetchLatestRelease(currentVersion: currentVersion)

      // キャッシュを更新
      if let result {
        updateCache(latestVersion: result.latestVersion, downloadURL: result.downloadURL)
      } else {
        // 新しいバージョンがない場合でもチェック日時を更新
        updateCache(latestVersion: currentVersion)
      }

      // 非表示済みバージョンのチェック
      if let result, let dismissedVersion, result.latestVersion == dismissedVersion {
        return nil
      }

      return result
    } catch {
      Self.logger.warning("Update check failed: \(error.localizedDescription)")
      // ネットワークエラー時はキャッシュ値を使用（downloadURLもキャッシュから復元）
      return buildResult(
        cachedVersion: cache?.latestVersion,
        currentVersion: currentVersion,
        dismissedVersion: dismissedVersion,
        downloadURL: cache?.downloadURL
      )
    }
  }

  // MARK: - 非公開メソッド

  /// GitHub Releases API から最新の安定リリースを取得する。
  private func fetchLatestRelease(currentVersion: String) async throws -> UpdateCheckResult? {
    let urlString = "https://api.github.com/repos/\(owner)/\(repo)/releases"
    guard let url = URL(string: urlString) else {
      Self.logger.error("Invalid URL: \(urlString)")
      return nil
    }

    var request = URLRequest(url: url)
    request.timeoutInterval = Self.requestTimeout
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

    let (data, _) = try await session.data(for: request)

    let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)

    // プレリリースをフィルタし、安定版のみを対象にする
    let stableReleases = releases.filter { !$0.prerelease }

    guard let latestRelease = stableReleases.first else {
      Self.logger.debug("No stable releases found")
      return nil
    }

    let latestVersion = stripVPrefix(latestRelease.tagName)

    // バージョン比較
    guard VersionComparator.isNewer(latestVersion, than: currentVersion) else {
      Self.logger.debug("Current version \(currentVersion) is up to date")
      return nil
    }

    return UpdateCheckResult(
      latestVersion: latestVersion,
      downloadURL: latestRelease.htmlURL
    )
  }

  /// キャッシュから結果を構築する。
  private func buildResult(
    cachedVersion: String?,
    currentVersion: String,
    dismissedVersion: String?,
    downloadURL: String?
  ) -> UpdateCheckResult? {
    guard let cachedVersion else { return nil }

    // 非表示済みバージョンのチェック
    if let dismissedVersion, cachedVersion == dismissedVersion {
      return nil
    }

    // バージョン比較
    guard VersionComparator.isNewer(cachedVersion, than: currentVersion) else {
      return nil
    }

    return UpdateCheckResult(
      latestVersion: cachedVersion,
      downloadURL: downloadURL ?? ""
    )
  }

  /// キャッシュを更新する。
  @MainActor
  private func updateCache(latestVersion: String, downloadURL: String? = nil) {
    settingsManager.settings.updateCache = UpdateCache(
      latestVersion: latestVersion,
      checkedAt: Date(),
      dismissedVersion: settingsManager.settings.updateCache?.dismissedVersion,
      downloadURL: downloadURL
    )
    // 保存エラーは黙殺
    try? settingsManager.save()
  }

  /// バージョン文字列から "v" プレフィックスを除去する。
  private func stripVPrefix(_ version: String) -> String {
    if version.hasPrefix("v") || version.hasPrefix("V") {
      return String(version.dropFirst())
    }
    return version
  }
}
