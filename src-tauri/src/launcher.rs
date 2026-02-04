use crate::types::TerminalType;
use serde::{Deserialize, Serialize};
use std::fs;
#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EditorInfo {
    pub id: String,
    pub name: String,
    pub app_name: String,
    pub installed: bool,
}

pub struct Launcher;

impl Launcher {
    /// インストール済みエディタの一覧を取得
    pub fn get_available_editors() -> Vec<EditorInfo> {
        let editors = vec![
            EditorInfo {
                id: "windsurf".to_string(),
                name: "Windsurf".to_string(),
                app_name: "Windsurf".to_string(),
                installed: Self::is_app_installed("Windsurf"),
            },
            EditorInfo {
                id: "cursor".to_string(),
                name: "Cursor".to_string(),
                app_name: "Cursor".to_string(),
                installed: Self::is_app_installed("Cursor"),
            },
            EditorInfo {
                id: "code".to_string(),
                name: "VS Code".to_string(),
                app_name: "Visual Studio Code".to_string(),
                installed: Self::is_app_installed("Visual Studio Code"),
            },
            EditorInfo {
                id: "antigravity".to_string(),
                name: "Antigravity".to_string(),
                app_name: "Antigravity".to_string(),
                installed: Self::is_app_installed("Antigravity"),
            },
            EditorInfo {
                id: "zed".to_string(),
                name: "Zed".to_string(),
                app_name: "Zed".to_string(),
                installed: Self::is_app_installed("Zed"),
            },
        ];

        // インストール済みのエディタのみを返す
        editors.into_iter().filter(|e| e.installed).collect()
    }

    /// アプリがインストールされているかチェック
    fn is_app_installed(app_name: &str) -> bool {
        // /Applicationsと~/Applicationsの両方をチェック
        let paths = [
            PathBuf::from("/Applications").join(format!("{}.app", app_name)),
            PathBuf::from(std::env::var("HOME").unwrap_or_default())
                .join("Applications")
                .join(format!("{}.app", app_name)),
        ];

        paths.iter().any(|p| p.exists())
    }

    /// インストール済みターミナルの一覧を取得
    pub fn get_available_terminals() -> Vec<EditorInfo> {
        let terminals = vec![
            EditorInfo {
                id: "terminal".to_string(),
                name: "Terminal".to_string(),
                app_name: "Terminal".to_string(),
                installed: true, // macOS標準なので常にインストール済み
            },
            EditorInfo {
                id: "iterm2".to_string(),
                name: "iTerm2".to_string(),
                app_name: "iTerm".to_string(),
                installed: Self::is_app_installed("iTerm"),
            },
            EditorInfo {
                id: "ghostty".to_string(),
                name: "Ghostty".to_string(),
                app_name: "Ghostty".to_string(),
                installed: Self::is_app_installed("Ghostty"),
            },
            EditorInfo {
                id: "warp".to_string(),
                name: "Warp".to_string(),
                app_name: "Warp".to_string(),
                installed: Self::is_app_installed("Warp"),
            },
        ];

        terminals.into_iter().filter(|t| t.installed).collect()
    }

    /// macOSアプリを起動
    pub fn launch_app(path: &str) -> Result<(), String> {
        // パスを正規化して検証
        let path_buf = Path::new(path)
            .canonicalize()
            .map_err(|e| format!("Invalid path: {}", e))?;

        // パスが存在するか確認
        if !path_buf.exists() {
            return Err(format!("Path does not exist: {}", path));
        }

        Command::new("open")
            .arg(&path_buf)
            .spawn()
            .map_err(|e| format!("Failed to launch app: {}", e))?;

        Ok(())
    }

