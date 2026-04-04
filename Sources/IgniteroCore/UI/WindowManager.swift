import AppKit
import Foundation

/// ランチャーウィンドウの表示/非表示、位置管理、リサイズを統括するマネージャ。
///
/// `@MainActor` でスレッド安全性を保証し、`@Observable` で SwiftUI バインディングに対応。
/// ウィンドウ位置は `UserDefaults` で永続化し、起動時に復元する。
@MainActor
@Observable
public final class WindowManager {

  // MARK: - Constants

  /// 検索バーのみ表示時の最小ウィンドウ高さ (px)
  ///
  /// searchField(68pt) + タイトルバー(.titled + .fullSizeContentView)
  public static let minHeight: CGFloat = 108

  /// 検索結果表示時の最大ウィンドウ高さ (px)
  public static let maxHeight: CGFloat = 500

  /// 検索結果 1 行あたりの高さ (px)
  ///
  /// 行コンテンツ: 名前(17pt) + spacing(2) + サブタイトル(12pt) + padding(6×2) = ~43pt
  /// 選択時やエディタ行ありではさらに高くなるため、余裕を持たせる。
  public static let rowHeight: CGFloat = 52

  /// ランチャーウィンドウの幅 (px)
  public static let width: CGFloat = 680

  // MARK: - UserDefaults Keys

  private enum DefaultsKey {
    static let positionX = "ignitero.launcher.position.x"
    static let positionY = "ignitero.launcher.position.y"
    static let positionSaved = "ignitero.launcher.position.saved"
  }

  // MARK: - Published State

  /// ランチャーウィンドウが表示中かどうか
  public private(set) var isLauncherVisible: Bool = false

  /// エディタ/ターミナルピッカーが表示中かどうか
  public private(set) var isPickerVisible: Bool = false

  /// 現在のウィンドウ高さ
  public private(set) var currentHeight: CGFloat = WindowManager.minHeight

  /// ランチャーパネルへの参照
  public var launcherPanel: NSPanel?

  /// モニター経由でランチャーが自動非表示になった際のコールバック。
  public var onAutoDismiss: (() -> Void)?

  /// ランチャー表示直前のコールバック（検索クリアなど）。
  public var onShowLauncher: (() -> Void)?

  /// ランチャーパネルのキーダウンイベントハンドラ。
  /// `true` を返すとイベントを消費する。
  public var onKeyEvent: ((NSEvent) -> Bool)?

  /// ピッカー表示中にショートカットが押された際のコールバック。
  /// ピッカーを閉じるために AppCoordinator から設定される。
  public var onCloseAllPickers: (() -> Void)?

  // MARK: - Private

  private let userDefaults: UserDefaults

  /// クリック外イベント監視トークン
  private var clickMonitor: Any?

  /// アプリ切り替え通知監視トークン
  private var appSwitchObserver: (any NSObjectProtocol)?

  /// キーダウンイベントのローカルモニター
  private var keyEventMonitor: Any?

  // MARK: - Initialization

  /// WindowManager を初期化する。
  ///
  /// - Parameter userDefaults: 位置永続化に使用する UserDefaults。テスト時に差し替え可能。
  public init(userDefaults: UserDefaults = .standard) {
    self.userDefaults = userDefaults
  }

  // MARK: - Launcher Visibility

  /// ランチャーの表示/非表示をトグルする。
  ///
  /// ピッカー表示中の場合はピッカーを閉じてランチャーを表示する。
  public func toggleLauncher() {
    if isPickerVisible {
      // ピッカーが開いている → 閉じてランチャーを表示
      onCloseAllPickers?()
      isPickerVisible = false
      showLauncher()
    } else if isLauncherVisible {
      hideLauncher()
    } else {
      showLauncher()
    }
  }

  /// ランチャーを表示し、カーソルがあるスクリーンの中央最前面に配置する。
  public func showLauncher() {
    onShowLauncher?()
    isLauncherVisible = true
    centerOnScreen()
    launcherPanel?.makeKeyAndOrderFront(nil)
    startDismissMonitors()
    startKeyEventMonitor()
  }

  // MARK: - Screen Centering

  /// カーソルがあるスクリーンの上部寄りにパネルを配置する。
  private func centerOnScreen() {
    guard let panel = launcherPanel else { return }

    let mouseNS = NSEvent.mouseLocation
    let screen =
      NSScreen.screens.first { NSMouseInRect(mouseNS, $0.frame, false) }
      ?? NSScreen.main
    guard let screen else { return }

    let vis = screen.visibleFrame
    let x = vis.midX - panel.frame.width / 2
    // 画面上端から約 1/4 の位置に配置（Spotlight 風）
    let y = vis.maxY - vis.height * 0.25 - panel.frame.height / 2
    panel.setFrameOrigin(NSPoint(x: x, y: y))
  }

  /// ランチャーを非表示にする。
  public func hideLauncher() {
    isLauncherVisible = false
    stopKeyEventMonitor()
    stopDismissMonitors()
    launcherPanel?.orderOut(nil)
  }

