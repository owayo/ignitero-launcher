import AppKit

/// テスト用の AppDelegate プロトコル。
/// 実際の AppDelegate は IgniteroLauncher ターゲットで定義する。
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
  public static let targetActivationPolicy: NSApplication.ActivationPolicy = .accessory

  public func applicationDidFinishLaunching(_ notification: Notification) {
    NSApplication.shared.setActivationPolicy(Self.targetActivationPolicy)
  }
}
