import AppKit
import Foundation
import os

// MARK: - MenuBarItem

/// メニューバーの各メニュー項目を表す構造体。
public struct MenuBarItem: Sendable, Identifiable {
  public let id: String
  public let title: String
  public let action: @MainActor @Sendable () -> Void

  public init(id: String, title: String, action: @MainActor @Sendable @escaping () -> Void) {
    self.id = id
    self.title = title
    self.action = action
  }
}

// MARK: - MenuBarActions

/// メニューバーのコンテキストメニュー操作を管理するクラス。
///
/// `MenuBarExtra` のクリック時に表示されるメニュー項目のアクションを提供する。
/// - ウィンドウを表示
/// - キャッシュを再構築
/// - 設定
/// - 終了
@MainActor
@Observable
public final class MenuBarActions {

  private static let logger = Logger(
    subsystem: "com.ignitero.launcher", category: "MenuBarActions")

  // MARK: - Dependencies

  /// ランチャーウィンドウの表示制御
  public let windowManager: WindowManager

  /// 設定の永続化管理
  public let settingsManager: SettingsManager

  /// アプリケーションスキャナー
  private let appScanner: any AppScannerProtocol

  /// ディレクトリスキャナー
  private let directoryScanner: any DirectoryScannerProtocol

  // MARK: - State

  /// キャッシュ再構築中かどうか
  public private(set) var isRebuildingCache: Bool = false

  /// 設定ウィンドウが開いているかどうか
  public var isSettingsOpen: Bool = false

  // MARK: - Initialization

  /// MenuBarActions を初期化する。
  ///
  /// - Parameters:
  ///   - windowManager: ランチャーウィンドウの表示制御
  ///   - settingsManager: 設定の永続化管理
  ///   - appScanner: アプリケーションスキャナー
  ///   - directoryScanner: ディレクトリスキャナー
  public init(
    windowManager: WindowManager,
    settingsManager: SettingsManager,
    appScanner: any AppScannerProtocol,
    directoryScanner: any DirectoryScannerProtocol
  ) {
    self.windowManager = windowManager
    self.settingsManager = settingsManager
    self.appScanner = appScanner
    self.directoryScanner = directoryScanner
  }

  // MARK: - Menu Items

  /// メニュー項目の一覧を返す。
  public var menuItems: [MenuBarItem] {
    [
      MenuBarItem(id: "show-window", title: "ウィンドウを表示") { [weak self] in
        self?.showWindow()
      },
      MenuBarItem(
        id: "rebuild-cache",
        title: isRebuildingCache ? "キャッシュを再構築中..." : "キャッシュを再構築"
      ) { [weak self] in
        guard let self else { return }
        Task { @MainActor in
          await self.rebuildCache()
        }
      },
      MenuBarItem(id: "settings", title: "設定") { [weak self] in
        self?.openSettings()
      },
      MenuBarItem(id: "quit", title: "終了") { [weak self] in
        self?.quit()
      },
    ]
  }

  // MARK: - Actions

  /// ランチャーウィンドウを表示する。
  public func showWindow() {
    windowManager.showLauncher()
  }

  /// キャッシュを再構築する。
  ///
  /// バックグラウンドタスクとしてアプリスキャンとディレクトリスキャンを再実行する。
  /// スキャン中は `isRebuildingCache` が `true` になる。
  /// エラーが発生しても `isRebuildingCache` は `false` に戻る。
  public func rebuildCache() async {
    isRebuildingCache = true
    defer { isRebuildingCache = false }

    Self.logger.info("Starting cache rebuild")

    // アプリスキャン
    do {
      let excludedApps = settingsManager.settings.excludedApps
      let apps = try appScanner.scanApplications(excludedApps: excludedApps)
      Self.logger.info("App scan completed: \(apps.count) apps found")
    } catch {
      Self.logger.error("App scan failed: \(error.localizedDescription)")
    }

    // ディレクトリスキャン
    do {
      let directories = settingsManager.settings.registeredDirectories
      let result = try directoryScanner.scan(directories: directories)
      Self.logger.info(
        "Directory scan completed: \(result.directories.count) directories, \(result.apps.count) apps"
      )
    } catch {
      Self.logger.error("Directory scan failed: \(error.localizedDescription)")
    }

    Self.logger.info("Cache rebuild completed")
  }

  /// 設定ウィンドウを開く。
  public func openSettings() {
    isSettingsOpen = true
  }

  /// 設定ウィンドウを閉じる。
  public func closeSettings() {
    isSettingsOpen = false
  }

  /// アプリケーションを終了する。
  public func quit() {
    NSApplication.shared.terminate(nil)
  }
}
