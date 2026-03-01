import AppKit
import Foundation

// MARK: - Special Key Types

/// ランチャーで処理する特殊キーの種別
public enum SpecialKey: Sendable {
  case left
  case right
  case enter
  case escape
}

/// 特殊キー操作の結果アクション
public enum SpecialKeyAction: Sendable, Equatable {
  /// デフォルトターミナルでディレクトリを開く
  case openInTerminal
  /// エディタピッカーを表示する
  case showEditorPicker
  /// ターミナルピッカーを表示する
  case showTerminalPicker
  /// 選択された結果を実行する
  case execute
  /// ランチャーを非表示にする
  case dismiss
  /// 計算結果をクリップボードにコピーする
  case copyCalculator
}

// MARK: - LauncherViewModel

/// ランチャービューのビューモデル。
///
/// 検索ロジック、キーボードナビゲーション、計算式評価、アップデートバナー管理を担当する。
/// SwiftUI ビューは表示のみを担い、ロジックはすべてこの ViewModel に集約する。
@MainActor
@Observable
public final class LauncherViewModel {

  // MARK: - Published State

  /// キャッシュスキャン中かどうか
  public var isScanning: Bool = false

  /// 検索クエリ文字列
  public var searchQuery: String = ""

  /// 検索結果一覧
  public private(set) var searchResults: [SearchResult] = []

  /// 現在選択中のインデックス
  public var selectedIndex: Int = 0

  /// 計算式の評価結果（計算式でない場合は nil）
  public private(set) var calculatorResult: String?

  /// 新バージョンのバージョン文字列（アップデートがない場合は nil）
  public var updateBannerVersion: String?

  /// 現在のバージョンのアップデートバナーが非表示にされたか
  public private(set) var isUpdateBannerDismissed: Bool = false

  // MARK: - Data Sources

  /// 検索対象のアプリケーション一覧
  public var apps: [AppItem] = []

  /// 検索対象のディレクトリ一覧
  public var directories: [DirectoryItem] = []

  /// 検索対象のカスタムコマンド一覧
  public var commands: [CustomCommand] = []

  /// 選択履歴
  public var history: [SelectionHistoryEntry] = []

  /// エディタ名（rawValue）→ キャッシュ済みアイコンパスのマッピング
  public var editorIconPaths: [String: String] = [:]

  /// デフォルトターミナルの表示名
  public var defaultTerminalName: String = "Terminal"

  /// 検索フィールドへのフォーカス要求トリガー（インクリメントで発火）
  public var focusTrigger: Int = 0

  // MARK: - Dependencies

  private let searchService: SearchService
  private let calculatorEngine: CalculatorEngine

  // MARK: - Computed Properties

  /// アップデートバナーを表示すべきかどうか
  public var shouldShowUpdateBanner: Bool {
    updateBannerVersion != nil && !isUpdateBannerDismissed
  }

  // MARK: - Initialization

  /// LauncherViewModel を初期化する。
  ///
  /// - Parameters:
  ///   - searchService: ファジー検索サービス
  ///   - calculatorEngine: 計算式評価エンジン
  public init(
    searchService: SearchService = SearchService(),
    calculatorEngine: CalculatorEngine = CalculatorEngine()
  ) {
    self.searchService = searchService
    self.calculatorEngine = calculatorEngine
  }

  // MARK: - Search

  /// 検索クエリに基づいて検索を実行し、結果と計算式評価を更新する。
  ///
  /// 検索クエリが変更されるたびに呼び出す。結果更新時に selectedIndex を 0 にリセットする。
  public func updateSearch() {
    // 検索実行
    searchResults = searchService.search(
      query: searchQuery,
      apps: apps,
      directories: directories,
      commands: commands,
      history: history
    )

    // 特殊アクション挿入
    insertSpecialActions()

    // 選択インデックスをリセット
    selectedIndex = 0

    // 計算式チェック
    checkForCalculatorExpression()
  }

  // MARK: - Selection Navigation

  /// 選択を 1 つ上に移動する。先頭の場合は移動しない。
  public func moveSelectionUp() {
    guard selectedIndex > 0 else { return }
    selectedIndex -= 1
  }

  /// 選択を 1 つ下に移動する。末尾の場合は移動しない。
  public func moveSelectionDown() {
    guard !searchResults.isEmpty else { return }
    let maxIndex = searchResults.count - 1
    guard selectedIndex < maxIndex else { return }
    selectedIndex += 1
  }

  // MARK: - Confirm Selection

  /// 現在選択中の検索結果を返す。結果がない場合は nil。
  ///
  /// コントローラー側で結果を受け取り、アプリ起動やディレクトリオープンを実行する。
  /// - Returns: 選択中の検索結果、または nil
  public func confirmSelection() -> SearchResult? {
    guard !searchResults.isEmpty, selectedIndex < searchResults.count else {
      return nil
    }
    return searchResults[selectedIndex]
  }

