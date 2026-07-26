# Ignitero Launcher

macOS向けメニューバー常駐型ランチャーアプリケーション。Swift 6.2 以上 + SwiftUI + AppKit で構築。macOS 26+ ネイティブ。

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
    App/                    # AppCoordinator（SettingsChange で設定変更を reloadOnly / cacheInvalidated / updateScheduleChanged に振り分けて即時反映。バナー dismiss は updateCache.dismissedVersion へ永続化。キャッシュ読込失敗時は履歴 purge をスキップ。executeResult は履歴復元可能な app/directory/command のみ選択履歴に記録し、emoji/カラーピッカー/Web検索は一過性アクションとして記録しない（網羅的 switch で種別追加時の記録漏れを防ぐ）。空パス/URL 履歴が累積し正規履歴を押し出すのを防止）, GlobalShortcutManager（Carbon ホットキー C コールバックとショートカット変更通知は `Task { @MainActor in }` で確実に MainActor へディスパッチ）, MenuBarActions（キャッシュ再構築は onRebuildCache コールバックで AppCoordinator.rebuildCacheAndReload に委譲）, CacheBootstrap（スキャン完了は onScanCompleted で全アプリ一覧ごと通知し、起動時・自動更新・手動再構築すべてで ViewModel 再読込を一本化。アプリとディレクトリの保存は CacheDatabase.saveAppsAndDirectories で 1 つのトランザクションに束ねており、片方だけ成功して片方が失敗した瞬間に「新世代の apps + 旧世代の directories」という不整合キャッシュが残るのを防ぐ。事前 clearCache はせず、スキャン失敗時は既存キャッシュを保持。DB 保存失敗時は ViewModel への完了通知を抑止し false を返すことで、スキャン結果と古いキャッシュの不整合が「成功」として伝搬するのを防止。lastScanDate は「最後にキャッシュ更新が成功した時刻」を意味するため defer 内では更新せず、保存成功後にのみ更新する（失敗時にも更新するとメニュー表示で「直前に成功した」かのように振る舞ってしまう）。startAutoUpdate は冒頭で必ず stop して設定変更を反映。runScan は isScanning ガードで再入防止）, PerformanceMonitor
    Data/                   # CacheDatabase (GRDB), SettingsManager, SelectionHistory（CacheDatabaseProtocol は保存・読み込みの両方を公開し、AppCoordinator は具象 CacheDatabase に依存せずキャッシュを ViewModel へ反映。saveApps/saveDirectories は単体置換用、CacheBootstrap のスキャン経路では saveAppsAndDirectories(apps:directories:) を必ず使い、両テーブルを 1 つの SQLite トランザクションで置換して世代不整合を防ぐ。設定JSON破損時はバックアップ復旧、バックアップ作成失敗は warning ログを残してデフォルト復元を継続、I/Oエラーは呼び出し側へ伝播。SettingsManager.updateSettings は設定変更と保存を一体化し、保存失敗時はメモリ上の設定も変更前へ戻して未保存値との不整合を防ぐ。カスタムコマンド履歴は command://UUID 識別子で管理。purgeInvalidPaths は allowlist 方式で、validPaths（アプリ/ディレクトリのパス + command://UUID）に含まれないエントリと空パス・Web検索URLを起動時に削除）
    Models/                 # AppItem, DirectoryItem, EditorType, TerminalType, EditorInfo, TerminalInfo
    Services/               # SearchService（空クエリ履歴は使用回数+最終利用日時で優先し、同 count・同 lastUsed・同名の場合は path で tie-break して Dictionary 反復順による非決定的な並びを防止。選択履歴のキーワードは記録時・比較時とも SearchQueryNormalizer で正規化し、大文字/全角/前後空白でも履歴ブーストが効く。applyHistoryBoost は入口で履歴を正規化済みタプル配列にキャッシュし、結果 R 件 × 履歴 H 件の述語内で keyword を再正規化しない。fuseScore は Fuse の内部 lowercased（isCaseSensitive=false デフォルト）と重複するため外側で text.lowercased() を呼ばない）, LaunchService（カスタムコマンド履歴は command://UUID 識別子で管理。Web検索特殊アクションのクエリ値は `&` / `=` / `+` 等を値としてパーセントエンコード。実行ディレクトリはシェルエスケープし、`cd --` でハイフン始まりディレクトリがオプションと誤認されるのを防ぐ。.command スクリプトは `cd -- ... || exit 1` で作業ディレクトリ消失時に別 cwd でのコマンド実行を防止（AppleScript 経路の `&&` と同等）。Terminal/iTerm2/Ghostty/cmuxはAppleScript。Ghostty 1.3.1 / cmux 0.64.20 で `new window` + `input text + \\n` を確認。Ghostty の辞書には `send key` もあるが cmux と同じく改行込みの `input text` で実行を確定し、cmux の辞書には `send key` がないため同方式が必須。executeAppleScript は osascript の stderr Pipe ハンドルを取得直後 defer で close し、AppleScript 経路でも FD リークを防止（cmux CLI 経路と同方針）。GhosttyでAppleScript失敗時は.commandへフォールバック。cmux はカスタムコマンド実行を AppleScript 優先、失敗時とディレクトリオープンは CLI / Socket API を使用（stdout/stderrを一時ファイルに分離して回収しデッドロック防止（各 FileHandle は取得直後に defer 登録しエラー時の FD リークを防止）、CLI ping は実行ファイルの存在と実行権限を確認してから 5 秒上限で待機し、無応答時は terminate して false を返し、正常終了のみ成功扱い（stdout/stderr 破棄には FileHandle.nullDevice ではなく各プロセス専用の書き込み用 /dev/null ハンドルを使う））。Warpは.command（Warp は AppleScript 辞書を取得できないため URL Scheme/Launch Configuration 方式と `.command` 実行を採る）、Terminal.appは/Systemパス優先）, AppScanner（scanApplications は async でバックグラウンド実行されメインスレッドを塞がない。ローカライズ名は per-app の mdls spawn ではなく URLResourceValues.localizedNameKey で取得。Info.plist はスキャンループ内で loadInfoPlist により 1 回だけ読み込み・パースし、除外判定・名前抽出・アイコン解決で共有してアプリ 1 件あたりの plist 二重・三重読込を排除（public な plistNames/iconFilePath/extractAppInfo は読み込み済み plist を受け取る private 版へ委譲し、既存 API と挙動を維持）。除外アプリはパス・表示名・バンドル名で照合し、isExcluded(app:excludedApps:) でスキャン後の再フィルタも可能）, DirectoryScanner（親ディレクトリは parent_search_keyword を検索名に反映。`.app` 拡張子の通常ファイルは isDirectory チェックで AppItem 登録を防止）, UpdateChecker（GitHub Releases: owayo/ignitero-launcher。安定版はAPI配列順ではなくVersionComparatorで最大バージョンを選択。VersionComparatorはプレリリース(-)/ビルドメタ(+)を除いたコア部分を0埋めで比較し、1.2.0-beta.1を1.2.1と誤認しない。await 中の dismissedVersion 変更を反映するため判定直前に最新値を再取得。updateCache の設定保存失敗は warning ログを残す。HTTPURLResponse のステータスコードを早期に検証し、200 番台以外（GitHub API のレート制限超過で返る 403 を含む）は配列ではないエラー JSON 本文を JSONDecoder に渡す前に弾いて、ステータスコードを含む warning を残す）, IMEController（TIS APIはメインスレッド実行）, CalculatorEngine（括弧付き式は再帰下降でパースするため、`(((…` のように極端に深くネストした入力（演算子を含む文字列を検索欄へ大量貼り付けすると checkForCalculatorExpression 経由で evaluate が呼ばれる）はスタックオーバーフローでアプリ全体が SIGSEGV クラッシュする。maxParenDepth=256 の深さ上限を超えたら無効な式として nil を返す。`+`/`*`/単項マイナスは既にループ化してスタック消費を抑えている）, IconCacheManager（自動更新と手動再構築の並行書き込みからファイル破損を守るため `.atomic` で書き込み。アプリ更新で .icns の中身だけ変わった場合に古いキャッシュを返さないよう、ソース mtime とキャッシュ mtime を比較してソースが新しければ再生成。ソース mtime が取得できない場合は既存キャッシュをそのまま使い無用な再生成を抑制）, EmojiKeywordSearch, HapticService
    UI/                     # LauncherPanel, LauncherView, LauncherViewModel（選択確定時は searchResults.indices で負値を含む範囲外 selectedIndex を拒否し、公開状態へ不正値が設定されても配列範囲外クラッシュを防ぐ）, WindowManager（OperationQueue.main から発火するアプリ切替通知は `Task { @MainActor in }` で確実に MainActor へディスパッチ。パネルは表示のたびに中央配置するため位置永続化は持たない）, SettingsView（ディレクトリ一覧は id: \.path と firstIndex(path:) 再検索で行を識別し、削除・並び替え時の index ずれによる誤更新/削除を防止。addDirectory は path を一意キーとして重複登録を防ぐ。ログイン時起動 Toggle は LaunchAtLoginManaging の非同期キャッシュを読み、body/getter で SMAppService.mainApp.status を同期取得しない）, SettingsViewModel（ログイン項目状態は LaunchAtLoginManaging 経由で Task.detached に逃がし、SettingsView の描画中に SMAppService の同期 I/O で UI スレッドをハングさせない。保存に成功した CRUD だけが onSettingsChanged(SettingsChange) を発火し、ランチャーへの反映漏れを防ぐ）, ShortcutRecorderSettingRow（KeyboardShortcuts.Recorder/RecorderCocoa は SwiftPM の Bundle.module へ依存し .app 配置時にクラッシュするため使用禁止。自前 NSButton で記録し、表示は必ず ShortcutDisplayFormatter 経由で行う）, ShortcutDisplayFormatter（`String(describing: shortcut)` / `KeyboardShortcuts.Shortcut.description` は SpecialKey.space の `"space_key".localized` で Bundle.module を初期化し assertionFailure を起こすため代替フォーマッタを必須化。modifier 表示順 ⌃⌥⇧⌘ と Carbon キーコード→記号マップ＋UCKeyTranslate で Bundle.module を一切踏まない）, EditorPickerPanel（確定通知は Terminal と同じ onSelect コールバック方式。ポーリング監視は廃止済み）, TerminalPickerPanel（選択確定時は terminals.indices で負値を含む範囲外 highlightedIndex を拒否する）, RadialPickerView, EmojiPickerPanel（AppCoordinator は Editor/Terminal ピッカーと同様に WindowManager.showPicker/hidePicker で isPickerVisible を管理し、表示中の Option+Space でも確実に閉じる。× ボタンによる onDismiss 未通知での状態固着を防ぐため styleMask に .closable を含めず、Escape / 絵文字選択 / Option+Space で閉じる）
  IgniteroLauncher/         # 実行可能ターゲット (@main エントリ)
    IgniteroApp.swift
