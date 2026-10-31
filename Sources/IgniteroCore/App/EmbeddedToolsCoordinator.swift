import AppKit

@MainActor
public final class EmbeddedToolsCoordinator {
  public let model: EmbeddedToolsModel
  public private(set) var panel: EmbeddedToolsPanel?
  public init(service: any EmbeddedToolsServing = EmbeddedToolsService()) {
    model = EmbeddedToolsModel(service: service)
  }
  public func showUsage() {
    model.openUsage()
    present()
  }
  public func showMarkdown(url: String = "") {
    model.openMarkdown(url: url)
    present()
  }
  public func close() {
    model.close()
    panel?.orderOut(nil)
  }
  private func present() {
    if panel == nil {
      panel = EmbeddedToolsPanel(model: model)
      panel?.onDismiss = { [weak self] in self?.close() }
    }
    panel?.present()
  }
}
