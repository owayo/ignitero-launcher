import Darwin
import Foundation
import Testing

@testable import IgniteroCore

/// 環境変数を指定したときだけ実行する、検索全体の比較用ベンチマーク。
@Suite("Search Benchmark", .serialized)
struct SearchBenchmarkTests {
  @Test(.enabled(if: ProcessInfo.processInfo.environment["IGNITERO_SEARCH_BENCHMARK"] == "1"))
  func measureSearch() {
    let service = SearchService()
    for itemCount in [20, 500, 2000] {
      let apps = (0..<itemCount).map {
        AppItem(name: "Application \($0)", path: "/Applications/App\($0).app")
      }
      let history = (0..<50).map { i in
        SelectionHistoryEntry(
          keyword: "ＡＰＰ\(i)",
          selectedPath: "/Applications/App\(i * (itemCount - 1) / 49).app", count: i + 1,
          lastUsed: Date(timeIntervalSince1970: 1_700_000_000 + Double(i)))
      }
      for query in ["app", "application 49", "absent", ""] {
        for _ in 0..<5 {
          _ = service.search(
            query: query, apps: apps, directories: [], commands: [], history: history)
        }
        var samples: [Double] = []
        var cpuSamples: [Double] = []
        var resultCount = 0
        for _ in 0..<7 {
          let start = ContinuousClock.now
          let cpuStart = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
          resultCount +=
            service.search(
              query: query, apps: apps, directories: [], commands: [], history: history
            ).count
          cpuSamples.append(Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - cpuStart) / 1e6)
          let duration = start.duration(to: .now).components
          samples.append(Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15)
        }
        let signature = service.search(
          query: query, apps: apps, directories: [], commands: [], history: history
        ).map { "\($0.kind):\($0.path):\($0.score)" }.joined(separator: "|")
          .utf8.reduce(UInt64(14_695_981_039_346_656_037)) {
            ($0 ^ UInt64($1)) &* 1_099_511_628_211
          }
        print(
          "SEARCH_BENCH items=\(itemCount) query=\(query.debugDescription) ms=\(samples) cpu_ms=\(cpuSamples) results=\(resultCount) signature=\(signature)"
        )
      }
    }
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    print("SEARCH_BENCH_MEMORY max_rss_bytes=\(usage.ru_maxrss)")
  }
}
