import Foundation
import Testing

@testable import IgniteroCore

// MARK: - HapticService テスト

@Suite("HapticService")
struct HapticServiceTests {

  @Test("selectionChanged がクラッシュせずに呼び出せる")
  func selectionChangedDoesNotCrash() {
    HapticService.selectionChanged()
  }

  @Test("confirmed がクラッシュせずに呼び出せる")
  func confirmedDoesNotCrash() {
    HapticService.confirmed()
  }

  @Test("連続呼び出しでクラッシュしない")
  func rapidConsecutiveCallsDoNotCrash() {
    for _ in 0..<100 {
      HapticService.selectionChanged()
    }
    for _ in 0..<100 {
      HapticService.confirmed()
    }
  }

  @Test("交互呼び出しでクラッシュしない")
  func alternatingCallsDoNotCrash() {
    for _ in 0..<50 {
      HapticService.selectionChanged()
      HapticService.confirmed()
    }
  }
}
