import Darwin
import Foundation
import IgniteroNative

public struct AIUsageSnapshot: Decodable, Sendable {
  public let report: AIUsageReport
  public let warnings: [String]
}
public struct AIUsageReport: Decodable, Sendable {
  public let generated_at: String
  public let accounts: [AIUsageAccount]
}
public struct AIUsageAccount: Decodable, Sendable {
  public let profile: String
  public let provider: String
  public let ok: Bool
  public let plan: String?
  public let email: String?
  public let profile_email: String?
  public let label: String?
  public let group_label: String?
  public let five_hour: AIUsageWindow?
  public let weekly: AIUsageWindow?
  public let manual_resets: [AIUsageReset]?
  public let error: String?

  public var displayName: String {
    if let label = label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
      return label
    }
    for value in [email, profile_email].compactMap({ $0 }) {
      let parts = value.split(separator: "@", omittingEmptySubsequences: false)
      if parts.count == 2, parts.allSatisfy({ !$0.isEmpty }) { return value }
    }
    return profile.isEmpty ? provider : profile
  }
}
public struct AIUsageWindow: Decodable, Sendable {
  public let kind: String?
  public let used_percent: Double?
  public let resets_at: String?
  public func title(fallback: String) -> String {
    switch kind {
    case "five_hour": "5時間"
    case "daily": "1日"
    case "weekly": "1週間"
    case "monthly": "1か月"
    default: fallback
    }
  }
}
public struct AIUsageReset: Decodable, Sendable {
  public let kind: String?
  public let remaining: UInt64?
  public let expires_at: String?
  public let paused: Bool?
}
public struct MarkdownDocument: Decodable, Sendable {
  public let markdown: String
  public let url: String
  public let final_url: String
  public let title: String?
}

public protocol EmbeddedToolsServing: Sendable {
  func usage(refresh: Bool) async throws -> AIUsageSnapshot
  func markdown(url: String) async throws -> MarkdownDocument
}
public enum EmbeddedToolsError: LocalizedError, Sendable {
  case failure(String)
  case busy
  case invalidResponse
  public var errorDescription: String? {
    switch self {
    case .failure(let message): message
    case .busy: "前の処理の終了を待っています。"
    case .invalidResponse: "取得結果を読み込めませんでした。もう一度お試しください。"
    }
  }
}

public struct EmbeddedToolsService: EmbeddedToolsServing {
  public init() {}
  public func usage(refresh: Bool) async throws -> AIUsageSnapshot {
    try await Self.run(kind: 1, request: ["refresh": refresh])
  }
  public func markdown(url: String) async throws -> MarkdownDocument {
    try await Self.run(kind: 2, request: ["url": url])
  }
  private struct Envelope<T: Decodable & Sendable>: Decodable, Sendable {
    let schema_version: Int
    let data: T?
    let error: String?
  }
  /// Polling yields to Swift's scheduler; the Rust worker owns blocking IO and Chrome.
  @concurrent
  private static func run<T: Decodable & Sendable, R: Encodable & Sendable>(
    kind: UInt32, request: R
  ) async throws -> T {
    let payload = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
    let job: EmbeddedJob
    while true {
      try Task.checkCancellation()
      do {
        job = try EmbeddedJob(kind: kind, request: payload)
        break
      } catch EmbeddedToolsError.busy {
        try await Task.sleep(for: .milliseconds(80))
      }
    }
    return try await withTaskCancellationHandler {
      while true {
        try Task.checkCancellation()
        if let data = try job.poll() {
          let envelope = try JSONDecoder().decode(Envelope<T>.self, from: data)
          guard envelope.schema_version == 1 else { throw EmbeddedToolsError.invalidResponse }
          if let error = envelope.error { throw EmbeddedToolsError.failure(error) }
          guard let value = envelope.data else { throw EmbeddedToolsError.invalidResponse }
          try Task.checkCancellation()
          return value
        }
        try await Task.sleep(for: .milliseconds(80))
      }
    } onCancel: {
      job.cancel()
    }
  }
}

/// Cancellation may run concurrently with polling. Ownership ends after both have returned.
private final class EmbeddedJob: @unchecked Sendable {
  private let handle: OpaquePointer
  init(kind: UInt32, request: String) throws {
    var error: UnsafeMutablePointer<CChar>?
    var status: Int32 = 0
    let pointer = request.withCString { ignitero_job_start(kind, $0, &status, &error) }
    defer { if let error { ignitero_string_free(error) } }
    guard let pointer else {
      if status == 2 { throw EmbeddedToolsError.busy }
      throw EmbeddedToolsError.failure(error.map { String(cString: $0) } ?? "処理を開始できませんでした。")
    }
    handle = pointer
  }
  deinit { ignitero_job_free(handle) }
  func cancel() { ignitero_job_cancel(handle) }
  func poll() throws -> Data? {
    var result: UnsafeMutablePointer<CChar>?
    let status = ignitero_job_poll(handle, &result)
    defer { if let result { ignitero_string_free(result) } }
    if status == 0 { return nil }
    guard status == 1, let result else { throw EmbeddedToolsError.invalidResponse }
    return Data(bytes: result, count: strlen(result))
  }
}
