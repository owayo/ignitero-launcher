# README.ja

このリポジトリの日本語版 README は [README.md](./README.md) に統合しています。

2026-03-20 時点の更新内容:

- Ghostty AppleScript を公式 1.3.0 API に更新（`make new window` + `input text "...\n"`）
- Warp / cmux は AppleScript 非対応のため既存方式を維持（2026-03-20 再確認済み）
- UpdateChecker の既定 GitHub リポジトリを `owayo/ignitero-launcher` に修正
- UpdateChecker キャッシュに downloadURL を保存するよう修正（キャッシュヒット時にURLが空になるバグを修正）
- ルートディレクトリ `/` と末尾スラッシュ付きパスの正規化不具合を修正
- cleanupStaleCommandScripts の isRegularFile デフォルト値修正（ディレクトリ誤削除防止）
- 特殊アクション検索で `g x foo` が Google と X 両方にマッチするバグを修正
- setCacheUpdateSettings の onSettingsChanged コールバック呼び出し欠落を修正
- テスト数を 694 → 711 に増加（バグ修正に対するリグレッションテスト 17件追加）
