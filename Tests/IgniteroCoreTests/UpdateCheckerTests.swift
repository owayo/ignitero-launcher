import Foundation
import Testing

@testable import IgniteroCore

// MARK: - URLSession モック

private final class MockURLSession: URLSessionProtocol, @unchecked Sendable {
  var dataToReturn: Data?
  var responseToReturn: URLResponse?
  var errorToThrow: Error?
  var requestedURL: URL?
  var delaySeconds: TimeInterval = 0

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    requestedURL = request.url

    if delaySeconds > 0 {
      try await Task.sleep(for: .seconds(delaySeconds))
    }

    if let error = errorToThrow {
      throw error
    }

    let data = dataToReturn ?? Data()
    let response =
      responseToReturn
      ?? HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    return (data, response)
  }
}

// MARK: - ヘルパー関数

private func makeReleasesJSON(_ releases: [[String: Any]]) -> Data {
  try! JSONSerialization.data(withJSONObject: releases)
}

private func makeRelease(
  tagName: String, prerelease: Bool = false, htmlURL: String = "https://github.com/test/releases"
) -> [String: Any] {
  [
    "tag_name": tagName,
    "prerelease": prerelease,
    "html_url": htmlURL,
  ]
}

private func makeTempConfigDir() -> URL {
  FileManager.default.temporaryDirectory
    .appendingPathComponent("ignitero-update-test-\(UUID().uuidString)")
}

// MARK: - GitHubRelease モデルテスト

@Suite("GitHubRelease Model")
struct GitHubReleaseModelTests {

  @Test func decodesFromJSON() throws {
    let json = """
      {
        "tag_name": "v1.2.3",
        "prerelease": false,
        "html_url": "https://github.com/test/releases/tag/v1.2.3"
      }
      """
    let data = json.data(using: .utf8)!
    let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

    #expect(release.tagName == "v1.2.3")
    #expect(release.prerelease == false)
    #expect(release.htmlURL == "https://github.com/test/releases/tag/v1.2.3")
  }

  @Test func decodesPrerelease() throws {
    let json = """
      {
        "tag_name": "v2.0.0-beta.1",
        "prerelease": true,
        "html_url": "https://github.com/test/releases/tag/v2.0.0-beta.1"
      }
      """
    let data = json.data(using: .utf8)!
    let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

    #expect(release.tagName == "v2.0.0-beta.1")
    #expect(release.prerelease == true)
  }
}

// MARK: - UpdateCheckResult テスト

@Suite("UpdateCheckResult Model")
struct UpdateCheckResultModelTests {

  @Test func hasVersionAndURL() {
    let result = UpdateCheckResult(
      latestVersion: "2.0.0",
      downloadURL: "https://github.com/test/releases/tag/v2.0.0"
    )
    #expect(result.latestVersion == "2.0.0")
    #expect(result.downloadURL == "https://github.com/test/releases/tag/v2.0.0")
  }
}

// MARK: - バージョン比較テスト

@Suite("Version Comparison")
struct VersionComparisonTests {

  @Test func newerVersionIsGreater() {
    #expect(VersionComparator.isNewer("2.0.0", than: "1.0.0") == true)
  }

  @Test func sameVersionIsNotGreater() {
    #expect(VersionComparator.isNewer("1.0.0", than: "1.0.0") == false)
  }

  @Test func olderVersionIsNotGreater() {
    #expect(VersionComparator.isNewer("1.0.0", than: "2.0.0") == false)
  }

  @Test func newerMinorVersion() {
    #expect(VersionComparator.isNewer("1.2.0", than: "1.1.0") == true)
  }

  @Test func newerPatchVersion() {
    #expect(VersionComparator.isNewer("1.0.2", than: "1.0.1") == true)
  }

  @Test func handlesVPrefix() {
    #expect(VersionComparator.isNewer("v2.0.0", than: "1.0.0") == true)
    #expect(VersionComparator.isNewer("2.0.0", than: "v1.0.0") == true)
    #expect(VersionComparator.isNewer("v2.0.0", than: "v1.0.0") == true)
  }

  @Test func handlesDifferentLengths() {
    #expect(VersionComparator.isNewer("1.0.0.1", than: "1.0.0") == true)
    #expect(VersionComparator.isNewer("1.0.0", than: "1.0.0.1") == false)
  }

  @Test func handlesMultiDigitVersions() {
    #expect(VersionComparator.isNewer("27.0.0", than: "26.1.105") == true)
    #expect(VersionComparator.isNewer("26.1.105", than: "27.0.0") == false)
  }
}

// MARK: - UpdateChecker 新バージョン検出テスト

@Suite("UpdateChecker New Version Detection")
struct UpdateCheckerNewVersionTests {

