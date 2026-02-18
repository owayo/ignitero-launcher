# Ignitero Launcher

macOS向けメニューバー常駐型ランチャーアプリケーション。Tauri v2 + React + TypeScript で構築。

## 技術スタック

- **フロントエンド**: React 19, TypeScript ~5.9, Vite 7, Ant Design 6
- **バックエンド**: Rust, Tauri v2
- **テスト**: Vitest 4, Testing Library (React, jest-dom, user-event)
- **リンター/フォーマッター**: Biome, Prettier
- **パッケージマネージャ**: pnpm

## プロジェクト構造

```
src/                    # フロントエンド (React/TypeScript)
  App.tsx               # メインランチャーウィンドウ
  SettingsWindow.tsx    # 設定画面
  EditorPickerWindow.tsx # エディタ選択画面
  TerminalPickerWindow.tsx # ターミナル選択画面
  calculator.ts         # 計算式評価モジュール
  types.ts              # 型定義
  main.tsx              # メインエントリポイント
  *-main.tsx            # 各サブウィンドウのエントリポイント
  test/setup.ts         # テストセットアップ (Tauri API モック)
  *.test.ts             # テストファイル
src-tauri/              # バックエンド (Rust/Tauri)
  src/                  # Rust ソースコード
  tests/                # Rust テスト
  Cargo.toml            # Rust 依存管理
  tauri.conf.json       # Tauri 設定
```

## 開発コマンド

```bash
pnpm dev              # Vite 開発サーバー起動 (ポート 1420)
pnpm build            # tsc + vite build
pnpm test             # vitest run (フロントエンドテスト)
pnpm test:watch       # vitest (ウォッチモード)
pnpm test:coverage    # カバレッジ付きテスト
pnpm test:rust        # Rust テスト (cargo test)
pnpm test:all         # フロントエンド + Rust テスト
pnpm tauri dev        # Tauri 開発モード
pnpm tauri:build      # プロダクションビルド
pnpm fmt              # Prettier フォーマット
pnpm tauri:fmt        # Rust フォーマット
```

## テスト規約

- テストファイルは `src/` 直下に `*.test.ts` として配置
- `jsdom` 環境で実行、`globals: true` 設定済み
- `pool: 'forks'` / `singleFork: true` でプロセス分離実行、`testTimeout: 30000`
- カバレッジ: `v8` プロバイダ、`text` / `json` / `html` レポーター
- Tauri API (`@tauri-apps/api/core`, `@tauri-apps/api/event` 等) は `src/test/setup.ts` でモック済み
- `localStorage` もモック済み

## ビルド構成

- マルチエントリ: `index.html`, `settings.html`, `editor-picker.html`, `terminal-picker.html`
- 各エントリに対応する React コンポーネントとエントリポイントが存在