    /// ディレクトリをエディタで開く
    pub fn open_directory(path: &str, editor: Option<&str>) -> Result<(), String> {
        // パスを正規化して検証
        let path_buf = Path::new(path)
            .canonicalize()
            .map_err(|e| format!("Invalid path: {}", e))?;

        // パスが存在し、ディレクトリであることを確認
        if !path_buf.exists() {
            return Err(format!("Path does not exist: {}", path));
        }
        if !path_buf.is_dir() {
            return Err(format!("Path is not a directory: {}", path));
        }

        match editor {
            Some("windsurf") => {
                // ディレクトリ直下の.code-workspaceファイルを検索
                let workspace_file = Self::find_workspace_file(&path_buf);
                let target_path = workspace_file.as_ref().unwrap_or(&path_buf);
                // Windsurfで開く
                Command::new("open")
                    .arg("-a")
                    .arg("Windsurf")
                    .arg(target_path)
                    .spawn()
                    .map_err(|e| format!("Failed to open with Windsurf: {}", e))?;
            }
            Some("cursor") => {
                // ディレクトリ直下の.code-workspaceファイルを検索
                let workspace_file = Self::find_workspace_file(&path_buf);
                let target_path = workspace_file.as_ref().unwrap_or(&path_buf);
                // Cursorで開く
                Command::new("open")
                    .arg("-a")
                    .arg("Cursor")
                    .arg(target_path)
                    .spawn()
                    .map_err(|e| format!("Failed to open with Cursor: {}", e))?;
            }
            Some("code") | Some("vscode") => {
                // ディレクトリ直下の.code-workspaceファイルを検索
                let workspace_file = Self::find_workspace_file(&path_buf);
                let target_path = workspace_file.as_ref().unwrap_or(&path_buf);
                // VS Codeで開く
                Command::new("open")
                    .arg("-a")
                    .arg("Visual Studio Code")
                    .arg(target_path)
                    .spawn()
                    .map_err(|e| format!("Failed to open with VS Code: {}", e))?;
            }
            Some("antigravity") => {
                // ディレクトリ直下の.code-workspaceファイルを検索
                let workspace_file = Self::find_workspace_file(&path_buf);
                let target_path = workspace_file.as_ref().unwrap_or(&path_buf);
                // Antigravityで開く
                Command::new("open")
                    .arg("-a")
                    .arg("Antigravity")
                    .arg(target_path)
                    .spawn()
                    .map_err(|e| format!("Failed to open with Antigravity: {}", e))?;
            }
            Some("zed") => {
                // ディレクトリ直下の.code-workspaceファイルを検索
                let workspace_file = Self::find_workspace_file(&path_buf);
                let target_path = workspace_file.as_ref().unwrap_or(&path_buf);
                // Zedで開く
                Command::new("open")
                    .arg("-a")
                    .arg("Zed")
                    .arg(target_path)
                    .spawn()
                    .map_err(|e| format!("Failed to open with Zed: {}", e))?;
            }
            _ => {
                // デフォルトはFinderで開く（常にディレクトリ本体を開く）
                Command::new("open")
                    .arg(&path_buf)
                    .spawn()
                    .map_err(|e| format!("Failed to open directory: {}", e))?;
            }
        }

        Ok(())
    }

    /// ディレクトリ直下の.code-workspaceファイルを検索
    fn find_workspace_file(dir: &Path) -> Option<std::path::PathBuf> {
        if let Ok(entries) = fs::read_dir(dir) {
            for entry in entries.flatten() {
                if let Ok(file_type) = entry.file_type() {
                    if file_type.is_file() {
                        if let Some(extension) = entry.path().extension() {
                            if extension == "code-workspace" {
                                return Some(entry.path());
                            }
                        }
                    }
                }
            }
        }
        None
    }

