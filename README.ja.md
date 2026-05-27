# README.ja

このリポジトリの日本語版 README は [README.md](./README.md) に統合しています。

2026-05-28 時点の更新内容:

- `depup --install` を実行し、`EmojiKit` を 2.5.0 → 3.0.0 にメジャーバージョンアップ
  - 3.0 はデプロイメントターゲットを iOS 18 / aligned OS バージョンへ引き上げる変更のみで、本プロジェクトの macOS 26 では破壊的変更なし
- 各ターミナルの AppleScript 対応状況を再調査（実装方針の変更なし）
  - Terminal.app / iTerm2 3.6.10 / Ghostty 1.3.1 / cmux 0.64.10: AppleScript 経由のコマンド実行を維持
  - Warp: 2026-05 時点でも AppleScript 非対応（GitHub issue #3364 が未対応）。`.command` 方式を維持
- コードベース全体レビュー実施、以下の改善を行った:
  - DirectoryScanner: 登録ディレクトリ内に `.app` 拡張子の通常ファイルが存在する場合に `AppItem` として登録されてしまい、起動時に `NSWorkspace.open` が失敗する不具合を修正。`AppScanner` と同様に `isDirectory` チェックを追加
  - WindowManager: アプリ切替通知ハンドラを `MainActor.assumeIsolated` から `Task { @MainActor in }` に変更し、`OperationQueue.main` のクロージャから MainActor へ確実にディスパッチするように統一（clickMonitor 側と同じパターンで一貫性を確保）
  - GlobalShortcutManager: Carbon ホットキー C コールバックとショートカット変更通知も同様に `Task { @MainActor in }` に統一
- テスト数を 920 → 922 に増加
  - DirectoryScanner: `.app` 拡張子の通常ファイルが `AppItem` として登録されないことを検証する Mock テストと実ファイルシステムテストを追加

2026-05-25 時点の更新内容:

- `depup --install` を実行し、依存パッケージ更新なし（4件すべて最新）を確認
- 各ターミナルの AppleScript 対応状況を再調査（実装方針の変更なし）
  - Terminal.app: Apple Support の案内とローカル辞書で `do script` を確認
  - iTerm2 3.6.10: 公式ドキュメントとローカル辞書で `create window with default profile` / `write` を確認
  - Ghostty 1.3.1: 公式 AppleScript ドキュメントとローカル辞書で `new window` / `input text` を確認
  - cmux 0.64.10: ローカル辞書で `new window` / `input text` を確認。公式ドキュメントは CLI / Socket API も自動化経路として案内
  - Warp 0.2026.05.20.09.21.02: 公式ドキュメントは URI Scheme / Launch Configurations と `.command` スクリプト実行を案内し、ローカルの Warp.app は AppleScript 辞書を取得できないため `.command` 方式を維持
- コードベース全体レビュー実施、実装挙動を変える確実なバグは検出されず
- テスト数を 918 → 920 に増加
  - LaunchService: Ghostty/cmux が `new window` + `input text` の AppleScript API を使うことを横断検証
  - LaunchService: AppleScript 非対応の Warp でも `.command` フォールバック用スクリプトが作業ディレクトリとコマンドを保持することを検証

2026-05-22 時点の更新内容:

- `depup --install` を実行し、依存パッケージ更新なし（4件すべて最新）を確認
- 各ターミナルの AppleScript 対応状況を再調査（実装方針の変更なし）
  - Terminal.app / iTerm2 3.6.10 / Ghostty 1.3.1 / cmux 0.64.7: AppleScript 経由のコマンド実行を維持（公式ドキュメントとローカル辞書を再確認）
  - Warp 0.2026.05.20.09.21.02: 公式ドキュメントは URI Scheme / Launch Configurations と `.command` スクリプト実行を案内し、ローカルの Warp.app は AppleScript 辞書を取得できないため `.command` 方式を維持
- コードベース全体レビュー実施、以下の確実なバグを修正:
  - UpdateChecker: GitHub Releases API の安定版配列がセマンティックバージョン順でない場合に、先頭の古い安定版を最新として扱う問題を修正。全安定版から `VersionComparator` で最大バージョンを選択するようにした