Tests/
  IgniteroCoreTests/        # 1001テスト (Swift Testing)
.backup/                    # Tauri v2 旧実装 (参照用)
```

補足（2026-07-27）: Warp 0.2026.07.01.09.21.01 は `sdef /Applications/Warp.app` がエラー -192 で AppleScript 辞書を取得できないため、引き続き `.command` ファイル方式を維持する。Terminal.app 2.15 / iTerm2 3.6.11 / Ghostty 1.3.1 / cmux 0.64.20 はローカル辞書で AppleScript 対応を確認済み。

補足（2026-06-29）: LaunchService の `runCmuxPing` は macOS 26 の SwiftPM テスト環境で短命プロセスの終了検出が 1 秒を超えることがあるため、5 秒上限で待機する。`Process` の stdout/stderr 破棄には `FileHandle.nullDevice` を使わず、各プロセス専用に書き込み用 `/dev/null` ハンドルを開いて終了後に閉じる（`FileHandle.nullDevice` を stdout/stderr に渡すと子プロセス終了検出が進まず false negative になる環境がある）。

## 開発コマンド

```bash
make build        # リリースビルド（Swift 6.3.2 の optimizer クラッシュ回避で -Xswiftc -Onone を付与）
make build-debug  # デバッグビルド
make test         # テスト実行 (swift test)
make bundle       # .app バンドル作成
make install      # /Applications にインストール＆起動
make run          # ビルド後に .app を起動
make dev          # デバッグビルド＆直接実行
make verify-sign  # インストール済み .app の署名を確認
make log          # ログストリーム (com.owayo.ignitero.launcher)
make clean        # ビルドキャッシュ削除
```

### コード署名とアクセシビリティ権限

`bundle` / `dev` は `CODESIGN_IDENTITY` で署名する。この変数は「ローカルの自己署名 identity が
あればそれ、無ければ ad-hoc (`-`)」に解決されるため、証明書を持たない CI や他マシンでも
ビルドは止まらない。

ad-hoc 署名 (`codesign --sign -`) は再ビルドのたびに cdhash が変わる。macOS の TCC は
「bundle ID + 署名」の組で権限を記憶しているため、ad-hoc のままだと `make install` のたびに
別アプリ扱いになり、**アクセシビリティ権限（グローバルショートカット Option+Space に必須）が
黙って無効化される**。システム設定のチェックは入ったまま残るので「許可しているのに効かない」
という分かりにくい壊れ方をする。ローカル開発では固定 identity で署名してこれを避ける。

- 署名が ad-hoc に落ちていないかの確認: `make verify-sign`（`Authority=` があれば固定署名、
  `Signature=adhoc` なら fallback 中）
- ad-hoc から固定署名へ切り替えた直後は、**一度だけ**権限を許可し直す必要がある
  （システム設定 > プライバシーとセキュリティ > アクセシビリティ でチェックを外す → 付け直す →
  アプリ再起動。効かなければ `−` で削除してから追加し直す）
- 一時的に別 identity を使う場合は `make CODESIGN_IDENTITY="別の名前" install`
- リリース成果物（`.github/workflows/release.yml`）は配布用のため ad-hoc のままで、この仕組みの
  対象外（Gatekeeper を通すには Developer ID + notarization が別途必要）

## テスト規約

- Swift Testing フレームワーク (`import Testing`) を使用、XCTest は不使用
- テストファイルは `Tests/IgniteroCoreTests/` に配置
- `@Suite` でグループ化、`@Test` でテスト関数をマーク
- `#expect` でアサーション
- プロトコルベースの DI でモック差し替え可能 (AppScannerProtocol, CacheDatabaseProtocol, IMEControlling, Launching, LaunchAtLoginManaging, URLSessionProtocol)