  /// パネルが外部要因（クリック外・アプリ切り替え）で非表示になった際に状態を同期する。
  public func syncHiddenState() {
    guard isLauncherVisible else { return }
    isLauncherVisible = false
    stopKeyEventMonitor()
    stopDismissMonitors()
  }

  // MARK: - Dismiss Monitors

  /// ランチャー外のクリックとアプリ切り替えを監視し、自動非表示を行う。
  private func startDismissMonitors() {
    stopDismissMonitors()

    // アプリ外（デスクトップ・他ウィンドウ）のクリックを検知
    // addGlobalMonitorForEvents のコールバックはメインスレッド保証がないため、
    // Task で MainActor にディスパッチする（assumeIsolated はデータレースの原因になる）。
    clickMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown]
    ) { [weak self] _ in
      Task { @MainActor in
        self?.autoDismiss()
      }
    }

    // Cmd+Tab 等で他アプリがアクティブになったことを検知
    appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
          as? NSRunningApplication,
        app.bundleIdentifier != Bundle.main.bundleIdentifier
      else { return }
      MainActor.assumeIsolated {
        self?.autoDismiss()
      }
    }
  }

  /// モニター検知による自動非表示。
  private func autoDismiss() {
    guard isLauncherVisible else { return }
    onAutoDismiss?()
    hideLauncher()
  }

  // MARK: - Key Event Monitor

  /// ランチャーパネル向けのローカルキーイベントモニターを開始する。
  private func startKeyEventMonitor() {
    stopKeyEventMonitor()
    keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
      [weak self] event in
      guard let self else { return event }
      // ランチャーパネルのイベントのみ処理
      guard event.window === self.launcherPanel else { return event }
      if let handler = self.onKeyEvent, handler(event) {
        return nil  // イベント消費
      }
      return event  // TextField 等に通常通り渡す
    }
  }

  /// キーイベントモニターを停止する。
  private func stopKeyEventMonitor() {
    if let monitor = keyEventMonitor {
      NSEvent.removeMonitor(monitor)
      keyEventMonitor = nil
    }
  }

  /// 自動非表示監視を停止する。
  private func stopDismissMonitors() {
    if let monitor = clickMonitor {
      NSEvent.removeMonitor(monitor)
      clickMonitor = nil
    }
    if let observer = appSwitchObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
      appSwitchObserver = nil
    }
  }

  // MARK: - Picker Visibility

  /// ピッカー表示中フラグをセットする。
  public func showPicker() {
    isPickerVisible = true
  }

  /// ピッカー表示中フラグをクリアする。
  public func hidePicker() {
    isPickerVisible = false
  }

  // MARK: - Window Resize

  /// 検索結果の件数に応じた適切なウィンドウ高さを計算する。
  ///
  /// - Parameter count: 検索結果の件数
  /// - Returns: 計算されたウィンドウ高さ。`minHeight` 以上 `maxHeight` 以下。
  public func heightForResults(count: Int) -> CGFloat {
    let effectiveCount = max(0, count)
    let computed = Self.minHeight + CGFloat(effectiveCount) * Self.rowHeight
    return min(computed, Self.maxHeight)
  }

  /// 検索結果の件数に応じてウィンドウをリサイズする。
  ///
  /// パネルが設定されている場合、フレームを更新して即座に反映する。
  /// - Parameter count: 検索結果の件数
  public func resizeForResults(count: Int) {
    let newHeight = heightForResults(count: count)
    currentHeight = newHeight

    guard let panel = launcherPanel else { return }
    var frame = panel.frame
    let heightDelta = newHeight - frame.height
    frame.size.height = newHeight
    frame.origin.y -= heightDelta  // macOS は下端が原点のためリサイズ時に y を調整
    panel.setFrame(frame, display: true, animate: false)
  }

  // MARK: - Position Persistence

  /// 現在のウィンドウ位置を UserDefaults に保存する。
  public func savePosition(x: Double, y: Double) {
    userDefaults.set(x, forKey: DefaultsKey.positionX)
    userDefaults.set(y, forKey: DefaultsKey.positionY)
    userDefaults.set(true, forKey: DefaultsKey.positionSaved)
  }

  /// 保存されたウィンドウ位置を復元する。
  public func restorePosition() -> (x: Double, y: Double)? {
    guard userDefaults.bool(forKey: DefaultsKey.positionSaved) else {
      return nil
    }
    let x = userDefaults.double(forKey: DefaultsKey.positionX)
    let y = userDefaults.double(forKey: DefaultsKey.positionY)
    return (x: x, y: y)
  }

  /// パネルの現在位置を UserDefaults に保存する。
  public func savePanelPosition() {
    guard let panel = launcherPanel else { return }
    let origin = panel.frame.origin
    savePosition(x: Double(origin.x), y: Double(origin.y))
  }

  /// 保存された位置にパネルを復元する。
  public func restorePanelPosition() {
    guard let panel = launcherPanel,
      let position = restorePosition()
    else { return }
    var frame = panel.frame
    frame.origin = CGPoint(x: position.x, y: position.y)
    panel.setFrame(frame, display: false)
  }
}
