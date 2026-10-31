import Foundation
import Network
import Synchronization
import Testing

@testable import IgniteroCore

@Suite("Embedded tools native integration", .serialized, .timeLimit(.minutes(2)))
struct EmbeddedToolsIntegrationTests {
  @Test(.enabled(if: ProcessInfo.processInfo.environment["IGNITERO_TOOLS_INTEGRATION"] == "1"))
  func markdownUsesTheNativeBridgeAndSystemChrome() async throws {
    let server = try HTTPPageFixture()
    let url = try await server.start()
    let result = try await EmbeddedToolsService().markdown(url: url)
    #expect(result.title == "Native Markdown")
    #expect(result.markdown.contains("# Native document"))
    #expect(result.markdown.contains("Rendered content"))
    #expect(!result.markdown.contains("Hidden content"))
    #expect(result.markdown.contains("/Case?X=AbC"))
    #expect(result.final_url == url)
  }
  @Test(.enabled(if: ProcessInfo.processInfo.environment["IGNITERO_TOOLS_INTEGRATION"] == "1"))
  func backendErrorsCrossTheABIWithoutLaunchingChrome() async {
    await #expect(throws: (any Error).self) {
      _ = try await EmbeddedToolsService().markdown(url: "file:///tmp/page")
    }
  }
}

private final class HTTPPageFixture: @unchecked Sendable {
  private let listener: NWListener
  private let queue = DispatchQueue(label: "tools-http-fixture")
  init() throws {
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
    listener = try NWListener(using: parameters)
    let body =
      "<html><head><title>Native Markdown</title></head><body><h1>Native document</h1><p hidden>Hidden content</p><a href='/Case?X=AbC'>Case link</a><script>document.body.insertAdjacentHTML('beforeend','<p>Rendered content</p>')</script></body></html>"
    let response = Data(
      "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        .utf8)
    let connectionQueue = queue
    listener.newConnectionHandler = { connection in
      connection.start(queue: connectionQueue)
      connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { _, _, _, _ in
        connection.send(
          content: response, completion: .contentProcessed { _ in connection.cancel() })
      }
    }
  }
  deinit { listener.cancel() }
  func start() async throws -> String {
    let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
      let ready = Mutex<CheckedContinuation<UInt16, any Error>?>(continuation)
      listener.stateUpdateHandler = { [listener] state in
        let result: Result<UInt16, any Error>
        switch state {
        case .ready:
          guard let port = listener.port?.rawValue else { return }
          result = .success(port)
        case .failed(let error): result = .failure(error)
        default: return
        }
        ready.withLock { continuation in
          continuation?.resume(with: result)
          continuation = nil
        }
        listener.stateUpdateHandler = nil
      }
      listener.start(queue: queue)
    }
    return "http://127.0.0.1:\(port)/"
  }
}
