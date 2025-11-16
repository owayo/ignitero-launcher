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

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum OpenMode {
    None,
    Finder,
    Editor,
}

impl Default for OpenMode {
    fn default() -> Self {
        OpenMode::None
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum TerminalType {
    Terminal,
    Iterm2,
    Warp,
}

impl Default for TerminalType {
    fn default() -> Self {
        TerminalType::Terminal
    }
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
pub struct Settings {
    pub registered_directories: Vec<RegisteredDirectory>,
    #[serde(default)]
    pub cache_update: CacheUpdateSettings,
    #[serde(default)]
    pub default_terminal: TerminalType,
}
