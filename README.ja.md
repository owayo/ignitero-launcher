# README.ja

このリポジトリの日本語版 README は [README.md](./README.md) に統合しています。

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
