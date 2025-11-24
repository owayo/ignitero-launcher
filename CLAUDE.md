# Ignitero Launcher

macOS向けの高速アプリケーション・ディレクトリランチャー。Tauri v2で構築されたメニューバー常駐型のランチャーです。

## プロジェクト概要

Ignitero Launcherは、macOS向けの軽量で高速なアプリケーションランチャーです。以下の機能を提供します：

- **/Applications配下のアプリケーション**をインクリメンタル検索で起動
- **柔軟なディレクトリ管理**: ディレクトリ自身や配下のディレクトリをFinder/エディタで開く
- **エディタ・ターミナル自動検出**: インストール済みのもののみを選択肢に表示
- **カスタム検索キーワード**: ディレクトリを任意のキーワードで検索可能
- **ターミナル統合**: →キーでディレクトリをターミナルで開く
- **Option+Spaceのグローバルホットキー**で検索窓を呼び出し
- **自動IME制御**: 権限チェックのキャッシュ化により快適な操作
- **メニューバー常駐**でバックグラウンド動作

## 必須コマンド

```bash
# 開発
pnpm install         # 依存関係のインストール
pnpm tauri dev       # 開発モードで実行

# ビルド
pnpm tauri:build     # プロダクションビルド
# これは実行します: pnpm fmt && pnpm tauri:fmt && tauri build

# コードフォーマット
pnpm fmt             # フロントエンドコード（Prettier）
pnpm tauri:fmt       # Rustコード（cargo fmt）

# テスト
cd src-tauri && cargo test  # Rustテスト
```

## アーキテクチャ概要

### バックエンド（Rust/Tauri）

- **`app_scanner.rs`** - /Applicationsと~/Applications配下のアプリケーションをスキャン
- **`directory_scanner.rs`** - 指定ディレクトリ配下をスキャン
- **`launcher.rs`** - アプリケーション起動、エディタ起動、ターミナル起動機能
  - **`get_available_editors()`**: インストール済みエディタの自動検出
  - **`get_available_terminals()`**: インストール済みターミナルの自動検出
- **`search.rs`** - fuzzy-matcherを使用したインクリメンタル検索エンジン
- **`cache.rs`** - SQLiteを使用したアプリケーション情報のキャッシュ管理
- **`icon_converter.rs`** - macOSアプリアイコンのPNG変換とキャッシュ
- **`ime_control.rs`** - IME（日本語入力）の制御と英字入力モードへの自動切り替え
  - アクセシビリティ権限チェックのキャッシュ化
- **`system_tray.rs`** - メニューバー統合とコンテキストメニュー
- **`settings.rs`** - ディレクトリ設定とエディタマッピングの永続化
- **`types.rs`** - アプリケーション情報とディレクトリ情報の型定義
- **`main.rs`** - アプリケーションエントリーポイントとグローバルホットキー管理

### フロントエンド（React/TypeScript）

- React + TypeScript + Ant Design UI
- TauriのIPCコマンドでバックエンドと通信
- 検索UI、設定管理、結果表示のコンポーネント

### 主要な設計パターン

1. **インクリメンタル検索**:
   - ユーザー入力に応じてリアルタイムでフィルタリング
   - fuzzy-matcherによる柔軟な検索
   - キーボードナビゲーション（`↑` `↓`、`Enter`）
     - useRefベースの選択項目自動スクロール
     - behavior: 'auto'で即座にスクロール（パフォーマンス最適化）
   - 自動IME制御による英字入力モードへの切り替え
     - アクセシビリティ権限チェックのキャッシュ化（繰り返しプロンプトの抑制）

2. **キャッシュ管理**:
   - SQLiteによるアプリケーション情報の永続化
   - アプリアイコンのPNG変換とキャッシュ
   - 高速な起動と検索応答

3. **柔軟なディレクトリ設定管理**:
   - 親ディレクトリ自身の開き方（none / finder / editor）
   - 配下のディレクトリの開き方（none / finder / editor）
   - カスタム検索キーワードの設定
   - ディレクトリごとに異なるエディタを設定可能
   - 設定の永続化（JSON）
   - **エディタ・ターミナル自動検出**:
     - `/Applications`と`~/Applications`の両方をスキャン
     - インストール済みのもののみを選択肢に表示
     - 対応エディタ: Antigravity, Cursor, VS Code, Windsurf
     - 対応ターミナル: Terminal（常に利用可能）, iTerm2, Warp

4. **ターミナル統合**:
   - デフォルトターミナルの設定（macOS Terminal / iTerm2 / Warp）
   - `→`キーでディレクトリをターミナルで開く
   - インストール済みターミナルの自動検出

5. **グローバルホットキー**:
   - `Option` + `Space`でウィンドウを表示/非表示
   - システムワイドで動作
   - フォーカス管理と自動IME制御

6. **メニューバー統合**:
   - ウィンドウを閉じても終了しない
   - メニューバーアイコンのメニューから設定や終了が可能
   - バックグラウンドで常駐

## 重要な実装詳細

