import Carbon.HIToolbox
import Dispatch
import Foundation
import os

public protocol IMEControlling: Sendable {
  func switchToASCII()
}

public struct IMEController: IMEControlling, Sendable {
  private static let logger = Logger(subsystem: "com.ignitero.launcher", category: "IME")

  public init() {}

  public func switchToASCII() {
    // TIS/TSM API はメインスレッドで直列実行しないと abort することがある。
    if Thread.isMainThread {
      Self.selectASCIIInputSource()
    } else {
      DispatchQueue.main.sync {
        Self.selectASCIIInputSource()
      }
    }
  }

  private static func selectASCIIInputSource() {
    guard let source = TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue() else {
      logger.error("Failed to get ASCII input source")
      return
    }
    let status = TISSelectInputSource(source)
    if status != noErr {
      logger.error("Failed to select input source: \(status)")
    }
  }
}
