import AppKit
import Testing

@testable import IgniteroCore

@Test @MainActor func appDelegateConformsToNSApplicationDelegate() {
  let delegate = AppDelegate()
  let asDelegate = delegate as NSApplicationDelegate
  #expect(asDelegate is AppDelegate)
}

@Test @MainActor func appDelegateTargetActivationPolicy() {
  // AppDelegate は .accessory ポリシーを使用する設計
  // (Dock アイコン非表示)
  #expect(AppDelegate.targetActivationPolicy == .accessory)
}