  // MARK: - Clipboard

  /// 計算結果をクリップボードにコピーする。計算結果がない場合は何もしない。
  public func copyCalculatorResult() {
    guard let result = calculatorResult else { return }
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(result, forType: .string)
  }

  // MARK: - Special Key Handling

  /// 特殊キー入力を処理し、対応するアクションを返す。
  ///
  /// - Parameters:
  ///   - key: 押されたキー
  ///   - modifiers: 修飾キーフラグ
  /// - Returns: 実行すべきアクション。該当するアクションがない場合は nil。
  public func handleSpecialKey(
    _ key: SpecialKey,
    modifiers: NSEvent.ModifierFlags
  ) -> SpecialKeyAction? {
    switch key {
    case .escape:
      return .dismiss

    case .enter:
      // 計算結果がある場合はコピー
      if calculatorResult != nil {
        return .copyCalculator
      }
      // 結果がない場合は何もしない
      guard !searchResults.isEmpty else { return nil }
      return .execute

    case .right:
      guard let selected = confirmSelection(), selected.kind == .directory else {
        return nil
      }
      if modifiers.contains(.command) {
        return .showTerminalPicker
      }
      return .openInTerminal

    case .left:
      guard let selected = confirmSelection(), selected.kind == .directory else {
        return nil
      }
      return .showEditorPicker
    }
  }

  // MARK: - Clear

  /// 検索状態をすべてリセットする。フォーカス喪失時に呼び出す。
  public func clearSearch() {
    searchQuery = ""
    searchResults = []
    selectedIndex = 0
    calculatorResult = nil
  }

  // MARK: - Update Banner

  /// 新バージョンのアップデートバナーを表示する。
  ///
  /// 以前のバージョンの非表示状態をリセットする。
  /// - Parameter version: 新バージョンの文字列
  public func showUpdateBanner(version: String) {
    updateBannerVersion = version
    isUpdateBannerDismissed = false
  }

  /// 指定バージョンのアップデートバナーを非表示にする。
  ///
  /// 現在のバナーバージョンと一致する場合のみ非表示フラグを設定する。
  /// - Parameter version: 非表示にするバージョン
  public func dismissUpdateBanner(version: String) {
    guard updateBannerVersion == version else { return }
    isUpdateBannerDismissed = true
  }

  // MARK: - Special Actions

  /// 検索クエリに応じた特殊アクション（Web検索、カラーピッカー、Emoji）を結果先頭に挿入する。
  private func insertSpecialActions() {
    let normalized = SearchQueryNormalizer.normalize(searchQuery)
    guard !normalized.isEmpty else { return }

    // Web検索: g <keyword>
    if normalized.hasPrefix("g ") {
      let keyword = String(normalized.dropFirst(2)).trimmingCharacters(in: .whitespaces)
      if !keyword.isEmpty,
        let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
      {
        let url = "https://www.google.com/search?q=\(encoded)"
        searchResults.insert(
          SearchResult(name: "Google で「\(keyword)」を検索", kind: .webSearch, score: -10, path: url),
          at: 0
        )
      }
    }

    // Web検索: x <keyword>
    if normalized.hasPrefix("x ") {
      let keyword = String(normalized.dropFirst(2)).trimmingCharacters(in: .whitespaces)
      if !keyword.isEmpty,
        let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
      {
        let url = "https://x.com/search?q=\(encoded)"
        searchResults.insert(
          SearchResult(name: "X で「\(keyword)」を検索", kind: .webSearch, score: -10, path: url),
          at: 0
        )
      }
    }

    // カラーピッカー
    if normalized == "color" || normalized == "colour" || normalized == "カラー" {
      searchResults.insert(
        SearchResult(name: "カラーピッカー", kind: .colorPicker, score: -10),
        at: 0
      )
    }

    // Emoji ピッカー
    if normalized == "emoji" || normalized.hasPrefix("emoji ") {
      searchResults.insert(
        SearchResult(name: "Emoji ピッカー", kind: .emoji, score: -10),
        at: 0
      )
    }
  }

  // MARK: - Calculator Expression Detection

  /// 検索クエリが算術式かどうかを判定し、計算結果を更新する。
  ///
  /// 単一の数値（演算子を含まない）は計算式とみなさない。
  public func checkForCalculatorExpression() {
    let query = searchQuery.trimmingCharacters(in: .whitespaces)
    guard !query.isEmpty else {
      calculatorResult = nil
      return
    }

    // 演算子を含まない場合は計算式ではない
    let hasOperator = query.contains(where: { "+-*/%".contains($0) })
    guard hasOperator else {
      calculatorResult = nil
      return
    }

    if let value = calculatorEngine.evaluate(query) {
      calculatorResult = calculatorEngine.formatResult(value, locale: Locale(identifier: "en_US"))
    } else {
      calculatorResult = nil
    }
  }
}
