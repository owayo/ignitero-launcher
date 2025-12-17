use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppItem {
    pub name: String,
    pub path: String,
    pub icon_path: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DirectoryItem {
    pub name: String,
    pub path: String,
    pub editor: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CustomCommand {
    pub alias: String,                     // 検索キーワード（エイリアス）
    pub command: String,                   // 実行するコマンド
    pub working_directory: Option<String>, // 実行ディレクトリ（省略時はホームディレクトリ）
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CommandItem {
    pub alias: String,
    pub command: String,
    pub working_directory: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WindowPosition {
    pub x: i32,
    pub y: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
#[serde(rename_all = "lowercase")]
pub enum OpenMode {
    #[default]
    None,
    Finder,
    Editor,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
#[serde(rename_all = "lowercase")]
pub enum TerminalType {
    #[default]
    Terminal,
    Iterm2,
    Warp,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RegisteredDirectory {
    pub path: String,

    // 親ディレクトリ自身の開き方
    #[serde(default)]
    pub parent_open_mode: OpenMode,
    pub parent_editor: Option<String>,
    pub parent_search_keyword: Option<String>, // 検索キーワード（未指定時はディレクトリ名）

    // サブディレクトリの開き方
    #[serde(default)]
    pub subdirs_open_mode: OpenMode,
    pub subdirs_editor: Option<String>,

    // .appファイルのスキャン
    #[serde(default)]
    pub scan_for_apps: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CacheUpdateSettings {
    pub update_on_startup: bool,         // 起動時に更新
    pub auto_update_enabled: bool,       // 自動更新を有効化
    pub auto_update_interval_hours: u32, // 自動更新間隔（時間）
}

impl Default for CacheUpdateSettings {
    fn default() -> Self {
        Self {
            update_on_startup: true,
            auto_update_enabled: true,
            auto_update_interval_hours: 6, // デフォルト6時間
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct UpdateCache {
    pub last_checked: Option<i64>,      // Unix timestamp
    pub latest_version: Option<String>, // 最新バージョン（例: "0.1.13"）
    pub html_url: Option<String>,       // ダウンロードページURL
    #[serde(default)]
    pub dismissed_version: Option<String>, // 却下したバージョン
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct Settings {
    pub registered_directories: Vec<RegisteredDirectory>,
    #[serde(default)]
    pub custom_commands: Vec<CustomCommand>,
    #[serde(default)]
    pub cache_update: CacheUpdateSettings,
    #[serde(default)]
    pub default_terminal: TerminalType,
    #[serde(default)]
    pub update_cache: UpdateCache,
    #[serde(default)]
    pub main_window_position: Option<WindowPosition>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_open_mode_default() {
        let mode: OpenMode = Default::default();
        assert_eq!(mode, OpenMode::None);
    }

    #[test]
    fn test_terminal_type_default() {
        let terminal: TerminalType = Default::default();
        assert_eq!(terminal, TerminalType::Terminal);
    }

    #[test]
    fn test_cache_update_settings_default() {
        let settings = CacheUpdateSettings::default();
        assert!(settings.update_on_startup);
        assert!(settings.auto_update_enabled);
        assert_eq!(settings.auto_update_interval_hours, 6);
    }

    #[test]
    fn test_update_cache_default() {
        let cache = UpdateCache::default();
        assert!(cache.last_checked.is_none());
        assert!(cache.latest_version.is_none());
        assert!(cache.html_url.is_none());
        assert!(cache.dismissed_version.is_none());
    }

    #[test]
    fn test_settings_default() {
        let settings = Settings::default();
        assert!(settings.registered_directories.is_empty());
        assert!(settings.custom_commands.is_empty());
        assert_eq!(settings.default_terminal, TerminalType::Terminal);
        assert!(settings.main_window_position.is_none());
    }

    #[test]
    fn test_app_item_serialization() {
        let app = AppItem {
            name: "Safari".to_string(),
            path: "/Applications/Safari.app".to_string(),
            icon_path: Some("/path/to/icon.png".to_string()),
        };
        let json = serde_json::to_string(&app).unwrap();
        assert!(json.contains("Safari"));
        assert!(json.contains("/Applications/Safari.app"));

        let deserialized: AppItem = serde_json::from_str(&json).unwrap();
        assert_eq!(deserialized.name, "Safari");
        assert_eq!(deserialized.path, "/Applications/Safari.app");
        assert_eq!(
            deserialized.icon_path,
            Some("/path/to/icon.png".to_string())
        );
    }

    #[test]
    fn test_directory_item_serialization() {
        let dir = DirectoryItem {
            name: "Projects".to_string(),
            path: "/Users/test/Projects".to_string(),
            editor: Some("cursor".to_string()),
        };
        let json = serde_json::to_string(&dir).unwrap();
        let deserialized: DirectoryItem = serde_json::from_str(&json).unwrap();
        assert_eq!(deserialized.name, "Projects");
        assert_eq!(deserialized.editor, Some("cursor".to_string()));
    }

    #[test]
    fn test_custom_command_serialization() {
        let cmd = CustomCommand {
            alias: "dev".to_string(),
            command: "pnpm dev".to_string(),
            working_directory: Some("/Users/test/project".to_string()),
        };
        let json = serde_json::to_string(&cmd).unwrap();
        let deserialized: CustomCommand = serde_json::from_str(&json).unwrap();
        assert_eq!(deserialized.alias, "dev");
        assert_eq!(deserialized.command, "pnpm dev");
        assert_eq!(
            deserialized.working_directory,
            Some("/Users/test/project".to_string())
        );
    }

    #[test]
    fn test_open_mode_serialization() {
        let modes = vec![OpenMode::None, OpenMode::Finder, OpenMode::Editor];
        for mode in modes {
            let json = serde_json::to_string(&mode).unwrap();
            let deserialized: OpenMode = serde_json::from_str(&json).unwrap();
            assert_eq!(deserialized, mode);
        }
    }

    #[test]
    fn test_terminal_type_serialization() {
        let terminals = vec![
            TerminalType::Terminal,
            TerminalType::Iterm2,
            TerminalType::Warp,
        ];
        for terminal in terminals {
            let json = serde_json::to_string(&terminal).unwrap();
            let deserialized: TerminalType = serde_json::from_str(&json).unwrap();
            assert_eq!(deserialized, terminal);
        }
    }

    #[test]
    fn test_registered_directory_with_defaults() {
        let json = r#"{
            "path": "/Users/test/Projects",
            "scan_for_apps": true
        }"#;
        let dir: RegisteredDirectory = serde_json::from_str(json).unwrap();
        assert_eq!(dir.path, "/Users/test/Projects");
        assert_eq!(dir.parent_open_mode, OpenMode::None);
        assert_eq!(dir.subdirs_open_mode, OpenMode::None);
        assert!(dir.scan_for_apps);
        assert!(dir.parent_editor.is_none());
        assert!(dir.subdirs_editor.is_none());
    }

    #[test]
    fn test_window_position() {
        let pos = WindowPosition { x: 100, y: 200 };
        let json = serde_json::to_string(&pos).unwrap();
        let deserialized: WindowPosition = serde_json::from_str(&json).unwrap();
        assert_eq!(deserialized.x, 100);
        assert_eq!(deserialized.y, 200);
    }

    #[test]
    fn test_command_item_without_working_directory() {
        let cmd = CommandItem {
            alias: "build".to_string(),
            command: "pnpm build".to_string(),
            working_directory: None,
        };
        let json = serde_json::to_string(&cmd).unwrap();
        assert!(json.contains("build"));
        let deserialized: CommandItem = serde_json::from_str(&json).unwrap();
        assert!(deserialized.working_directory.is_none());
    }

    #[test]
    fn test_app_item_without_icon() {
        let app = AppItem {
            name: "TestApp".to_string(),
            path: "/Applications/TestApp.app".to_string(),
            icon_path: None,
        };
        let json = serde_json::to_string(&app).unwrap();
        let deserialized: AppItem = serde_json::from_str(&json).unwrap();
        assert!(deserialized.icon_path.is_none());
    }
}
