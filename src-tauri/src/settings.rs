use crate::types::{CustomCommand, RegisteredDirectory, Settings, WindowPosition};
use std::fs;
use std::path::PathBuf;
use std::sync::Mutex;

pub struct SettingsManager {
    settings: Mutex<Settings>,
    settings_path: PathBuf,
}

impl Default for SettingsManager {
    fn default() -> Self {
        Self::new()
    }
}

impl SettingsManager {
    pub fn new() -> Self {
        let settings_path = Self::get_settings_path();
        let settings = Self::load_settings(&settings_path);

        Self {
            settings: Mutex::new(settings),
            settings_path,
        }
    }

    fn get_settings_path() -> PathBuf {
        let home = std::env::var("HOME").unwrap_or_else(|_| String::from("/tmp"));
        PathBuf::from(home)
            .join(".config")
            .join("ignitero-launcher")
            .join("settings.json")
    }

    fn load_settings(path: &PathBuf) -> Settings {
        if let Ok(content) = fs::read_to_string(path) {
            match serde_json::from_str(&content) {
                Ok(settings) => settings,
                Err(e) => {
                    // 設定ファイルが破損している場合、バックアップを作成
                    eprintln!("Settings file corrupted: {}", e);
                    let backup_path = path.with_extension("json.backup");
                    if let Err(backup_err) = fs::copy(path, &backup_path) {
                        eprintln!("Failed to backup corrupted settings: {}", backup_err);
                    } else {
                        eprintln!("Backed up corrupted settings to: {:?}", backup_path);
                    }
                    Settings::default()
                }
            }
        } else {
            Settings::default()
        }
    }

    pub fn get_settings(&self) -> Settings {
        self.settings.lock().unwrap().clone()
    }

    pub fn save_settings(&self, settings: Settings) -> Result<(), String> {
        // ディレクトリを作成
        if let Some(parent) = self.settings_path.parent() {
            fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }

        // 設定を保存
        let content = serde_json::to_string_pretty(&settings).map_err(|e| e.to_string())?;
        fs::write(&self.settings_path, content).map_err(|e| e.to_string())?;

        // メモリ上の設定を更新
        *self.settings.lock().unwrap() = settings;

        Ok(())
    }

    pub fn add_directory(&self, dir: RegisteredDirectory) -> Result<(), String> {
        let mut settings = self.get_settings();

        // 既に存在する場合は更新
        if let Some(existing) = settings
            .registered_directories
            .iter_mut()
            .find(|d| d.path == dir.path)
        {
            *existing = dir;
        } else {
            settings.registered_directories.push(dir);
        }

        self.save_settings(settings)
    }

    pub fn remove_directory(&self, path: &str) -> Result<(), String> {
        let mut settings = self.get_settings();
        settings.registered_directories.retain(|d| d.path != path);
        self.save_settings(settings)
    }

    pub fn get_registered_directories(&self) -> Vec<RegisteredDirectory> {
        self.get_settings().registered_directories
    }

    pub fn add_command(&self, cmd: CustomCommand) -> Result<(), String> {
        let mut settings = self.get_settings();

        // 既に存在する場合は更新
        if let Some(existing) = settings
            .custom_commands
            .iter_mut()
            .find(|c| c.alias == cmd.alias)
        {
            *existing = cmd;
        } else {
            settings.custom_commands.push(cmd);
        }

        self.save_settings(settings)
    }

    pub fn remove_command(&self, alias: &str) -> Result<(), String> {
        let mut settings = self.get_settings();
        settings.custom_commands.retain(|c| c.alias != alias);
        self.save_settings(settings)
    }

    pub fn get_custom_commands(&self) -> Vec<CustomCommand> {
        self.get_settings().custom_commands
    }

    pub fn get_update_cache(&self) -> crate::types::UpdateCache {
        self.get_settings().update_cache
    }

    pub fn save_update_cache(
        &self,
        last_checked: Option<i64>,
        latest_version: Option<String>,
        html_url: Option<String>,
    ) -> Result<(), String> {
        // mutexを保持したまま更新して競合を防ぐ
        let mut settings_guard = self.settings.lock().unwrap();
        let dismissed_version = settings_guard.update_cache.dismissed_version.clone();
        settings_guard.update_cache = crate::types::UpdateCache {
            last_checked,
            latest_version,
            html_url,
            dismissed_version,
        };

        // ディレクトリを作成
        if let Some(parent) = self.settings_path.parent() {
            fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }

        // 設定を保存
        let content = serde_json::to_string_pretty(&*settings_guard).map_err(|e| e.to_string())?;
        fs::write(&self.settings_path, content).map_err(|e| e.to_string())?;

        Ok(())
    }

