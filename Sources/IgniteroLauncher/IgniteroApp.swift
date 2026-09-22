import AppKit
import IgniteroCore
import SwiftUI

/// アプリケーション全体で共有する AppCoordinator。
@MainActor
let sharedCoordinator = AppCoordinator()

// MARK: - AppDelegate関連

@MainActor
final class IgniteroAppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApplication.shared.setActivationPolicy(.accessory)
    Task { @MainActor in
      await sharedCoordinator.start()
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    sharedCoordinator.shutdown()
  }
}

// MARK: - エントリポイント

/// `--self-test-resources` 付きで起動された場合はリソース解決の自己診断だけを実行して
/// 終了コードで結果を返す（`make smoke-resources` が `.app` に対して実行する）。
/// `--print-version` はバンドルの `Info.plist` と実行時の自己申告値が一致するかを
/// `make verify-bundle` が検証するための診断。
/// いずれも GUI を起動しないため `sharedCoordinator` は初期化されない。
@main
enum IgniteroLauncherMain {
  @MainActor
  static func main() {
    if CommandLine.arguments.contains("--self-test-resources") {
      exit(ResourceSelfTest.run() ? EXIT_SUCCESS : EXIT_FAILURE)
    }
    if CommandLine.arguments.contains("--print-version") {
      guard let version = Ignitero.version else {
        FileHandle.standardError.write(
          Data("error: アプリケーションバージョンを取得できない\n".utf8))
        exit(EXIT_FAILURE)
      }
      print(version)
      exit(EXIT_SUCCESS)
    }
    IgniteroApp.main()
  }
}

// MARK: - アプリ

struct IgniteroApp: App {
  @NSApplicationDelegateAdaptor(IgniteroAppDelegate.self) var appDelegate
  @Environment(\.openWindow) private var openWindow

  var body: some Scene {
    MenuBarExtra {
      Button("ウィンドウを表示") {
        sharedCoordinator.menuBarActions.showWindow()
      }
      .keyboardShortcut("o")

      Button("キャッシュを再構築") {
        Task {
          await sharedCoordinator.rebuildCacheAndReload()
        }
      }

      Divider()

      Button("設定...") {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "settings")
      }
      .keyboardShortcut(",")

      Divider()

      Button("終了") {
        NSApplication.shared.terminate(nil)
      }
      .keyboardShortcut("q")
    } label: {
      MenuBarLabel()
        .onChange(of: sharedCoordinator.menuBarActions.isSettingsOpen) { _, isOpen in
          if isOpen {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "settings")
            sharedCoordinator.menuBarActions.isSettingsOpen = false
          }
        }
    }

    Window("設定 - Ignitero", id: "settings") {
      SettingsView(viewModel: sharedCoordinator.settingsViewModel)
    }
    .defaultSize(width: 520, height: 400)
  }

  fileprivate static func loadMenuBarIcon() -> NSImage? {
    guard let bundlePath = Bundle.main.resourcePath else { return nil }
    let url2x = URL(fileURLWithPath: bundlePath).appendingPathComponent("MenuBarIcon@2x.png")
    let url1x = URL(fileURLWithPath: bundlePath).appendingPathComponent("MenuBarIcon.png")
    let url = FileManager.default.fileExists(atPath: url2x.path) ? url2x : url1x
    guard let image = NSImage(contentsOf: url) else { return nil }
    image.size = NSSize(width: 18, height: 18)
    image.isTemplate = false
    return image
  }
}

// MARK: - メニューバー表示

/// メニューバーアイコン。起動処理完了までローディングアニメーションを表示する。
private struct MenuBarLabel: View {
  private var isLoading: Bool {
    !sharedCoordinator.isReady || sharedCoordinator.cacheBootstrap.isScanning
  }

  var body: some View {
    if isLoading {
      Image(systemName: "arrow.trianglehead.2.counterclockwise")
        .symbolEffect(.rotate, isActive: true)
    } else if let icon = IgniteroApp.loadMenuBarIcon() {
      Image(nsImage: icon)
    } else {
      Image(systemName: "magnifyingglass")
    }
  }
}