### アプリケーション検索
- /Applications配下を再帰的にスキャン
- .appバンドルの情報を抽出（名前、アイコン、パス）
- SQLiteキャッシュによる高速検索
- アイコンをPNGに変換してキャッシュ（~/.cache/ignitero/icons/）
- 起動時とメニューからの手動再スキャン

### ディレクトリ検索
- **親ディレクトリ自身**:
  - `parent_open_mode`: none / finder / editor
  - `parent_search_keyword`: カスタム検索キーワード（未指定時はディレクトリ名）
  - `parent_editor`: エディタ選択（Antigravity / Windsurf / Cursor / VS Code）
- **配下のディレクトリ**:
  - `subdirs_open_mode`: none / finder / editor
  - `subdirs_editor`: エディタ選択（Antigravity / Windsurf / Cursor / VS Code）
- **エディタ自動検出**:
  - `Launcher::get_available_editors()`: インストール済みエディタを取得
  - `/Applications`と`~/Applications`の両方をチェック
  - インストール済みのエディタのみが選択肢に表示される
  - 対応エディタ: Antigravity, Cursor, VS Code, Windsurf
- **ターミナル自動検出**:
  - `Launcher::get_available_terminals()`: インストール済みターミナルを取得
  - Terminal（macOS標準）は常に利用可能
  - iTerm2, Warpはインストール時のみ表示
- **エディタ起動方式**:
  - `open -a "App Name" <path>`でシンプルに起動
  - .code-workspaceファイルがあればそれを優先的に開く（エディタの場合のみ）
  - macOSのLaunchServicesがアプリケーション名からバンドルを自動解決
- **ターミナル起動**:
  - `open -a Terminal/iTerm/Warp <path>`でターミナルを開く
  - `→`キーで起動

### 自動IME制御
- ウィンドウ表示時に自動的に英字入力モードへ切り替え
- Core Graphics FrameworkのCGEventによる英数キー（キーコード102）シミュレーション
- アクセシビリティ権限チェックとユーザーへの権限要求
- **権限チェックのキャッシュ化**:
  - 初回チェック後の結果をキャッシュ（静的変数）
  - 2回目以降は繰り返しプロンプトを表示しない
  - パフォーマンス向上とUX改善
- macOSの「書類ごとの自動切り替え」に対応した150ms遅延処理
- メインスレッド保証による確実な実行

**必要な権限**:
- システム設定 → プライバシーとセキュリティ → アクセシビリティ
- 権限がない場合は自動的に要求ダイアログを表示

### ホットキー動作
- `Option` + `Space`: ウィンドウ表示/非表示切り替え
- ウィンドウ表示時に自動的にフォーカス
- 検索フィールドにフォーカスを移動（100ms遅延）
- 英字入力モードに自動切り替え（150ms遅延）

### キーボードナビゲーション
- `↑` `↓`キーで項目選択
- `Enter`キーで起動
- `→`キーでディレクトリをターミナルで開く
- `Escape`キーでウィンドウを閉じる
- 選択項目の自動スクロール（useRefベースの実装）
- scrollIntoView APIによる最小限のスクロール（block: 'nearest'）
- パフォーマンス重視（behavior: 'auto'）

### ウィンドウ管理
- 検索ウィンドウサイズ: 600x500
- 常に前面表示（alwaysOnTop）
- 透明度とシャドウでモダンな見た目
- window-vibrancyによるmacOS標準のぼかし効果

### UI/UX改善
- ツールチップ付きアイコンボタン（キャッシュ更新・設定）
- キャッシュ更新ボタンを検索画面に配置
- マウスオーバー効果なしのシンプルなボタンデザイン
- エディタアイコンのIPCキャッシュによるパフォーマンス最適化

## Tauri固有の注意事項

- Ant DesignをUIコンポーネントに使用
- Tauri v2のパターンでフロントエンド-バックエンド通信
- `productName`に日本語文字を使用しない（tauri.conf.json）
- `identifier`: `com.owayo.ignitero.launcher`（macOSバンドルID）
- 必要な権限: `core:tray:default`, `shell:default`, `global-shortcut:default`

## 技術スタック

- **フロントエンド**: React 18、TypeScript、Vite、Ant Design
- **バックエンド**: Rust、Tauri v2
- **検索**: fuzzy-matcher（Rustファジーマッチング）
- **IME制御**: Core Graphics Framework（CGEvent）
- **キャッシュ**: rusqlite（SQLite）
- **アイコン処理**: core-foundation、plist
- **UI効果**: window-vibrancy（macOSぼかし効果）
- **ホットキー**: Tauri global-shortcut plugin
- **統合機能**: エディタ・ターミナル自動検出と起動
- **パッケージマネージャ**: pnpm

## 主要な型定義

### RegisteredDirectory
```typescript
{
  path: string;
  parent_open_mode: 'none' | 'finder' | 'editor';
  parent_editor?: string;
  parent_search_keyword?: string;
  subdirs_open_mode: 'none' | 'finder' | 'editor';
  subdirs_editor?: string;
  scan_for_apps: boolean;
}
```

### Settings
```typescript
{
  registered_directories: RegisteredDirectory[];
  cache_update: CacheUpdateSettings;
  default_terminal: 'terminal' | 'iterm2' | 'warp';
}
```