## アーキテクチャ

- **MVVM**: LauncherViewModel, SettingsViewModel でUIロジックを分離
- **AppCoordinator**: 全コンポーネントを統合するメインコーディネーター
- **Protocol-based DI**: テスト容易性のためプロトコル経由で依存注入
- **@MainActor + @Observable**: SwiftUI/AppKit の状態管理
- **Sendable**: Swift 6.2 Strict Concurrency 準拠
- **@MainActor**: SettingsManager, WindowManager 等の状態管理クラスはメインアクター隔離で保護

## ライブラリ使用上の制約（クラッシュ回避ルール）

### KeyboardShortcuts（過去 2 度の設定画面クラッシュ原因）

以下の API を呼ぶと SwiftPM の `Bundle.module` 解決が `.app` 内で失敗し `assertionFailure` で SIGTRAP（設定画面を開いた瞬間にアプリ全体クラッシュ）。**いかなる呼び出しも禁止**。

- `KeyboardShortcuts.Recorder`（SwiftUI ビュー）— `record_shortcut`.localized 等
- `KeyboardShortcuts.RecorderCocoa`（NSView）— 同上
- `KeyboardShortcuts.Shortcut.description` および `String(describing: shortcut)` — `SpecialKey.space` で `"space_key".localized`
- `print(shortcut)` / `"\(shortcut)"` / Logger の `\(shortcut)` 補間 — `CustomStringConvertible` 経由で同じ

