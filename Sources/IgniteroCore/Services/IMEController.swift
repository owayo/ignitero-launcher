import Carbon.HIToolbox
import os

public protocol IMEControlling: Sendable {
  func switchToASCII()
}

public struct IMEController: IMEControlling, Sendable {
  private static let logger = Logger(subsystem: "com.ignitero.launcher", category: "IME")

  public init() {}

  public func switchToASCII() {
    guard let source = TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue() else {
      Self.logger.error("Failed to get ASCII input source")
      return
    }
    let status = TISSelectInputSource(source)
    if status != noErr {
      Self.logger.error("Failed to select input source: \(status)")
    }
  }
}
