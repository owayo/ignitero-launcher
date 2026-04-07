# README.ja

このリポジトリの日本語版 README は [README.md](./README.md) に統合しています。

2026-04-08 時点の更新内容:

- テスト数を 815 → 822 に増加（CacheBootstrap autoUpdateIntervalNanoseconds のインターバルクランプ境界値テスト7件を追加）
- 各ターミナルの AppleScript 対応状況を 2026-04-08 時点で再調査（変更なし: Warp/cmux は引き続き非対応）
- コードベース全体レビュー実施、以下のバグを修正:
  - CacheBootstrap: `startAutoUpdate` のインターバル計算で `UInt64` オーバーフロー防止のためクランプ処理を追加（1〜8760時間に制限）
  - LauncherPanel: `updateConstraints` の不要なガード分岐を削除しコメントを正確な記述に修正

2026-04-05 時点の更新内容:

- テスト数を 802 → 815 に増加（SelectionHistory maxEntries 切り詰めテスト、EditorPickerPanel dismissPanel 回帰テスト、EditorType supportsCodeWorkspace テスト、CustomCommand 後方互換デコードテスト、WindowManager 状態管理テストを追加）
- 各ターミナルの AppleScript 対応状況を 2026-04-05 時点で再調査（変更なし: Warp/cmux は引き続き非対応）
- コードベース全体レビュー実施、以下のバグを修正:
  - WindowManager: `addGlobalMonitorForEvents` コールバックでの `MainActor.assumeIsolated` を `Task { @MainActor in }` に修正（データレース防止）
  - EditorPickerPanel: `dismissPanel()` で `pickerState.dismiss()` を呼ぶよう修正（ポーリングタスクリーク防止）
  - AppScanner: `localizedNameViaMdls` のパイプ読み取り順序を修正（デッドロック防止）
  - LaunchService: `ensureCmuxRunning` の `usleep` を `Task.sleep` に修正（cooperative thread pool ブロック防止）
  - SelectionHistory: `load()` で `maxEntries` 制限を適用するよう修正（外部編集による無制限エントリ防止）
  - SettingsManager: `@MainActor` を追加しデータレースを防止

2026-04-04 時点の更新内容:

- テスト数を 778 → 802 に増加（CalculatorEngine 減算結合性・科学記法拒否・浮動小数点剰余、VersionComparator 先頭ゼロ・大文字V・非数値セグメント、LaunchService パス正規化エッジケース、SelectionHistory command://保持・複数空パスpurge・save/load上限維持テストを追加）
- 各ターミナルの AppleScript 対応状況を 2026-04-04 時点で再調査（変更なし: Warp/cmux は引き続き非対応）
- コードベース全体レビュー実施（確認されたバグなし）

2026-04-03 時点の更新内容:

- テスト数を 770 → 778 に増加（SearchService 履歴集約テスト、LauncherViewModel コマンドキー操作テストを追加）
- 各ターミナルの AppleScript 対応状況を 2026-04-03 時点で再調査（変更なし）

2026-04-02 時点の更新内容:

- cmux の AppleScript サポートを削除し、CLI 直接実行に変更（AppleScript 辞書を持たないため）
- テスト数を 763 → 770 に増加（cmux テスト修正、スクリプトクリーンアップ境界値テスト、AppleScript 網羅テストを追加）
- 各ターミナルの AppleScript 対応状況を 2026-04-02 時点で再調査
  - Ghostty: 公式 AppleScript ドキュメントあり（1.3.0 以降）
  - cmux: AppleScript 辞書なし。CLI / Socket API で制御
  - Warp: AppleScript 辞書なし。`.command` ファイル方式

2026-03-30 時点の更新内容:

- 空クエリ履歴の優先順位付けで、同じ使用回数なら最終利用日時が新しい項目を先に出すよう修正
- カスタムコマンド履歴を `command://<UUID>` 識別子で保持するよう修正し、空クエリ履歴表示と起動時クリーンアップで正しく残るように修正
- テスト数を 758 → 763 に増加（SearchService / AppCoordinator の履歴回帰テストを追加）
- 各ターミナルの AppleScript 対応状況を 2026-03-30 時点で再調査

2026-03-23 時点の更新内容:

- Ghostty AppleScript を公式 1.3.0 API に更新（`make new window` + `input text "...\n"`）
- cmux AppleScript を追加し、無効な環境では CLI へフォールバック
- Warp は AppleScript 非対応のため `.command` 方式を維持（2026-03-23 再確認済み）
- UpdateChecker の既定 GitHub リポジトリを `owayo/ignitero-launcher` に修正
- UpdateChecker キャッシュに downloadURL を保存するよう修正（キャッシュヒット時にURLが空になるバグを修正）
- ルートディレクトリ `/` と末尾スラッシュ付きパスの正規化不具合を修正
- cleanupStaleCommandScripts の isRegularFile デフォルト値修正（ディレクトリ誤削除防止）
- 特殊アクション検索で `g x foo` が Google と X 両方にマッチするバグを修正
- setCacheUpdateSettings の onSettingsChanged コールバック呼び出し欠落を修正
- テスト数を 711 → 712 に増加（cmux AppleScript 回帰テストを追加）
- テスト数を 712 → 751 に増加（HapticService, EmojiPickerPanel, CalculatorEngine 境界値, EmojiKeywordSearch エッジケース, SelectionHistory 並行テスト等を追加）
- 各ターミナルの AppleScript 対応状況を 2026-03-26 時点で再調査（変更なし）