代替実装:
- ショートカット記録 UI: 自前の `ShortcutRecorderSettingRow`（`Sources/IgniteroCore/UI/`）
- ショートカット表示文字列: 自前の `ShortcutDisplayFormatter`（`Sources/IgniteroCore/UI/`）
- ログ出力: `shortcut.carbonKeyCode` / `shortcut.carbonModifiers` の数値のみを出力

呼んでよい API:
- `KeyboardShortcuts.getShortcut(for:)` / `setShortcut(_:for:)` / `reset(_:)`
- `KeyboardShortcuts.Shortcut.init(event:)` / `init(carbonKeyCode:carbonModifiers:)` / `init(_:modifiers:)`
- `Shortcut.key` / `Shortcut.modifiers` / `Shortcut.carbonKeyCode` / `Shortcut.carbonModifiers` / `Shortcut.nsMenuItemKeyEquivalent` / `Shortcut.isTakenBySystem`
- `KeyboardShortcuts.Name.toggleLauncher.initialShortcut`

回帰テスト: `Tests/IgniteroCoreTests/ShortcutDisplayFormatterTests.swift` が Option+Space を含む全特殊キー組み合わせで `Bundle.module` 経由のクラッシュが起きないことを保証する。

### EmojiKit（過去 1 度の Emoji ピッカー起動時クラッシュ原因）