  @Test func detectsNewVersion() async {
    let mockSession = MockURLSession()
    mockSession.dataToReturn = makeReleasesJSON([
      makeRelease(
        tagName: "v99.0.0",
        htmlURL: "https://github.com/test/releases/tag/v99.0.0"
      )
    ])

    let settingsManager = SettingsManager(configDirectory: makeTempConfigDir())
    let checker = UpdateChecker(
      session: mockSession,
      settingsManager: settingsManager,
      owner: "test",
      repo: "test-repo"
    )

    let result = await checker.checkForUpdate(currentVersion: "1.0.0")

    #expect(result != nil)
    #expect(result?.latestVersion == "99.0.0")
    #expect(result?.downloadURL == "https://github.com/test/releases/tag/v99.0.0")
  }

  @Test func returnsNilForOlderVersion() async {
    let mockSession = MockURLSession()
    mockSession.dataToReturn = makeReleasesJSON([
      makeRelease(tagName: "v0.1.0")
    ])

    let settingsManager = SettingsManager(configDirectory: makeTempConfigDir())
    let checker = UpdateChecker(
      session: mockSession,
      settingsManager: settingsManager,
      owner: "test",
      repo: "test-repo"
    )

    let result = await checker.checkForUpdate(currentVersion: "1.0.0")
    #expect(result == nil)
  }

  @Test func returnsNilForSameVersion() async {
    let mockSession = MockURLSession()
    mockSession.dataToReturn = makeReleasesJSON([
      makeRelease(tagName: "v1.0.0")
    ])

    let settingsManager = SettingsManager(configDirectory: makeTempConfigDir())
    let checker = UpdateChecker(
      session: mockSession,
      settingsManager: settingsManager,
      owner: "test",
      repo: "test-repo"
    )

    let result = await checker.checkForUpdate(currentVersion: "1.0.0")
    #expect(result == nil)
  }
}

// MARK: - UpdateChecker プレリリース除外テスト

@Suite("UpdateChecker Prerelease Filtering")
struct UpdateCheckerPrereleaseTests {

  @Test func skipsPrereleaseVersions() async {
    let mockSession = MockURLSession()
    mockSession.dataToReturn = makeReleasesJSON([
      makeRelease(tagName: "v99.0.0-beta.1", prerelease: true),
      makeRelease(tagName: "v99.0.0-rc.1", prerelease: true),
    ])

    let settingsManager = SettingsManager(configDirectory: makeTempConfigDir())
    let checker = UpdateChecker(
      session: mockSession,
      settingsManager: settingsManager,
      owner: "test",
      repo: "test-repo"
    )

    let result = await checker.checkForUpdate(currentVersion: "1.0.0")
    #expect(result == nil)
  }

  @Test func selectsStableOverPrerelease() async {
    let mockSession = MockURLSession()
    mockSession.dataToReturn = makeReleasesJSON([
      makeRelease(tagName: "v3.0.0-beta.1", prerelease: true),
      makeRelease(tagName: "v2.0.0", prerelease: false),
    ])

    let settingsManager = SettingsManager(configDirectory: makeTempConfigDir())
    let checker = UpdateChecker(
      session: mockSession,
      settingsManager: settingsManager,
      owner: "test",
      repo: "test-repo"
    )

    let result = await checker.checkForUpdate(currentVersion: "1.0.0")
    #expect(result != nil)
    #expect(result?.latestVersion == "2.0.0")
  }
}

// MARK: - UpdateChecker キャッシュテスト

@Suite("UpdateChecker Cache")
struct UpdateCheckerCacheTests {

  @Test func usesCachedResultWithin12Hours() async {
    let mockSession = MockURLSession()
    // API が呼ばれたら検出できるようにする
    mockSession.dataToReturn = makeReleasesJSON([
      makeRelease(tagName: "v99.0.0")
    ])

    let settingsManager = SettingsManager(configDirectory: makeTempConfigDir())
    // キャッシュを設定（6時間前にチェック済み）
    settingsManager.settings.updateCache = UpdateCache(
      latestVersion: "2.0.0",
      checkedAt: Date().addingTimeInterval(-6 * 3600)  // 6時間前
    )

    let checker = UpdateChecker(
      session: mockSession,
      settingsManager: settingsManager,
      owner: "test",
      repo: "test-repo"
    )

    let result = await checker.checkForUpdate(currentVersion: "1.0.0")

    // キャッシュから結果を返す
    #expect(result != nil)
    #expect(result?.latestVersion == "2.0.0")
    // API は呼ばれない
    #expect(mockSession.requestedURL == nil)
  }