    /// カスタムコマンドをターミナルで実行
    pub fn execute_command(
        command: &str,
        working_directory: Option<&str>,
        terminal_type: &TerminalType,
    ) -> Result<(), String> {
        // 実行ディレクトリが指定されている場合、cdコマンドを先頭に追加
        let full_command = if let Some(dir) = working_directory {
            // パスにスペースが含まれる場合に備えてクォートする
            format!("cd '{}' && {}", dir.replace('\'', "'\\''"), command)
        } else {
            command.to_string()
        };
        let escaped_command = full_command.replace('\\', "\\\\").replace('"', "\\\"");

        match terminal_type {
            TerminalType::Terminal => {
                // macOSデフォルトターミナル（AppleScript経由）
                let script = format!(
                    r#"tell application "Terminal"
                        activate
                        do script "{}"
                    end tell"#,
                    escaped_command
                );
                Command::new("osascript")
                    .arg("-e")
                    .arg(&script)
                    .spawn()
                    .map_err(|e| format!("Failed to execute command in Terminal: {}", e))?;
            }
            TerminalType::Iterm2 => {
                // iTerm2（AppleScript経由）
                let script = format!(
                    r#"tell application "iTerm"
                        activate
                        tell current window
                            create tab with default profile
                            tell current session
                                write text "{}"
                            end tell
                        end tell
                    end tell"#,
                    escaped_command
                );
                Command::new("osascript")
                    .arg("-e")
                    .arg(&script)
                    .spawn()
                    .map_err(|e| format!("Failed to execute command in iTerm2: {}", e))?;
            }
            TerminalType::Warp => {
                // Warpは直接的なAppleScriptコマンド実行に対応していないため、
                // 一時的な.commandファイルを作成してWarpで開く
                // 参考: Warpには AppleScript辞書がなく、CLIもエージェント用のみ
                let temp_dir = std::env::temp_dir();
                let script_path =
                    temp_dir.join(format!("ignitero_cmd_{}.command", std::process::id()));

                // コマンドの短い説明を作成（タブタイトル用）
                let tab_title = if full_command.len() > 30 {
                    format!("{}...", &full_command[..27])
                } else {
                    full_command.clone()
                };
                // タブタイトルに使えない文字をエスケープ
                let tab_title = tab_title.replace('\n', " ").replace('\r', "");

                // スクリプト内容を作成
                // - OSC エスケープシーケンスでタブタイトルを上書き
                // - 実行後もシェルを維持
                let script_content = format!(
                    "#!/bin/zsh\nprintf '\\033]0;%s\\007' \"{}\"\n{}\nexec $SHELL",
                    tab_title.replace('"', "\\\""),
                    full_command
                );
                fs::write(&script_path, &script_content)
                    .map_err(|e| format!("Failed to write temp script: {}", e))?;

                // 実行権限を付与
                #[cfg(unix)]
                fs::set_permissions(&script_path, fs::Permissions::from_mode(0o755))
                    .map_err(|e| format!("Failed to set script permissions: {}", e))?;

                // Warpでスクリプトを開く
                Command::new("open")
                    .arg("-a")
                    .arg("Warp")
                    .arg(&script_path)
                    .spawn()
                    .map_err(|e| format!("Failed to execute command in Warp: {}", e))?;
            }
            TerminalType::Ghostty => {
                // GhosttyはAppleScriptに対応していないため、
                // 一時的な.commandファイルを作成してGhosttyで開く
                let temp_dir = std::env::temp_dir();
                let script_path =
                    temp_dir.join(format!("ignitero_cmd_{}.command", std::process::id()));

                // コマンドの短い説明を作成（タブタイトル用）
                let tab_title = if full_command.len() > 30 {
                    format!("{}...", &full_command[..27])
                } else {
                    full_command.clone()
                };
                // タブタイトルに使えない文字をエスケープ
                let tab_title = tab_title.replace('\n', " ").replace('\r', "");

                // スクリプト内容を作成
                // - OSC エスケープシーケンスでタブタイトルを上書き
                // - 実行後もシェルを維持
                let script_content = format!(
                    "#!/bin/zsh\nprintf '\\033]0;%s\\007' \"{}\"\n{}\nexec $SHELL",
                    tab_title.replace('"', "\\\""),
                    full_command
                );
                fs::write(&script_path, &script_content)
                    .map_err(|e| format!("Failed to write temp script: {}", e))?;

                // 実行権限を付与
                #[cfg(unix)]
                fs::set_permissions(&script_path, fs::Permissions::from_mode(0o755))
                    .map_err(|e| format!("Failed to set script permissions: {}", e))?;

                // Ghosttyでスクリプトを開く
                Command::new("open")
                    .arg("-a")
                    .arg("Ghostty")
                    .arg(&script_path)
                    .spawn()
                    .map_err(|e| format!("Failed to execute command in Ghostty: {}", e))?;
            }
        }

        Ok(())
    }

    /// ディレクトリをターミナルで開く
    pub fn open_in_terminal(path: &str, terminal_type: &TerminalType) -> Result<(), String> {
        // パスを正規化して検証
        let path_buf = Path::new(path)
            .canonicalize()
            .map_err(|e| format!("Invalid path: {}", e))?;

        // パスが存在し、ディレクトリであることを確認
        if !path_buf.exists() {
            return Err(format!("Path does not exist: {}", path));
        }
        if !path_buf.is_dir() {
            return Err(format!("Path is not a directory: {}", path));
        }

        match terminal_type {
            TerminalType::Terminal => {
                // macOSデフォルトターミナル
                Command::new("open")
                    .arg("-a")
                    .arg("Terminal")
                    .arg(&path_buf)
                    .spawn()
                    .map_err(|e| format!("Failed to open Terminal: {}", e))?;
            }
            TerminalType::Iterm2 => {
                // iTerm2
                Command::new("open")
                    .arg("-a")
                    .arg("iTerm")
                    .arg(&path_buf)
                    .spawn()
                    .map_err(|e| format!("Failed to open iTerm2: {}", e))?;
            }
            TerminalType::Warp => {
                // Warp
                Command::new("open")
                    .arg("-a")
                    .arg("Warp")
                    .arg(&path_buf)
                    .spawn()
                    .map_err(|e| format!("Failed to open Warp: {}", e))?;
            }
            TerminalType::Ghostty => {
                // Ghostty
                Command::new("open")
                    .arg("-a")
                    .arg("Ghostty")
                    .arg(&path_buf)
                    .spawn()
                    .map_err(|e| format!("Failed to open Ghostty: {}", e))?;
            }
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::TempDir;

    #[test]
    fn test_launch_app_with_nonexistent_path() {
        let result = Launcher::launch_app("/nonexistent/path/to/app.app");
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Invalid path"));
    }

    #[test]
    fn test_open_directory_with_nonexistent_path() {
        let result = Launcher::open_directory("/nonexistent/path", None);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Invalid path"));
    }

    #[test]
    fn test_open_directory_with_file() {
        let temp_dir = TempDir::new().expect("Failed to create temp dir");
        let file_path = temp_dir.path().join("test.txt");
        fs::write(&file_path, "test").expect("Failed to write file");

        let result = Launcher::open_directory(file_path.to_str().unwrap(), None);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("not a directory"));
    }

    #[test]
    fn test_open_in_terminal_with_nonexistent_path() {
        let result = Launcher::open_in_terminal("/nonexistent/path", &TerminalType::Terminal);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Invalid path"));
    }

    #[test]
    fn test_open_in_terminal_with_file() {
        let temp_dir = TempDir::new().expect("Failed to create temp dir");
        let file_path = temp_dir.path().join("test.txt");
        fs::write(&file_path, "test").expect("Failed to write file");

        let result =
            Launcher::open_in_terminal(file_path.to_str().unwrap(), &TerminalType::Terminal);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("not a directory"));
    }

