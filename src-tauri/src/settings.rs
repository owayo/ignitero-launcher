use crate::types::{RegisteredDirectory, Settings};
use std::fs;
use std::path::PathBuf;
use std::sync::Mutex;

pub struct SettingsManager {
    settings: Mutex<Settings>,
    settings_path: PathBuf,
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
}
