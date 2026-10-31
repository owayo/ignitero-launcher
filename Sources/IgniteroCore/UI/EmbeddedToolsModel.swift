import Foundation
import Observation

public enum MarkdownInput {
  public static func validatedURL(_ text: String) -> String? {
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard value.utf8.count <= 8192,
      !value.unicodeScalars.contains(where: {
        CharacterSet.whitespacesAndNewlines.contains($0)
          || CharacterSet.controlCharacters.contains($0)
      }),
      let url = URL(string: value),
      let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
      let host = url.host, !host.isEmpty, url.user == nil, url.password == nil
    else { return nil }
    return url.absoluteString
  }
}

@MainActor @Observable
public final class EmbeddedToolsModel {
  public enum Mode { case usage, markdown }
  public var mode: Mode = .usage
  public var isLoading = false
  public var errorMessage = ""
  public var usage: AIUsageSnapshot?
  public var urlInput = ""
  public var markdownText = ""
  public var document: MarkdownDocument?
  public var isActive = false
  public var onActivityChanged: ((Bool) -> Void)?
  private let service: any EmbeddedToolsServing
  private(set) var request: Task<Void, Never>?
  private var generation = UUID()

  public init(service: any EmbeddedToolsServing = EmbeddedToolsService()) { self.service = service }
  public var canCopyMarkdown: Bool {
    isActive && mode == .markdown && !isLoading && document != nil && errorMessage.isEmpty
      && !markdownText.isEmpty
  }

  public func openUsage() {
    cancelRequest()
    mode = .usage
    activate()
    refreshUsage(force: false)
  }
  public func openMarkdown(url: String = "") {
    cancelRequest()
    mode = .markdown
    errorMessage = ""
    activate()
    if !url.isEmpty {
      urlInput = url
      fetchMarkdown()
    }
  }
  private func activate() {
    isActive = true
    onActivityChanged?(true)
  }
  public func close() {
    let wasActive = isActive
    cancelRequest()
    isActive = false
    if wasActive { onActivityChanged?(false) }
  }
  public func cancelRequest() {
    generation = UUID()
    request?.cancel()
    request = nil
    isLoading = false
  }
  public func refreshUsage(force: Bool = true) {
    guard isActive && mode == .usage else { return }
    cancelRequest()
    let id = generation
    isLoading = true
    errorMessage = ""
    request = Task { [weak self] in
      guard let self else { return }
      do {
        let snapshot = try await service.usage(refresh: force)
        guard generation == id, !Task.isCancelled else { return }
        usage = snapshot
      } catch {
        guard generation == id, !Task.isCancelled else { return }
        errorMessage = error.localizedDescription
      }
      if generation == id {
        isLoading = false
        request = nil
      }
    }
  }
  public func fetchMarkdown() {
    guard isActive && mode == .markdown else { return }
    cancelRequest()
    document = nil
    markdownText = ""
    errorMessage = ""
    guard let url = MarkdownInput.validatedURL(urlInput) else {
      errorMessage = "http:// または https:// で始まるURLを入力してください。"
      return
    }
    let id = generation
    isLoading = true
    request = Task { [weak self] in
      guard let self else { return }
      do {
        let value = try await service.markdown(url: url)
        guard generation == id, !Task.isCancelled else { return }
        document = value
        markdownText = value.markdown
        if value.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          errorMessage = "このページから本文を取得できませんでした。"
        }
      } catch {
        guard generation == id, !Task.isCancelled else { return }
        errorMessage = error.localizedDescription
      }
      if generation == id {
        isLoading = false
        request = nil
      }
    }
  }
}
