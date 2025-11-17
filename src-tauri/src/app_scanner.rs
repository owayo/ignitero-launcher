use crate::types::AppItem;
use plist::Value;
use std::path::Path;
use walkdir::WalkDir;

pub struct AppScanner;

impl AppScanner {
    /// /Applicationsと~/Applications配下のアプリをスキャン
    pub fn scan_applications() -> Vec<AppItem> {
        let mut apps = Vec::new();

        // システムのApplicationsディレクトリ
        let system_app_dir = Path::new("/Applications");
        if system_app_dir.exists() {
            apps.extend(Self::scan_directory(system_app_dir, 2)); // 深さ2まで
        }

        // ユーザーのApplicationsディレクトリ
        if let Some(home_dir) = std::env::var("HOME").ok() {
            let user_app_dir = Path::new(&home_dir).join("Applications");
            if user_app_dir.exists() {
                apps.extend(Self::scan_directory(&user_app_dir, 3)); // Chrome Appsなどのため深さ3
            }
        }

        apps
    }

    /// 指定ディレクトリ配下のアプリをスキャン
    pub fn scan_directory(dir: &Path, max_depth: usize) -> Vec<AppItem> {
        let mut apps = Vec::new();

        for entry in WalkDir::new(dir)
            .max_depth(max_depth)
            .follow_links(false)
            .into_iter()
            .filter_map(|e| e.ok())
        {
            let path = entry.path();
            if path.extension().and_then(|s| s.to_str()) == Some("app") {
                if let Some(app_item) = Self::parse_app_bundle(path) {
                    apps.push(app_item);
                }
            }
        }

        apps
    }

    /// .appバンドルから情報を抽出
    fn parse_app_bundle(app_path: &Path) -> Option<AppItem> {
        let name = app_path.file_stem()?.to_str()?.to_string();

        let path = app_path.to_str()?.to_string();

        // Info.plistからアイコン情報を取得（オプション）
        let icon_path = Self::get_app_icon_path(app_path);

        Some(AppItem {
            name,
            path,
            icon_path,
        })
    }

    /// アプリのアイコンパスを取得
    pub fn get_app_icon_path(app_path: &Path) -> Option<String> {
        let info_plist_path = app_path.join("Contents").join("Info.plist");

        if !info_plist_path.exists() {
            return None;
        }

        let plist = Value::from_file(&info_plist_path).ok()?;
        let dict = plist.as_dictionary()?;

        // CFBundleIconFileキーからアイコンファイル名を取得
        let icon_file = dict
            .get("CFBundleIconFile")
            .and_then(|v| v.as_string())
            .unwrap_or("AppIcon");

        let resources_path = app_path.join("Contents").join("Resources");

        // .icns拡張子を試す
        let mut icon_path = resources_path.join(format!("{}.icns", icon_file));
        if !icon_path.exists() {
            icon_path = resources_path.join(icon_file);
        }

        if icon_path.exists() {
            icon_path.to_str().map(|s| s.to_string())
        } else {
            None
        }
    }
}
