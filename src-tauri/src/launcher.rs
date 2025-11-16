use crate::types::TerminalType;
use std::fs;
use std::path::Path;
use std::process::Command;

pub struct Launcher;

impl Launcher {
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
                // WindsurfのバンドルIDを取得して開く
                Self::open_with_app_bundle("Windsurf", target_path)?;
            }
            Some("cursor") => {
                // ディレクトリ直下の.code-workspaceファイルを検索
                let workspace_file = Self::find_workspace_file(&path_buf);
                let target_path = workspace_file.as_ref().unwrap_or(&path_buf);
                // CursorのバンドルIDを取得して開く
                Self::open_with_app_bundle("Cursor", target_path)?;
            }
            Some("code") | Some("vscode") => {
                // ディレクトリ直下の.code-workspaceファイルを検索
                let workspace_file = Self::find_workspace_file(&path_buf);
                let target_path = workspace_file.as_ref().unwrap_or(&path_buf);
                // VS CodeのバンドルIDを取得して開く
                Self::open_with_app_bundle("Visual Studio Code", target_path)?;
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

    /// アプリケーションバンドルIDを使用してディレクトリを開く
    fn open_with_app_bundle(app_name: &str, path: &Path) -> Result<(), String> {
        // osascriptでアプリのバンドルIDを取得
        let bundle_id_output = Command::new("osascript")
            .arg("-e")
            .arg(format!("id of app \"{}\"", app_name))
            .output()
            .map_err(|e| format!("Failed to get bundle ID for {}: {}", app_name, e))?;

        if !bundle_id_output.status.success() {
            return Err(format!(
                "Failed to get bundle ID for {}: {}",
                app_name,
                String::from_utf8_lossy(&bundle_id_output.stderr)
            ));
        }

        let bundle_id = String::from_utf8_lossy(&bundle_id_output.stdout)
            .trim()
            .to_string();

        // open -n -b で開く
        Command::new("open")
            .arg("-n") // 新しいインスタンスを開く
            .arg("-b") // バンドルIDを指定
            .arg(&bundle_id)
            .arg("--args") // 引数を渡す
            .arg(path)
            .spawn()
            .map_err(|e| format!("Failed to open with {}: {}", app_name, e))?;

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
        }

        Ok(())
    }
}
