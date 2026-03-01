import Foundation
import Testing

@testable import IgniteroCore

// MARK: - PerformanceMonitor Measure Tests

@Suite("PerformanceMonitor Measure")
struct PerformanceMonitorMeasureTests {

  @Test func measureBlockReturnsPositiveDuration() {
    let ms = PerformanceMonitor.measure("test-sync") {}
    #expect(ms >= 0)
  }

  @Test func measureAsyncBlockReturnsPositiveDuration() async {
    let ms = await PerformanceMonitor.measureAsync("test-async") {}
    #expect(ms >= 0)
  }

  @Test func measureBlockWithWorkReturnsDuration() {
    let ms = PerformanceMonitor.measure("test-work") {
      var sum = 0
      for i in 0..<1000 {
        sum += i
      }
      _ = sum
    }
    #expect(ms >= 0)
  }

  @Test func measureAsyncBlockWithSleepReturnsDuration() async throws {
    let ms = await PerformanceMonitor.measureAsync("test-async-sleep") {
      try? await Task.sleep(for: .milliseconds(10))
    }
    // Should be at least ~10ms (sleep duration)
    #expect(ms >= 5)
  }
}

// MARK: - PerformanceMonitor Signpost Tests

@Suite("PerformanceMonitor Signpost")
struct PerformanceMonitorSignpostTests {

  @Test func beginAndEndIntervalDoesNotCrash() {
    let state = PerformanceMonitor.beginInterval("test-interval")
    PerformanceMonitor.endInterval("test-interval", state)
  }

  @Test func multipleIntervalsCanCoexist() {
    let state1 = PerformanceMonitor.beginInterval("interval-1")
    let state2 = PerformanceMonitor.beginInterval("interval-2")
    PerformanceMonitor.endInterval("interval-2", state2)
    PerformanceMonitor.endInterval("interval-1", state1)
  }
}

// MARK: - SearchService Performance Tests

@Suite("SearchService Performance")
struct SearchServicePerformanceTests {

  @Test func searchPerformanceWith100Items() {
    let service = SearchService()
    var apps: [AppItem] = []
    for i in 0..<100 {
      apps.append(AppItem(name: "Application \(i)", path: "/Applications/App\(i).app"))
    }
    let ms = PerformanceMonitor.measure("search-100-items") {
      _ = service.search(query: "app", apps: apps, directories: [], commands: [], history: [])
    }
    #expect(ms < 500)  // Search should complete within 500ms
  }

  @Test func searchPerformanceWith500Items() {
    let service = SearchService()
    var apps: [AppItem] = []
    for i in 0..<500 {
      apps.append(AppItem(name: "Application \(i)", path: "/Applications/App\(i).app"))
    }
    let ms = PerformanceMonitor.measure("search-500-items") {
      _ = service.search(query: "app", apps: apps, directories: [], commands: [], history: [])
    }
    #expect(ms < 2000)  // 500 items should still be under 2 seconds
  }
}

// MARK: - CalculatorEngine Performance Tests

@Suite("CalculatorEngine Performance")
struct CalculatorEnginePerformanceTests {

  @Test func calculatorPerformance1000Evaluations() {
    let engine = CalculatorEngine()
    let ms = PerformanceMonitor.measure("calculator-1000") {
      for _ in 0..<1000 {
        _ = engine.evaluate("(1+2)*3/4-5%2+100*200")
      }
    }
    #expect(ms < 1000)  // 1000 calculations under 1 second
  }

  @Test func calculatorPerformanceSimpleExpression() {
    let engine = CalculatorEngine()
    let ms = PerformanceMonitor.measure("calculator-simple") {
      for _ in 0..<10000 {
        _ = engine.evaluate("1+1")
      }
    }
    #expect(ms < 1000)  // 10000 simple calculations under 1 second
  }
}

// MARK: - WindowManager Performance Tests

@Suite("WindowManager Performance")
struct WindowManagerPerformanceTests {

  @MainActor
  @Test func windowManagerCreationPerformance() {
    let ms = PerformanceMonitor.measure("window-manager-creation") {
      _ = WindowManager()
    }
    #expect(ms < 50)  // WindowManager creation under 50ms
  }
}

// MARK: - LauncherPanel Performance Tests

@Suite("LauncherPanel Performance")
struct LauncherPanelPerformanceTests {

  @MainActor
  @Test func launcherPanelCreationPerformance() {
    let ms = PerformanceMonitor.measure("launcher-panel-creation") {
      _ = LauncherPanel()
    }
    #expect(ms < 100)  // Panel creation under 100ms
  }
}