    pub fn dismiss_update(&self, version: String) -> Result<(), String> {
        // mutexを保持したまま更新
        let mut settings_guard = self.settings.lock().unwrap();
        settings_guard.update_cache.dismissed_version = Some(version);

        // ディレクトリを作成
        if let Some(parent) = self.settings_path.parent() {
            fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }

        // 設定を保存
        let content = serde_json::to_string_pretty(&*settings_guard).map_err(|e| e.to_string())?;
        fs::write(&self.settings_path, content).map_err(|e| e.to_string())?;

        Ok(())
    }

    pub fn save_main_window_position(&self, position: WindowPosition) -> Result<(), String> {
        let mut settings = self.get_settings();
        settings.main_window_position = Some(position);
        self.save_settings(settings)
    }

    /// テスト用：カスタムパスでSettingsManagerを作成
    #[cfg(test)]
    pub fn new_with_path(settings_path: PathBuf) -> Self {
        let settings = Self::load_settings(&settings_path);
        Self {
            settings: Mutex::new(settings),
            settings_path,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::{CacheUpdateSettings, OpenMode, TerminalType};
    use tempfile::TempDir;

    #[test]
    fn test_new_settings_manager() {
        // テスト用の一時ファイルを使用
        let temp_dir = TempDir::new().expect("Failed to create temp dir");
        let settings_path = temp_dir.path().join("settings.json");
        let manager = SettingsManager::new_with_path(settings_path);
        let settings = manager.get_settings();

        // デフォルト設定が読み込まれる
        assert_eq!(settings.registered_directories.len(), 0);
        assert_eq!(settings.default_terminal, TerminalType::Terminal);
    }

    #[test]
    fn test_add_directory() {
        let temp_dir = TempDir::new().expect("Failed to create temp dir");
        let settings_path = temp_dir.path().join("settings.json");
        let manager = SettingsManager::new_with_path(settings_path);

        let dir = RegisteredDirectory {
            path: "/Users/test/Projects".to_string(),
            parent_open_mode: OpenMode::Editor,
            parent_editor: Some("cursor".to_string()),
            parent_search_keyword: Some("proj".to_string()),
            subdirs_open_mode: OpenMode::Finder,
            subdirs_editor: None,
            scan_for_apps: false,
        };

        manager
            .add_directory(dir.clone())
            .expect("Failed to add directory");

        let settings = manager.get_settings();
        assert_eq!(settings.registered_directories.len(), 1);
        assert_eq!(
            settings.registered_directories[0].path,
            "/Users/test/Projects"
        );
        assert_eq!(
            settings.registered_directories[0].parent_editor,
            Some("cursor".to_string())
        );
    }

    #[test]
    fn test_update_existing_directory() {
        let temp_dir = TempDir::new().expect("Failed to create temp dir");
        let settings_path = temp_dir.path().join("settings.json");
        let manager = SettingsManager::new_with_path(settings_path);

        // 最初のディレクトリを追加
        let dir1 = RegisteredDirectory {
            path: "/Users/test/Projects".to_string(),
            parent_open_mode: OpenMode::Finder,
            parent_editor: None,
            parent_search_keyword: None,
            subdirs_open_mode: OpenMode::None,
            subdirs_editor: None,
            scan_for_apps: false,
        };
        manager
            .add_directory(dir1)
            .expect("Failed to add directory");

        // 同じパスで異なる設定を追加（更新）
        let dir2 = RegisteredDirectory {
            path: "/Users/test/Projects".to_string(),
            parent_open_mode: OpenMode::Editor,
            parent_editor: Some("cursor".to_string()),
            parent_search_keyword: Some("proj".to_string()),
            subdirs_open_mode: OpenMode::Finder,
            subdirs_editor: None,
            scan_for_apps: true,
        };
        manager
            .add_directory(dir2)
            .expect("Failed to update directory");

        let settings = manager.get_settings();
        assert_eq!(settings.registered_directories.len(), 1);
        assert_eq!(
            settings.registered_directories[0].parent_open_mode,
            OpenMode::Editor
        );
        assert_eq!(settings.registered_directories[0].scan_for_apps, true);
    }

    #[test]
    fn test_remove_directory() {
        let temp_dir = TempDir::new().expect("Failed to create temp dir");
        let settings_path = temp_dir.path().join("settings.json");
        let manager = SettingsManager::new_with_path(settings_path);

        // ディレクトリを追加
        let dir1 = RegisteredDirectory {
            path: "/Users/test/Projects".to_string(),
            parent_open_mode: OpenMode::Finder,
            parent_editor: None,
            parent_search_keyword: None,
            subdirs_open_mode: OpenMode::None,
            subdirs_editor: None,
            scan_for_apps: false,
        };
        let dir2 = RegisteredDirectory {
            path: "/Users/test/Documents".to_string(),
            parent_open_mode: OpenMode::Finder,
            parent_editor: None,
            parent_search_keyword: None,
            subdirs_open_mode: OpenMode::None,
            subdirs_editor: None,
            scan_for_apps: false,
        };

        manager
            .add_directory(dir1)
            .expect("Failed to add directory");
        manager
            .add_directory(dir2)
            .expect("Failed to add directory");

        assert_eq!(manager.get_settings().registered_directories.len(), 2);

        // 1つ削除
        manager
            .remove_directory("/Users/test/Projects")
            .expect("Failed to remove directory");

        let settings = manager.get_settings();
        assert_eq!(settings.registered_directories.len(), 1);
        assert_eq!(
            settings.registered_directories[0].path,
            "/Users/test/Documents"
        );
    }

    #[test]
    fn test_save_and_load_settings() {
        let temp_dir = TempDir::new().expect("Failed to create temp dir");
        let settings_path = temp_dir.path().join("settings.json");

        // 設定を保存
        {
            let manager = SettingsManager::new_with_path(settings_path.clone());
            let dir = RegisteredDirectory {
                path: "/Users/test/Projects".to_string(),
                parent_open_mode: OpenMode::Editor,
                parent_editor: Some("cursor".to_string()),
                parent_search_keyword: Some("proj".to_string()),
                subdirs_open_mode: OpenMode::Finder,
                subdirs_editor: None,
                scan_for_apps: true,
            };
            manager.add_directory(dir).expect("Failed to add directory");
        }

        // 新しいインスタンスで読み込み
        {
            let manager = SettingsManager::new_with_path(settings_path);
            let settings = manager.get_settings();

            assert_eq!(settings.registered_directories.len(), 1);
            assert_eq!(
                settings.registered_directories[0].path,
                "/Users/test/Projects"
            );
            assert_eq!(
                settings.registered_directories[0].parent_open_mode,
                OpenMode::Editor
            );
            assert_eq!(settings.registered_directories[0].scan_for_apps, true);
        }
    }

    #[test]
    fn test_update_cache_operations() {
        let temp_dir = TempDir::new().expect("Failed to create temp dir");
        let settings_path = temp_dir.path().join("settings.json");
        let manager = SettingsManager::new_with_path(settings_path);

        // 更新キャッシュを保存
        manager
            .save_update_cache(
                Some(1234567890),
                Some("0.2.0".to_string()),
                Some("https://github.com/test/test/releases/tag/v0.2.0".to_string()),
            )
            .expect("Failed to save update cache");

        let cache = manager.get_update_cache();
        assert_eq!(cache.last_checked, Some(1234567890));
        assert_eq!(cache.latest_version, Some("0.2.0".to_string()));
        assert_eq!(
            cache.html_url,
            Some("https://github.com/test/test/releases/tag/v0.2.0".to_string())
        );
    }

    #[test]
    fn test_dismiss_update() {
        let temp_dir = TempDir::new().expect("Failed to create temp dir");
        let settings_path = temp_dir.path().join("settings.json");
        let manager = SettingsManager::new_with_path(settings_path);

        // バージョンを却下
        manager
            .dismiss_update("0.2.0".to_string())
            .expect("Failed to dismiss update");

        let cache = manager.get_update_cache();
        assert_eq!(cache.dismissed_version, Some("0.2.0".to_string()));
    }

    #[test]
    fn test_cache_update_settings() {
        let temp_dir = TempDir::new().expect("Failed to create temp dir");
        let settings_path = temp_dir.path().join("settings.json");
        let manager = SettingsManager::new_with_path(settings_path);

        let mut settings = manager.get_settings();
        settings.cache_update = CacheUpdateSettings {
            update_on_startup: false,
            auto_update_enabled: true,
            auto_update_interval_hours: 12,
        };

        manager
            .save_settings(settings)
            .expect("Failed to save settings");

        let loaded = manager.get_settings();
        assert_eq!(loaded.cache_update.update_on_startup, false);
        assert_eq!(loaded.cache_update.auto_update_enabled, true);
        assert_eq!(loaded.cache_update.auto_update_interval_hours, 12);
    }

    #[test]
    fn test_default_terminal_setting() {
        let temp_dir = TempDir::new().expect("Failed to create temp dir");
        let settings_path = temp_dir.path().join("settings.json");
        let manager = SettingsManager::new_with_path(settings_path);

        let mut settings = manager.get_settings();
        settings.default_terminal = TerminalType::Iterm2;

        manager
            .save_settings(settings)
            .expect("Failed to save settings");

        let loaded = manager.get_settings();
        assert_eq!(loaded.default_terminal, TerminalType::Iterm2);
    }

    #[test]
    fn test_empty_settings() {
        let temp_dir = TempDir::new().expect("Failed to create temp dir");
        let settings_path = temp_dir.path().join("nonexistent.json");
        let manager = SettingsManager::new_with_path(settings_path);

        let settings = manager.get_settings();
        assert_eq!(settings.registered_directories.len(), 0);
        assert_eq!(settings.default_terminal, TerminalType::Terminal);
    }
}
