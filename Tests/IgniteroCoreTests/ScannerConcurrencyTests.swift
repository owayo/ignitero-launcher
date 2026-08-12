import Foundation
import Synchronization
import Testing

@testable import IgniteroCore

private final class BlockingFileSystemProvider: FileSystemProvider, @unchecked Sendable {
  let started = Mutex(false)
  let release = DispatchSemaphore(value: 0)

  func contentsOfDirectory(atPath _: String) throws -> [String] {
    started.withLock { $0 = true }
    release.wait()
    return []
  }

  func isDirectory(atPath _: String) -> Bool {
    true
  }

  func fileExists(atPath _: String) -> Bool {
    true
  }
}

@Suite("スキャナーの並行実行")
struct ScannerConcurrencyTests {
  @MainActor
  private func verifyMainActorRemainsResponsive(
    hasStarted: @escaping @Sendable () -> Bool,
    release: DispatchSemaphore,
    operation: @MainActor @escaping @Sendable () async throws -> Void
  ) async throws {
    // 実装が呼び出し元のアクターを占有してもテスト全体が停止しないよう、時間切れで解除する。
    let timeoutFinished = DispatchSemaphore(value: 0)
    let timedOut = Mutex(false)
    let timeoutThread = Thread {
      if timeoutFinished.wait(timeout: .now() + 30) == .timedOut {
        timedOut.withLock { $0 = true }
        release.signal()
      }
    }
    timeoutThread.start()
    defer {
      release.signal()
      timeoutFinished.signal()
    }

    let operationTask = Task { @MainActor in
      try await operation()
    }

    while !hasStarted() {
      await Task.yield()
    }

    #expect(!timedOut.withLock { $0 })

    release.signal()
    try await operationTask.value
  }

  @Test("ディレクトリスキャン中もメインアクターが進行する")
  @MainActor
  func directoryScanDoesNotBlockMainActor() async throws {
    let fileSystem = BlockingFileSystemProvider()
    let scanner = DirectoryScanner(fileSystemProvider: fileSystem)
    let registered = RegisteredDirectory(
      path: "/blocked",
      parentOpenMode: .none,
      parentEditor: nil,
      subdirsOpenMode: .none,
      subdirsEditor: nil,
      scanForApps: false
    )

    try await verifyMainActorRemainsResponsive(
      hasStarted: { fileSystem.started.withLock { $0 } },
      release: fileSystem.release,
      operation: {
        _ = try await scanner.scan(directories: [registered])
      })
  }
}