以下の API を呼ぶと EmojiKit 内の `Localizable.localizedName` / `localizedText` がデフォルト引数の `Bundle.module` を解決しに行き、`.app` 配置時の SwiftPM リソースバンドル解決失敗で `assertionFailure` → SIGTRAP（Emoji ピッカーを開いた瞬間にアプリ全体クラッシュ）。**いかなる呼び出しも禁止**。

- `EmojiCategory.localizedName` / `localizedName(in:)` — 既定 `bundle: .module`
- `EmojiCategory.labelText` / `labelText(for:)` — 内部で `localizedName` を呼ぶ
- `EmojiCategory.label` / `label(for:)` — 同上
- `Emoji.GridSectionTitle(_:)` — 内部で `category.labelText(for:)` を呼ぶ
- `EmojiGrid(..., sectionTitle: { $0.view })` — デフォルト `view` は `GridSectionTitle`
- `Localizable.localizedText(for:in:)`（バンドル省略形） — 全 `Localizable` 適合型で同根

代替実装:
- カテゴリ表示名: 自前の `EmojiCategoryDisplayName`（`Sources/IgniteroCore/UI/`）
- セクションタイトル: `Text(EmojiCategoryDisplayName.text(for: params.category).uppercased())` を `sectionTitle:` クロージャで直接構築

呼んでよい API:
- `EmojiCategory.id` / `symbolIconName` / `symbolIcon` / `emojis` / `hasEmojis` / `hasEmoji(_:)`
- `EmojiCategory.smileysAndPeople` 等の standard ケース、`.persisted(_:)` / `.custom(...)`
- `Collection.standardGrid` / `standardCategories`
- `EmojiGrid` 本体（`sectionTitle:` を自前 View で渡せば安全）
- `Localizable.localizedName(in:bundle:)` / `localizedText(for:in:bundle:)` — bundle を明示すれば `.module` を踏まない

回帰テスト: `Tests/IgniteroCoreTests/EmojiCategoryDisplayNameTests.swift` が `standardGrid` 全カテゴリで `Bundle.module` を踏まずに表示名が返ることを保証する。

# currentDate
Today's date is 2026-07-06.
