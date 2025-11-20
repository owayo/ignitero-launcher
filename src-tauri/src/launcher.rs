use crate::types::TerminalType;
use serde::{Deserialize, Serialize};
use std::fs;
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
        ];

        // インストール済みのエディタのみを返す
        editors.into_iter().filter(|e| e.installed).collect()
    }

    /// アプリがインストールされているかチェック
    fn is_app_installed(app_name: &str) -> bool {
        // /Applicationsと~/Applicationsの両方をチェック
        let paths = vec![
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
}
