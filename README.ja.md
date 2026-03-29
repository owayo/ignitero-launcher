# README.ja

このリポジトリの日本語版 README は [README.md](./README.md) に統合しています。

2026-03-30 時点の更新内容:

- 空クエリ履歴の優先順位付けで、同じ使用回数なら最終利用日時が新しい項目を先に出すよう修正
- カスタムコマンド履歴を `command://<UUID>` 識別子で保持するよう修正し、空クエリ履歴表示と起動時クリーンアップで正しく残るように修正
- テスト数を 758 → 763 に増加（SearchService / AppCoordinator の履歴回帰テストを追加）
- 各ターミナルの AppleScript 対応状況を 2026-03-30 時点で再調査
  - Ghostty: 公式 AppleScript ドキュメントあり
  - cmux: 公式ドキュメントの主導線は CLI / Socket API、ローカル `sdef` で AppleScript 辞書も確認
  - Warp: 公式ドキュメントは URI Scheme / Launch Configurations が中心で、AppleScript 辞書は確認できず

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
