import AppKit
import IgniteroCore
import SwiftUI

/// アプリケーション全体で共有する AppCoordinator。
@MainActor
let sharedCoordinator = AppCoordinator()

// MARK: - AppDelegate

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

// MARK: - App

@main
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

// MARK: - MenuBarLabel

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
