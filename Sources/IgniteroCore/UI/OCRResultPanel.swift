import AppKit
import SwiftUI

@MainActor
@Observable
public final class OCRBackendModel {
  public enum Phase { case recognizing, ready, failed }
  public var phase: Phase = .recognizing
  public var text = ""
  public var message = ""
  public var elapsedSeconds: Double?
  public init() {}

  public func reset() {
    phase = .recognizing
    text = ""
    message = ""
    elapsedSeconds = nil
  }
}

@MainActor
@Observable
public final class OCRResultModel {
  public enum Phase { case capturing, recognizing, ready, failed }
  public var phase: Phase = .capturing
  public let vision = OCRBackendModel()
  public let ocrus = OCRBackendModel()
  public var message = ""
  public var needsPermission = false
  public var image: NSImage?
  public init() {}
}

@MainActor
public final class OCRResultPanel: NSPanel, NSWindowDelegate {
  public var onDismiss: (() -> Void)?

  public init(model: OCRResultModel, onSelectAgain: @escaping () -> Void) {
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 920, height: 560),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: true)
    title = "画面の文字を読み取り"
    minSize = NSSize(width: 640, height: 400)
    isReleasedWhenClosed = false
    isFloatingPanel = true
    level = .floating
    delegate = self
    contentView = SafeHostingView.makeContainer(
      rootView: OCRResultView(
        model: model, onSelectAgain: onSelectAgain, onClose: { [weak self] in self?.close() }))
  }

  public override var canBecomeKey: Bool { true }
  public override func cancelOperation(_ sender: Any?) { close() }
  public func windowWillClose(_ notification: Notification) { onDismiss?() }

  public func present() {
    let screen =
      NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
    if let visible = screen?.visibleFrame {
      let size = CGSize(
        width: min(frame.width, visible.width - 32), height: min(frame.height, visible.height - 32))
      setFrame(
        CGRect(
          x: visible.midX - size.width / 2, y: visible.midY - size.height / 2, width: size.width,
          height: size.height), display: false)
    } else {
      center()
    }
    makeKeyAndOrderFront(nil)
    NSApp.activate()
  }
}

private struct OCRResultView: View {
  @Bindable var model: OCRResultModel
  let onSelectAgain: () -> Void
  let onClose: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let image = model.image {
        Image(nsImage: image).resizable().scaledToFit()
          .frame(maxWidth: .infinity, maxHeight: 84).accessibilityLabel("読み取り範囲")
      }
      switch model.phase {
      case .capturing:
        Spacer()
        HStack {
          Spacer()
          ProgressView()
          Text("画面を準備しています…")
          Spacer()
        }
        Spacer()
      case .recognizing, .ready:
        Text("同じ範囲をVisionとocrusで読み取ります。結果はそれぞれ修正・コピーできます。")
          .font(.caption).foregroundStyle(.secondary)
        HStack(alignment: .top, spacing: 16) {
          OCRBackendView(model: model.vision, name: "macOS Vision", shortcut: "1")
          Divider()
          OCRBackendView(model: model.ocrus, name: "ocrus", shortcut: "2")
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      case .failed:
        Spacer()
        Label(model.message, systemImage: "exclamationmark.triangle").frame(maxWidth: .infinity)
        if model.needsPermission {
          Button("画面収録の設定を開く") {
            if let url = URL(
              string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
            {
              NSWorkspace.shared.open(url)
            }
          }.frame(maxWidth: .infinity)
        }
        Spacer()
      }
      HStack {
        Button("閉じる", action: onClose).keyboardShortcut(.cancelAction)
        Spacer()
        Button("もう一度範囲選択", action: onSelectAgain)
      }
    }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct OCRBackendView: View {
  @Bindable var model: OCRBackendModel
  let name: String
  let shortcut: KeyEquivalent
  @State private var copied = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(name).font(.headline)
        Spacer()
        if let seconds = model.elapsedSeconds {
          Text(String(format: "%.2f秒", seconds)).font(.caption).foregroundStyle(.secondary)
        }
      }
      switch model.phase {
      case .recognizing:
        VStack(spacing: 12) {
          Spacer()
          ProgressView()
          Text("読み取り中…")
          Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      case .ready:
        TextEditor(text: $model.text).font(.system(.body, design: .monospaced))
          .accessibilityLabel("\(name)の認識結果")
          .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
      case .failed:
        Text(model.message).foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      Button(copied ? "コピーしました" : "コピー") {
        NSPasteboard.general.clearContents()
        copied = NSPasteboard.general.setString(model.text, forType: .string)
      }.keyboardShortcut(shortcut, modifiers: .command)
        .disabled(model.phase != .ready || model.text.isEmpty)
        .onChange(of: model.text) { _, _ in copied = false }
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