- テスト数を 917 → 918 に増加
  - UpdateChecker: API の返却順が `v1.9.9` → `v2.0.0` の場合でも `v2.0.0` を最新安定版として選択する回帰テストを追加

2026-05-20 時点の更新内容:

- `depup --install` を実行し、依存パッケージ更新なし（4件すべて最新）を確認
- 各ターミナルの AppleScript 対応状況を再調査（実装方針の変更なし）
  - Terminal.app / iTerm2 3.6.10 / Ghostty 1.3.1 / cmux 0.64.6: AppleScript 経由のコマンド実行を維持（公式ドキュメントとローカル辞書を再確認）
  - Warp: 2026-05 時点でも AppleScript 非対応。`warp://action/new_window` / `warp://launch/<name>` の URL Scheme は提供されているがコマンド実行は不可のため、`.command` 方式を維持
- コードベース全体レビュー実施、実装挙動を変える確実なバグは検出されず
- テスト数を 907 → 917 に増加
  - UpdateChecker: API 取得成功で新バージョンなしの場合に `currentVersion` がキャッシュされ、期限内は API 再呼び出しが抑制されることを検証
  - CalculatorEngine: 単項マイナスが括弧付き式に直接適用されるパターン（`-(1+2)`, `-((1+2)*3)` など）を 5 件追加
  - LaunchService: AppleScript 対応ターミナルが空コマンドでも非空スクリプトを返すこと、`tell application` のアプリ名と作業ディレクトリ付与時の `cd` 含有を確認する横断テストを 3 件追加

2026-05-19 時点の更新内容:

- `depup --install` を実行し、依存パッケージ更新なし（4件すべて最新）を確認
- 各ターミナルの AppleScript 対応状況を再調査（実装方針の変更なし）
  - Terminal.app: AppleScript 辞書の `do script` を確認
  - iTerm2 3.6.10: 公式ドキュメントとローカル辞書で `create window with default profile` / `write text` を確認
  - Ghostty 1.3.1: 公式 AppleScript ドキュメントとローカル辞書で `new window` / `input text` を確認
  - cmux 0.64.6: ローカル辞書で `new window` / `input text` を確認。カスタムコマンドは AppleScript 優先、失敗時とディレクトリオープンは CLI / Socket API を維持
  - Warp 0.2026.05.13.09.15.03: 公式ドキュメントは URI Scheme / Launch Configurations と `.command` スクリプト実行を案内し、ローカルの Warp.app は AppleScript 辞書を取得できないため `.command` 方式を維持
- コードベース全体レビュー実施、実装挙動を変える確実なバグは検出されず
- テスト数を 905 → 907 に増加
  - TerminalType: 設定 JSON に永続化される raw value と Codable 往復を検証

2026-05-13 時点の更新内容:

- `depup --install` を実行し、依存パッケージ更新なし（4件すべて最新）を確認
- 各ターミナルの AppleScript 対応状況を再調査（実装方針の変更なし）
  - Terminal.app: AppleScript 辞書の `do script` を確認
  - iTerm2 3.6.10: 公式ドキュメントとローカル辞書で `create window with default profile` / `write text` を確認
  - Ghostty 1.3.x: 公式 AppleScript ドキュメントとローカル辞書で `new window` / `input text` を確認
  - cmux 0.64.x: ローカル辞書で `new window` / `input text` を確認。公式ドキュメントは CLI / Socket API も自動化経路として案内
  - Warp: 公式ドキュメントは URL Scheme / Launch Configuration と `.command` スクリプト実行を案内し、AppleScript 辞書を取得できないため `.command` 方式を維持
- コードベース全体レビュー実施、実装挙動を変える確実なバグは検出されず
  - レビューで指摘された AppleScript ダブルクォートエスケープ (`\"`) は `osascript` で実機検証し、AppleScript 文字列リテラル内の有効なエスケープであることを確認（誤検出）
  - `executeCmuxCLI` の `waitUntilExit` / `semaphore.wait` 順序の指摘は、stdout/stderr を並列 drain しているため実害がないことを確認（順序依存のデッドロックは発生しない）