  @Test func fetchesNewDataAfter12Hours() async {
    let mockSession = MockURLSession()
    mockSession.dataToReturn = makeReleasesJSON([
      makeRelease(
        tagName: "v3.0.0",
        htmlURL: "https://github.com/test/releases/tag/v3.0.0"
      )
    ])

    let settingsManager = SettingsManager(configDirectory: makeTempConfigDir())
    // キャッシュを設定（13時間前にチェック済み）
    settingsManager.settings.updateCache = UpdateCache(
      latestVersion: "2.0.0",
      checkedAt: Date().addingTimeInterval(-13 * 3600)  // 13時間前
    )

    let checker = UpdateChecker(
      session: mockSession,
      settingsManager: settingsManager,
      owner: "test",
      repo: "test-repo"
    )

    let result = await checker.checkForUpdate(currentVersion: "1.0.0")

    // 新しいデータを取得
    #expect(result != nil)
    #expect(result?.latestVersion == "3.0.0")
    // API が呼ばれた
    #expect(mockSession.requestedURL != nil)
  }

  @Test func cachedOlderVersionReturnsNil() async {
    let mockSession = MockURLSession()

    let settingsManager = SettingsManager(configDirectory: makeTempConfigDir())
    // キャッシュにあるバージョンが現在のバージョンより古い
    settingsManager.settings.updateCache = UpdateCache(
      latestVersion: "0.9.0",
      checkedAt: Date().addingTimeInterval(-1 * 3600)  // 1時間前
    )

    let checker = UpdateChecker(
      session: mockSession,
      settingsManager: settingsManager,
      owner: "test",
      repo: "test-repo"
    )

    let result = await checker.checkForUpdate(currentVersion: "1.0.0")
    #expect(result == nil)
  }

  @Test func noCacheTriggersAPICall() async {
    let mockSession = MockURLSession()
    mockSession.dataToReturn = makeReleasesJSON([
      makeRelease(tagName: "v2.0.0")
    ])

    let settingsManager = SettingsManager(configDirectory: makeTempConfigDir())
    // キャッシュなし

    let checker = UpdateChecker(
      session: mockSession,
      settingsManager: settingsManager,
      owner: "test",
      repo: "test-repo"
    )

    _ = await checker.checkForUpdate(currentVersion: "1.0.0")
    #expect(mockSession.requestedURL != nil)
  }
}

// MARK: - UpdateChecker 非表示バージョンテスト

@Suite("UpdateChecker Dismissed Version")
struct UpdateCheckerDismissedVersionTests {

  @Test func suppressesNotificationForDismissedVersion() async {
    let mockSession = MockURLSession()
    mockSession.dataToReturn = makeReleasesJSON([
      makeRelease(tagName: "v2.0.0")
    ])

    let settingsManager = SettingsManager(configDirectory: makeTempConfigDir())
    // ユーザーが v2.0.0 を非表示にしている
    settingsManager.settings.updateCache = UpdateCache(
      dismissedVersion: "2.0.0"
    )

    let checker = UpdateChecker(
      session: mockSession,
      settingsManager: settingsManager,
      owner: "test",
      repo: "test-repo"
    )

    let result = await checker.checkForUpdate(currentVersion: "1.0.0")
    #expect(result == nil)
  }

  @Test func showsNotificationForDifferentVersionThanDismissed() async {
    let mockSession = MockURLSession()
    mockSession.dataToReturn = makeReleasesJSON([
      makeRelease(
        tagName: "v3.0.0",
        htmlURL: "https://github.com/test/releases/tag/v3.0.0"
      )
    ])

    let settingsManager = SettingsManager(configDirectory: makeTempConfigDir())
    // ユーザーが v2.0.0 を非表示にしているが、最新は v3.0.0
    settingsManager.settings.updateCache = UpdateCache(
      dismissedVersion: "2.0.0"
    )

    let checker = UpdateChecker(
      session: mockSession,
      settingsManager: settingsManager,
      owner: "test",
      repo: "test-repo"
    )

    let result = await checker.checkForUpdate(currentVersion: "1.0.0")
    #expect(result != nil)
    #expect(result?.latestVersion == "3.0.0")
  }
}

// MARK: - UpdateChecker エラーハンドリングテスト

@Suite("UpdateChecker Error Handling")
struct UpdateCheckerErrorHandlingTests {

  @Test func returnsNilOnNetworkError() async {
    let mockSession = MockURLSession()
    mockSession.errorToThrow = URLError(.notConnectedToInternet)

    let settingsManager = SettingsManager(configDirectory: makeTempConfigDir())
    let checker = UpdateChecker(
      session: mockSession,
      settingsManager: settingsManager,
      owner: "test",
      repo: "test-repo"
    )

    let result = await checker.checkForUpdate(currentVersion: "1.0.0")
    #expect(result == nil)
  }

