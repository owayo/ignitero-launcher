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