- テスト数を 901 → 903 に増加
  - CalculatorEngine: `parseExpression` / `parseTerm` のループ実装に対する回帰防止テストを追加。10000 項の加算式・乗算式でスタックオーバーフローせずに評価できることを検証

2026-05-11 時点の更新内容:

- `depup --install` を実行し、依存パッケージ更新なし（4件すべて最新）を確認
- 各ターミナルの AppleScript 対応状況を再調査（実装方針の変更なし）
  - Terminal.app: AppleScript 辞書の `do script` を確認
  - iTerm2 3.6.10: 公式ドキュメントとローカル辞書で `create window with default profile` / `write text` を確認
  - Ghostty 1.3.1: 公式ドキュメントとローカル辞書で `new window` / `input text` を確認
  - cmux 0.64.3: ローカル辞書で `new window` / `input text` を確認。公式ドキュメントは CLI / Socket API も自動化経路として案内
  - Warp 0.2026.04.27.15.32.03: 公式ドキュメントは `.command` スクリプト実行を案内し、ローカルの Warp.app は AppleScript 辞書を取得できないため `.command` 方式を維持
- コードベース全体レビュー実施、以下の確実なバグを修正:
  - LauncherViewModel: `g` / `x` の Web 検索アクションで検索語に `&` / `=` / `+` が含まれると、検索語の一部が別クエリパラメータとして解釈される問題を修正。URL クエリ値としてパーセントエンコードするようにした
- テスト数を 899 → 901 に増加（Google / X 検索のクエリ区切り文字エンコード回帰テストを追加）

2026-05-09 時点の更新内容:

- `depup --install` を実行し、依存パッケージ更新なし（4件すべて最新）を確認
- 各ターミナルの AppleScript 対応状況を再調査（実装方針の変更なし）
  - Terminal.app: AppleScript 辞書の `do script` を確認
  - iTerm2 3.6.10: 公式ドキュメントとローカル辞書で `create window with default profile` / `write text` を確認
  - Ghostty 1.3.1: 公式 AppleScript ドキュメントとローカル辞書で `new window` / `input text` を確認
  - cmux 0.64.3: ローカル辞書で `new window` / `input text` を確認。公式ドキュメントは CLI / Socket API も自動化経路として案内
  - Warp 0.2026.04.27.15.32.03: 公式ドキュメントは URI Scheme / Launch Configurations と `.command` スクリプト実行を案内し、ローカルの Warp.app は AppleScript 辞書を取得できないため `.command` 方式を維持
- コードベース全体レビュー実施、実装挙動を変える確実なバグは検出されず
- `SelectionHistory` の `command://UUID` 履歴クリーンアップ仕様をコメントとテストで明確化
- テスト数を 898 → 899 に増加（`validPaths` に含まれる `command://UUID` だけ保持し、削除済みカスタムコマンド履歴は purge されることを検証）

2026-05-06 時点の更新内容:

- `depup --install` を実行し、依存パッケージ更新なし（4件すべて最新）を確認
- 各ターミナルの AppleScript 対応状況を再調査（結論変更なし）
  - Terminal.app / iTerm2 / Ghostty 1.3.x / cmux 0.63.x: AppleScript 経由で実装済み
  - Warp: 2026年5月時点でも AppleScript 非対応が続くことを公式 Issue #3364 で確認。`.command` 方式を維持
- コードベース全体レビュー実施、以下の確実なバグを修正:
  - MenuBarActions: メニューバー経由の「キャッシュを再構築」がスキャン結果をログ出力するだけで保存していなかった経路を修正。`AppCoordinator.rebuildCacheAndReload` をコールバック (`onRebuildCache`) で呼び出すパターンに切り替え、スキャン結果の DB 保存とビューモデル再読込まで確実に行うようにした
  - UpdateChecker: GitHub API フェッチの `await` 中にユーザーがバナーを「非表示」にしても、ローカル変数で判定していたため反映されない問題を修正。判定直前および catch 経路でも `settingsManager.settings.updateCache?.dismissedVersion` を再取得するようにした
  - IconCacheManager: 自動更新スキャンと手動再構築が同じ出力パスに並行書き込みした場合にファイル破損が発生し得る問題を修正。`Data.write(to:options: .atomic)` で一時ファイル+リネームによる原子的書き込みに変更