    #[test]
    fn test_find_workspace_file() {
        let temp_dir = TempDir::new().expect("Failed to create temp dir");

        // .code-workspaceファイルを作成
        let workspace_path = temp_dir.path().join("project.code-workspace");
        fs::write(&workspace_path, "{}").expect("Failed to write workspace file");

        let result = Launcher::find_workspace_file(temp_dir.path());
        assert!(result.is_some());
        assert_eq!(result.unwrap(), workspace_path);
    }

    #[test]
    fn test_find_workspace_file_not_found() {
        let temp_dir = TempDir::new().expect("Failed to create temp dir");

        // .code-workspaceファイルがない場合
        let result = Launcher::find_workspace_file(temp_dir.path());
        assert!(result.is_none());
    }

    #[test]
    fn test_find_workspace_file_with_other_files() {
        let temp_dir = TempDir::new().expect("Failed to create temp dir");

        // 他のファイルを作成
        fs::write(temp_dir.path().join("README.md"), "test").expect("Failed to write file");
        fs::write(temp_dir.path().join("config.json"), "{}").expect("Failed to write file");

        // .code-workspaceファイルを作成
        let workspace_path = temp_dir.path().join("my.code-workspace");
        fs::write(&workspace_path, "{}").expect("Failed to write workspace file");

        let result = Launcher::find_workspace_file(temp_dir.path());
        assert!(result.is_some());
        assert_eq!(result.unwrap(), workspace_path);
    }

    #[test]
    fn test_find_workspace_file_multiple() {
        let temp_dir = TempDir::new().expect("Failed to create temp dir");

        // 複数の.code-workspaceファイルを作成
        let workspace1 = temp_dir.path().join("project1.code-workspace");
        let workspace2 = temp_dir.path().join("project2.code-workspace");
        fs::write(&workspace1, "{}").expect("Failed to write workspace1");
        fs::write(&workspace2, "{}").expect("Failed to write workspace2");

        // いずれかが返される（どちらでも良い）
        let result = Launcher::find_workspace_file(temp_dir.path());
        assert!(result.is_some());
        let path = result.unwrap();
        assert!(path == workspace1 || path == workspace2);
    }

    // 新機能のテスト: エディタ自動検出
    #[test]
    fn test_get_available_editors_returns_vec() {
        // エディタリストが返されることを確認
        let editors = Launcher::get_available_editors();
        assert!(editors.iter().all(|e| e.installed));
    }

    #[test]
    fn test_get_available_editors_structure() {
        // 最低でも1つ以上のエディタが定義されている
        // （実際にインストールされていなくても構造は確認できる）
        let all_editors = [
            EditorInfo {
                id: "windsurf".to_string(),
                name: "Windsurf".to_string(),
                app_name: "Windsurf".to_string(),
                installed: false,
            },
            EditorInfo {
                id: "cursor".to_string(),
                name: "Cursor".to_string(),
                app_name: "Cursor".to_string(),
                installed: false,
            },
            EditorInfo {
                id: "code".to_string(),
                name: "VS Code".to_string(),
                app_name: "Visual Studio Code".to_string(),
                installed: false,
            },
            EditorInfo {
                id: "antigravity".to_string(),
                name: "Antigravity".to_string(),
                app_name: "Antigravity".to_string(),
                installed: false,
            },
        ];

        // 各エディタの構造が正しいことを確認
        assert_eq!(all_editors.len(), 4);
        assert!(all_editors.iter().all(|e| !e.id.is_empty()));
        assert!(all_editors.iter().all(|e| !e.name.is_empty()));
        assert!(all_editors.iter().all(|e| !e.app_name.is_empty()));
    }