  @Test func returnsNilOnInvalidJSON() async {
    let mockSession = MockURLSession()
    mockSession.dataToReturn = "invalid json".data(using: .utf8)

    let settingsManager = SettingsManager(configDirectory: makeTempConfigDir())
    let checker = UpdateChecker(
      session: mockSession,
      settingsManager: settingsManager,
      owner: "test",
      repo: "test-repo"
    )

    let result = await checker.checkForUpdate(currentVersion: "1.0.0")
    #expect(result == nil)
  }

  @Test func returnsNilOnEmptyReleases() async {
    let mockSession = MockURLSession()
    mockSession.dataToReturn = makeReleasesJSON([])

    let settingsManager = SettingsManager(configDirectory: makeTempConfigDir())
    let checker = UpdateChecker(
      session: mockSession,
      settingsManager: settingsManager,
      owner: "test",
      repo: "test-repo"
    )

    let result = await checker.checkForUpdate(currentVersion: "1.0.0")
    #expect(result == nil)
  }

  @Test func returnsNilOnTimeout() async {
    let mockSession = MockURLSession()
    mockSession.errorToThrow = URLError(.timedOut)

    let settingsManager = SettingsManager(configDirectory: makeTempConfigDir())
    let checker = UpdateChecker(
      session: mockSession,
      settingsManager: settingsManager,
      owner: "test",
      repo: "test-repo"
    )

    let result = await checker.checkForUpdate(currentVersion: "1.0.0")
    #expect(result == nil)
  }

  @Test func usesCachedValueOnNetworkError() async {
    let mockSession = MockURLSession()
    mockSession.errorToThrow = URLError(.notConnectedToInternet)

    let settingsManager = SettingsManager(configDirectory: makeTempConfigDir())
    // 期限切れのキャッシュがあるが、ネットワークエラー時はキャッシュを使用
    settingsManager.settings.updateCache = UpdateCache(
      latestVersion: "2.0.0",
      checkedAt: Date().addingTimeInterval(-24 * 3600)  // 24時間前（期限切れ）
    )

    let checker = UpdateChecker(
      session: mockSession,
      settingsManager: settingsManager,
      owner: "test",
      repo: "test-repo"
    )

    let result = await checker.checkForUpdate(currentVersion: "1.0.0")
    // ネットワークエラー時はキャッシュ値を返す
    #expect(result != nil)
    #expect(result?.latestVersion == "2.0.0")
  }
}

// MARK: - UpdateChecker API URL テスト

@Suite("UpdateChecker API URL")
struct UpdateCheckerAPIURLTests {

  @Test func usesCorrectGitHubAPIURL() async {
    let mockSession = MockURLSession()
    mockSession.dataToReturn = makeReleasesJSON([])

    let settingsManager = SettingsManager(configDirectory: makeTempConfigDir())
    let checker = UpdateChecker(
      session: mockSession,
      settingsManager: settingsManager,
      owner: "myorg",
      repo: "myrepo"
    )

    _ = await checker.checkForUpdate(currentVersion: "1.0.0")

    #expect(
      mockSession.requestedURL?.absoluteString
        == "https://api.github.com/repos/myorg/myrepo/releases")
  }

  @Test func usesProductionRepositoryDefaults() async {
    let mockSession = MockURLSession()
    mockSession.dataToReturn = makeReleasesJSON([])

    let settingsManager = SettingsManager(configDirectory: makeTempConfigDir())
    let checker = UpdateChecker(
      session: mockSession,
      settingsManager: settingsManager
    )

    _ = await checker.checkForUpdate(currentVersion: "1.0.0")

    #expect(
      mockSession.requestedURL?.absoluteString
        == "https://api.github.com/repos/owayo/ignitero-launcher/releases")
  }
}

// MARK: - UpdateChecker キャッシュ更新テスト

@Suite("UpdateChecker Cache Update")
struct UpdateCheckerCacheUpdateTests {

  @Test func updatesCacheAfterSuccessfulFetch() async {
    let mockSession = MockURLSession()
    mockSession.dataToReturn = makeReleasesJSON([
      makeRelease(tagName: "v5.0.0")
    ])

    let settingsManager = SettingsManager(configDirectory: makeTempConfigDir())
    let checker = UpdateChecker(
      session: mockSession,
      settingsManager: settingsManager,
      owner: "test",
      repo: "test-repo"
    )

    _ = await checker.checkForUpdate(currentVersion: "1.0.0")

    // キャッシュが更新されている
    #expect(settingsManager.settings.updateCache?.latestVersion == "5.0.0")
    #expect(settingsManager.settings.updateCache?.checkedAt != nil)
  }
}
