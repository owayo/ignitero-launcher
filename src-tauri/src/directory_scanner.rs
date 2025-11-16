use crate::types::DirectoryItem;
use std::fs;
use std::path::Path;

pub struct DirectoryScanner;

impl DirectoryScanner {
    /// 指定ディレクトリ配下のサブディレクトリをスキャン
    pub fn scan_subdirectories(base_path: &Path) -> Vec<DirectoryItem> {
        let mut directories = Vec::new();

        if !base_path.exists() || !base_path.is_dir() {
            return directories;
        }

        if let Ok(entries) = fs::read_dir(base_path) {
            for entry in entries.filter_map(|e| e.ok()) {
                let path = entry.path();

                if path.is_dir() {
                    // .で始まる隠しディレクトリはスキップ
                    if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                        if name.starts_with('.') {
                            continue;
                        }

                        directories.push(DirectoryItem {
                            name: name.to_string(),
                            path: path.to_string_lossy().to_string(),
                            editor: None,
                        });
                    }
                }
            }
        }

        directories
    }
}
