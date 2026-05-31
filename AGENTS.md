# Ignitero Launcher

macOS向けメニューバー常駐型ランチャーアプリケーション。Swift 6.2 + SwiftUI + AppKit で構築。macOS 26+ ネイティブ。

## 技術スタック

- **言語**: Swift 6.2 (Strict Concurrency)
- **UI**: SwiftUI + AppKit (NSPanel)
- **データ**: GRDB.swift (SQLite), JSON 永続化
- **検索**: Fuse-Swift (ファジー検索)
- **ショートカット**: KeyboardShortcuts (Option+Space)
- **テスト**: Swift Testing (`import Testing`, `@Test`, `@Suite`, `#expect`)
- **パッケージ**: Swift Package Manager
- **最小OS**: macOS 26

## プロジェクト構造

```
Package.swift               # Swift Package 定義
Makefile                    # ビルド・インストール
Resources/                  # Info.plist, AppIcon.icns, entitlements
Sources/
  IgniteroCore/             # コアモジュール (テスト可能なライブラリ)
    App/                    # AppCoordinator, AppDelegate, GlobalShortcutManager（Carbon ホットキー C コールバックとショートカット変更通知は `Task { @MainActor in }` で確実に MainActor へディスパッチ）, MenuBarActions（キャッシュ再構築は onRebuildCache コールバックで AppCoordinator.rebuildCacheAndReload に委譲し、スキャン結果のDB保存とビューモデル再読込を確実に行う）, CacheBootstrap, PerformanceMonitor
    Data/                   # CacheDatabase (GRDB), SettingsManager, SelectionHistory（CacheDatabaseProtocol は保存・読み込みの両方を公開し、AppCoordinator は具象 CacheDatabase に依存せずキャッシュを ViewModel へ反映。設定JSON破損時はバックアップ復旧、I/Oエラーは呼び出し側へ伝播。カスタムコマンド履歴は command://UUID 識別子を validPaths に含めたものだけ起動時 purge で保持）
    Models/                 # AppItem, DirectoryItem, EditorType, TerminalType, EditorInfo, TerminalInfo
    Services/               # SearchService, LaunchService（空クエリ履歴は使用回数+最終利用日時で優先。選択履歴のキーワードは記録時・比較時とも SearchQueryNormalizer で正規化し、大文字/全角/前後空白でも履歴ブーストが効く。カスタムコマンド履歴は command://UUID 識別子で管理。Web検索特殊アクションのクエリ値は `&` / `=` / `+` 等を値としてパーセントエンコード。実行ディレクトリはシェルエスケープし、Terminal/iTerm2/Ghostty/cmuxはAppleScript。Ghostty 1.3.1 / cmux 0.64.10 で `new window` + `input text + \\n` を確認。GhosttyでAppleScript失敗時は.commandへフォールバック。cmux はカスタムコマンド実行を AppleScript 優先、失敗時とディレクトリオープンは CLI / Socket API を使用（stdout/stderr並列読み取りでデッドロック防止、CLI ping は実行ファイルの存在と実行権限を確認してから待機し、正常終了のみ成功扱い）。Warpは.command（Warp は AppleScript 辞書を取得できないため URL Scheme/Launch Configuration 方式と `.command` 実行を採る）、Terminal.appは/Systemパス優先）, AppScanner（除外アプリはパス・表示名・バンドル名で照合）, DirectoryScanner（親ディレクトリは parent_search_keyword を検索名に反映。`.app` 拡張子の通常ファイルは isDirectory チェックで AppItem 登録を防止）, UpdateChecker（GitHub Releases: owayo/ignitero-launcher。安定版はAPI配列順ではなくVersionComparatorで最大バージョンを選択。VersionComparatorはプレリリース(-)/ビルドメタ(+)を除いたコア部分を0埋めで比較し、1.2.0-beta.1を1.2.1と誤認しない。await 中の dismissedVersion 変更を反映するため判定直前に最新値を再取得）, IMEController（TIS APIはメインスレッド実行）, CalculatorEngine, IconCacheManager（自動更新と手動再構築の並行書き込みからファイル破損を守るため `.atomic` で書き込み）, EmojiKeywordSearch, HapticService
    UI/                     # LauncherPanel, LauncherView, LauncherViewModel, WindowManager（OperationQueue.main から発火するアプリ切替通知は `Task { @MainActor in }` で確実に MainActor へディスパッチ）, SettingsView, SettingsViewModel, EditorPickerPanel, TerminalPickerPanel, RadialPickerView, EmojiPickerPanel（AppCoordinator は Editor/Terminal ピッカーと同様に WindowManager.showPicker/hidePicker で isPickerVisible を管理し、表示中の Option+Space でも確実に閉じる）
  IgniteroLauncher/         # 実行可能ターゲット (@main エントリ)
    IgniteroApp.swift
Tests/
  IgniteroCoreTests/        # 924テスト (Swift Testing)
.backup/                    # Tauri v2 旧実装 (参照用)
```

## 開発コマンド

```bash
make build        # リリースビルド
make build-debug  # デバッグビルド
make test         # テスト実行 (swift test)
make bundle       # .app バンドル作成
make install      # /Applications にインストール＆起動
make run          # ビルド後に .app を起動
make dev          # デバッグビルド＆直接実行
make log          # ログストリーム (com.owayo.ignitero.launcher)
make clean        # ビルドキャッシュ削除
```

## テスト規約

- Swift Testing フレームワーク (`import Testing`) を使用、XCTest は不使用
- テストファイルは `Tests/IgniteroCoreTests/` に配置
- `@Suite` でグループ化、`@Test` でテスト関数をマーク
- `#expect` でアサーション
- プロトコルベースの DI でモック差し替え可能 (AppScannerProtocol, CacheDatabaseProtocol, IMEControlling, Launching, URLSessionProtocol)

## アーキテクチャ

- **MVVM**: LauncherViewModel, SettingsViewModel でUIロジックを分離
- **AppCoordinator**: 全コンポーネントを統合するメインコーディネーター
- **Protocol-based DI**: テスト容易性のためプロトコル経由で依存注入
- **@MainActor + @Observable**: SwiftUI/AppKit の状態管理
- **Sendable**: Swift 6.2 Strict Concurrency 準拠
- **@MainActor**: SettingsManager, WindowManager 等の状態管理クラスはメインアクター隔離で保護

# currentDate
Today's date is 2026-05-31.