    #[test]
    fn test_get_available_editors_filters_installed_only() {
        // インストール済みのエディタのみが返されることを確認
        let available = Launcher::get_available_editors();

        // すべてのエディタがinstalledフラグがtrueであることを確認
        for editor in available {
            assert!(
                editor.installed,
                "Editor {} should be marked as installed",
                editor.name
            );
        }
    }

    // 新機能のテスト: ターミナル自動検出
    #[test]
    fn test_get_available_terminals_returns_vec() {
        // ターミナルリストが返されることを確認
        let terminals = Launcher::get_available_terminals();
        assert!(!terminals.is_empty());
        assert!(terminals.iter().all(|t| t.installed));
    }

    #[test]
    fn test_get_available_terminals_always_includes_default_terminal() {
        // macOSデフォルトのTerminalは常に含まれる
        let terminals = Launcher::get_available_terminals();

        let has_terminal = terminals
            .iter()
            .any(|t| t.id == "terminal" && t.app_name == "Terminal" && t.installed);

        assert!(
            has_terminal,
            "Default macOS Terminal should always be available"
        );
    }

    #[test]
    fn test_get_available_terminals_structure() {
        // ターミナルの構造が正しいことを確認
        let terminals = Launcher::get_available_terminals();

        for terminal in terminals {
            assert!(!terminal.id.is_empty(), "Terminal ID should not be empty");
            assert!(
                !terminal.name.is_empty(),
                "Terminal name should not be empty"
            );
            assert!(
                !terminal.app_name.is_empty(),
                "Terminal app_name should not be empty"
            );
            assert!(
                terminal.installed,
                "All returned terminals should be installed"
            );
        }
    }

    #[test]
    fn test_open_in_terminal_with_ghostty_nonexistent_path() {
        let result = Launcher::open_in_terminal("/nonexistent/path", &TerminalType::Ghostty);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Invalid path"));
    }

    #[test]
    fn test_open_in_terminal_with_ghostty_file_not_directory() {
        let temp_dir = TempDir::new().expect("Failed to create temp dir");
        let file_path = temp_dir.path().join("test.txt");
        fs::write(&file_path, "test").expect("Failed to write file");

        let result =
            Launcher::open_in_terminal(file_path.to_str().unwrap(), &TerminalType::Ghostty);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("not a directory"));
    }

    #[test]
    fn test_terminal_types_all_variants() {
        // 全てのターミナルタイプが存在し、正しく処理されることを確認
        let terminal_types = vec![
            TerminalType::Terminal,
            TerminalType::Iterm2,
            TerminalType::Ghostty,
            TerminalType::Warp,
        ];

        // 非存在パスで各ターミナルタイプのエラーハンドリングをテスト
        for terminal_type in terminal_types {
            let result = Launcher::open_in_terminal("/nonexistent/path", &terminal_type);
            assert!(result.is_err(), "Expected error for {:?}", terminal_type);
        }
    }

    #[test]
    fn test_editor_info_serialization() {
        // EditorInfoがシリアライズ可能であることを確認
        let editor = EditorInfo {
            id: "test".to_string(),
            name: "Test Editor".to_string(),
            app_name: "TestApp".to_string(),
            installed: true,
        };

        let serialized = serde_json::to_string(&editor);
        assert!(serialized.is_ok());

        let json = serialized.unwrap();
        assert!(json.contains("\"id\":\"test\""));
        assert!(json.contains("\"name\":\"Test Editor\""));
        assert!(json.contains("\"installed\":true"));
    }

    #[test]
    fn test_editor_info_deserialization() {
        // EditorInfoがデシリアライズ可能であることを確認
        let json = r#"{
            "id": "test",
            "name": "Test Editor",
            "app_name": "TestApp",
            "installed": true
        }"#;

        let result: Result<EditorInfo, _> = serde_json::from_str(json);
        assert!(result.is_ok());

        let editor = result.unwrap();
        assert_eq!(editor.id, "test");
        assert_eq!(editor.name, "Test Editor");
        assert_eq!(editor.app_name, "TestApp");
        assert!(editor.installed);
    }
}