- テスト数を 895 → 898 に増加
  - MenuBarActions: `onRebuildCache` コールバックの呼び出しと `isRebuildingCache` の遷移テストを追加
  - UpdateChecker: `await` 中に `dismissedVersion` が更新された場合、判定で最新値が反映されることを検証する回帰テストを追加
  - IconCacheManager: 8並列の `cacheIcon` 呼び出し後も PNG マジックナンバーを満たす破損のないファイルが残ることを検証するテストを追加

2026-05-02 時点の更新内容:

- `depup --install` を実行し、依存パッケージ更新なし（4件すべて最新）を確認
- 各ターミナルの AppleScript 対応状況を再調査（結論変更なし）
  - Terminal.app: AppleScript 辞書の `do script` を確認
  - iTerm2 3.6.10: 公式ドキュメントとローカル辞書で `create window with default profile` / `write text` を確認
  - Ghostty 1.3.1: 公式 AppleScript ドキュメントとローカル辞書で `new window` / `input text` を確認
  - cmux 0.63.2: ローカル辞書で `new window` / `input text` を確認。公式ドキュメントは引き続き CLI / Socket API も自動化経路として案内
  - Warp 0.2026.04.27.15.32.03: 公式ドキュメントは URI Scheme を案内し、ローカルの Warp.app は AppleScript 辞書を取得できないため `.command` 方式を維持
- コードベース全体レビュー実施、以下の確実なバグを修正:
  - LaunchService: cmux CLI の ping で `Process.run()` に失敗した後に `terminationStatus` を参照し、Foundation 例外でクラッシュする経路を修正
  - LaunchService: cmux の最前面化 AppleScript でも `Process.run()` 成功時だけ `waitUntilExit()` するよう修正
  - emoji キーワード更新スクリプト: Python の既定 CA パスが存在しない macOS 環境でも、システムまたは Homebrew の CA バンドルで HTTPS 検証を継続するよう修正
- `emoji_keywords_ja.json` を最新データで再生成
- テスト数を 893 → 895 に増加（cmux CLI パスなし・実行権限なしの回帰テストを追加）
- CodeRabbit CLI は認証済みだが、組織の時間上限により今回の差分レビューは開始できず

2026-04-29 時点の更新内容（追加分）:

- `depup --install` を実行し、依存パッケージ更新なし（4件すべて最新）を確認
- 各ターミナルの AppleScript 対応状況を再調査（結論変更なし）
  - Warp: 公式 GitHub Issue #3364 で AppleScript 非対応を確認。URI Scheme `warp://launch/<name>` ではコマンド実行が無視される既知のバグ（Issue #9007）あり。`.command` 方式が引き続き最適
  - 他のターミナル（Terminal.app / iTerm2 / Ghostty / cmux）は AppleScript 対応で実装済み
- テスト数を 880 → 893 に増加
  - SearchService: 履歴ブーストのエッジケース（クエリと無関係な履歴・空クエリで該当パスなし・最大件数クランプ）を追加
  - CalculatorEngine: `formatResult` に NaN / 正負の Infinity を渡してもクラッシュしないことを確認するテスト追加
  - UpdateChecker: キャッシュ境界値（12時間ちょうどは失効、11時間59分59秒はキャッシュ採用）テスト追加
  - AppScanner: `InfoPlist.strings` のローカライズ名解決（CFBundleName のみ・displayName 優先・対象キーなし・バイナリ plist 形式・未知ロケール）テスト追加
- コメントの日本語化（CalculatorEngine の英語コメント `consume operator` などを日本語へ置き換え）
- コードベース全体レビュー実施、確実なバグは検出されず（前回までのコミットで既に修正済み）

2026-04-29 時点の更新内容（初回分）:

