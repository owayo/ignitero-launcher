import AppKit
import Foundation
import Testing

@testable import IgniteroCore

@Suite("Embedded launcher tools", .timeLimit(.minutes(1)))
@MainActor
struct EmbeddedToolsTests {
  @Test func actionQueriesPreserveTheEntireURL() {
    let model = LauncherViewModel()
    for query in ["ai", "AI usage", "利用枠", "AI利用枠"] {
      model.searchQuery = query
      model.updateSearch()
      #expect(model.searchResults.first?.kind == .aiUsage)
    }
    let url =
      "https://example.com/Case/" + String(repeating: "AbC", count: 40) + "?Token=AbC+%2F&x=Y"
    model.searchQuery = "MD \(url)"
    model.updateSearch()
    #expect(model.searchResults.first?.kind == .markdown)
    #expect(model.searchResults.first?.path == url)
    #expect(model.handleSpecialKey(.right, modifiers: []) == nil)
    model.searchQuery = "md"
    model.updateSearch()
    #expect(model.searchResults.first?.kind == .markdown)
    #expect(model.searchResults.first?.path == "")
  }
  @Test func onlyHTTPURLsWithoutCredentialsAreAccepted() {
    #expect(
      MarkdownInput.validatedURL(" https://example.com/Case?X=AbC+%2f ")
        == "https://example.com/Case?X=AbC+%2f")
    #expect(
      MarkdownInput.validatedURL("https://example.com/日本語?Q=AbC")
        == "https://example.com/%E6%97%A5%E6%9C%AC%E8%AA%9E?Q=AbC")
    #expect(MarkdownInput.validatedURL("https://例え.テスト/記事") != nil)
    for value in [
      "file:///tmp/a", "javascript:alert(1)", "example.com", "https://user:pass@example.com",
      "https://exa mple.com", "http://",
    ] {
      #expect(MarkdownInput.validatedURL(value) == nil)
    }
  }
  @Test func inactiveToolsCannotStartRequestsOrDismissAnotherPicker() async {
    let service = ControlledToolsService()
    let model = EmbeddedToolsModel(service: service)
    var events: [Bool] = []
    model.onActivityChanged = { events.append($0) }
    model.close()
    #expect(events.isEmpty)
    model.openMarkdown()
    model.close()
    model.close()
    model.urlInput = "https://example.com"
    model.fetchMarkdown()
    model.refreshUsage()
    #expect(events == [true, false])
    #expect(await service.callCount == 0)
    #expect(!model.canCopyMarkdown)
  }
  @Test func nullAndZeroUsageRemainDistinct() throws {
    let snapshot = try fixture()
    #expect(snapshot.report.accounts.count == 2)
    #expect(snapshot.report.accounts[0].five_hour?.used_percent == 0)
    #expect(snapshot.report.accounts[0].weekly?.used_percent == nil)
    #expect(snapshot.report.accounts[0].displayName == "Home")
    let unknown = try JSONDecoder().decode(
      AIUsageWindow.self, from: Data("{\"used_percent\":null}".utf8))
    #expect(unknown.title(fallback: "短期枠") == "短期枠")
    #expect(unknown.title(fallback: "長期枠") == "長期枠")
    #expect(snapshot.report.accounts[1].ok == false)
    #expect(snapshot.report.accounts[1].error == "Session expired")
  }
  @Test func closeAndReplacementRejectLateMarkdownResults() async throws {
    let service = ControlledToolsService()
    let model = EmbeddedToolsModel(service: service)
    model.openMarkdown(url: "https://example.com/Old")
    await service.waitForCalls(1)
    let oldRequest = model.request
    model.openMarkdown(url: "https://example.com/New")
    await service.waitForCalls(2)
    await service.finishMarkdown(1, text: "new")
    await model.waitForIdle()
    #expect(model.markdownText == "new")
    await service.finishMarkdown(0, text: "old")
    await oldRequest?.value
    #expect(model.markdownText == "new")
    model.openMarkdown(url: "https://example.com/Closed")
    await service.waitForCalls(3)
    let closingRequest = model.request
    model.close()
    await service.finishMarkdown(2, text: "closed")
    await closingRequest?.value
    #expect(model.isActive == false)
    #expect(model.markdownText.isEmpty)
    #expect(!model.canCopyMarkdown)
  }
  @Test func failedRefreshRetainsPreviousUsage() async throws {
    let service = ControlledToolsService()
    let model = EmbeddedToolsModel(service: service)
    model.openUsage()
    await service.waitForCalls(1)
    await service.finishUsage(.success(try fixture()))
    await model.waitForIdle()
    model.refreshUsage()
    await service.waitForCalls(2)
    await service.finishUsage(.failure(EmbeddedToolsError.failure("offline")))
    await model.waitForIdle()
    #expect(model.usage?.report.accounts.count == 2)
    #expect(model.errorMessage == "offline")
    #expect(await service.refreshes == [false, true])
  }
  @Test func invalidURLDoesNotCallTheServiceOrLeaveCopyableText() async {
    let service = ControlledToolsService()
    let model = EmbeddedToolsModel(service: service)
    model.openMarkdown(url: "file:///tmp/a")
    #expect(await service.callCount == 0)
    #expect(!model.errorMessage.isEmpty)
    #expect(!model.canCopyMarkdown)
  }

  private func fixture() throws -> AIUsageSnapshot {
    let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
      "Fixtures/EmbeddedTools.json")
    let envelope = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
    let data = try JSONSerialization.data(withJSONObject: envelope["data"]!)
    return try JSONDecoder().decode(AIUsageSnapshot.self, from: data)
  }
}

private actor ControlledToolsService: EmbeddedToolsServing {
  var callCount = 0
  var refreshes: [Bool] = []
  private var calls: [(Int, CheckedContinuation<Void, Never>)] = []
  private var usageCalls: [CheckedContinuation<AIUsageSnapshot, any Error>] = []
  private var markdownCalls: [CheckedContinuation<MarkdownDocument, any Error>] = []
  func usage(refresh: Bool) async throws -> AIUsageSnapshot {
    refreshes.append(refresh)
    return try await withCheckedThrowingContinuation { continuation in
      usageCalls.append(continuation)
      recordCall()
    }
  }
  func markdown(url: String) async throws -> MarkdownDocument {
    try await withCheckedThrowingContinuation { continuation in
      markdownCalls.append(continuation)
      recordCall()
    }
  }
  private func recordCall() {
    callCount += 1
    let ready = calls.filter { $0.0 <= callCount }
    calls.removeAll { $0.0 <= callCount }
    for (_, continuation) in ready { continuation.resume() }
  }
  func waitForCalls(_ count: Int) async {
    if callCount >= count { return }
    await withCheckedContinuation { calls.append((count, $0)) }
  }
  func finishUsage(_ result: Result<AIUsageSnapshot, any Error>) {
    usageCalls.removeFirst().resume(with: result)
  }
  func finishMarkdown(_ index: Int, text: String) {
    markdownCalls[index].resume(
      returning: MarkdownDocument(
        markdown: text, url: "https://example.com", final_url: "https://example.com", title: nil))
  }
}

extension EmbeddedToolsModel {
  fileprivate func waitForIdle() async {
    await request?.value
  }
}