- `depup --install` を実行し、依存パッケージ更新なし（4件すべて最新）を確認
- テスト数を 876 → 880 に増加（DirectoryScanner の親検索キーワード、AppScanner の除外アプリ照合の回帰テストを追加）
- 各ターミナルの AppleScript 対応状況を 2026-04-29 時点で再調査
  - Terminal.app: AppleScript 辞書の `do script` を確認
  - iTerm2: AppleScript 辞書の `create window with default profile` / `write` を確認。現行ドキュメントでは AppleScript は Deprecated 扱いだが利用可能
  - Ghostty 1.3.1: 公式 AppleScript ドキュメントとローカル辞書で `new window` / `input text` を確認
  - cmux 0.63.2: ローカル辞書で `new window` / `input text` を確認。公式 changelog でも AppleScript 関連修正を確認
  - Warp: 公式ドキュメントは URI Scheme / Launch Configurations と `.command` スクリプト実行を案内。ローカルの Warp.app は AppleScript 辞書を取得できず `.command` 方式を維持
- コードベース全体レビュー実施、以下の確実なバグを修正:
  - DirectoryScanner: `parent_search_keyword` が読み書きされるだけで検索名に反映されず、親ディレクトリをカスタムキーワードで検索できない問題を修正
  - AppScanner: 設定画面が除外アプリを表示名で保存する一方、スキャン時はパスだけで照合していたため、UIから除外したアプリが検索結果に残る問題を修正

2026-04-23 時点の更新内容:

- EmojiKit を 2.3.5 → 2.4.0 に更新
- テスト数を 871 → 876 に増加（CalculatorEngine の連続単項マイナスと括弧付き式の回帰テストを追加）
- 各ターミナルの AppleScript 対応状況を 2026-04-23 時点で再調査
  - Terminal.app: AppleScript 辞書の `do script` を確認
  - iTerm2 3.6.10: AppleScript の `create window with default profile` を確認
  - Ghostty 1.3.1: AppleScript 辞書の `new window` / `input text` を確認
  - cmux 0.63.2: AppleScript 辞書の `new window` / `input text` を確認。カスタムコマンド実行は引き続き AppleScript 優先
  - Warp 0.2026.04.08.08.36.05: 公式ドキュメントは URI Scheme / Launch Configurations を案内し、AppleScript 辞書は確認できず `.command` 方式を維持
- コードベース全体レビュー実施。ビルドと 876 テストは通過し、今回の確実な修正は CalculatorEngine の連続単項マイナスで深い再帰が発生する経路のみ
  - CalculatorEngine: 単項マイナスを再帰からループ処理へ変更し、長い `---...` 入力でもスタック消費を一定に抑制

2026-04-13 時点の更新内容:

- テスト数を 869 → 871 に増加（LaunchService の cmux AppleScript サポート行列とシングルクォート作業ディレクトリエスケープの回帰テストを追加）
- 各ターミナルの AppleScript 対応状況を 2026-04-13 時点で再調査
  - Ghostty 1.3.1: AppleScript の `new window` と `input text` を確認
  - cmux 0.63.2: AppleScript 辞書と `input text` を確認。カスタムコマンド実行を AppleScript へ切り替え
  - Warp 0.2026.04.01.08.39.02: 公式ドキュメントは URI Scheme / Launch Configurations を案内し、AppleScript 辞書は確認できず `.command` 方式を維持
- コードベース全体レビュー実施、以下のバグを修正:
  - LaunchService: Ghostty の AppleScript 生成で `make new window` を使っていたのを、現行辞書に合わせて `new window` に修正
  - LaunchService: cmux のカスタムコマンド実行を AppleScript 優先に変更し、失敗時は既存の CLI 実行へフォールバックするよう修正

2026-04-09 時点の更新内容:

- テスト数を 822 → 829 に増加（AppCoordinator エディタピッカー観測タスク管理テスト、LaunchService Ghostty フォールバック・commandScript 全ターミナルテストを追加）
- 各ターミナルの AppleScript 対応状況を 2026-04-09 時点で再調査（変更なし: Warp/cmux は引き続き非対応）
- コードベース全体レビュー実施、以下のバグを修正:
  - LaunchService: cmux CLI の stdout/stderr 逐次読み取りを `readabilityHandler` による並列読み取りに変更（デッドロック防止）
  - TerminalPickerState: `@MainActor` を追加し EditorPickerState との一貫性を確保（データレース防止）
  - AppCoordinator: `setupEditorPickerObservation` で前回タスクをキャンセルするよう修正（タスクリーク防止）

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
