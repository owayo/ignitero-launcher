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
        if let Ok(home_dir) = std::env::var("HOME") {
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
        // ファイルシステム名（英語名）を original_name として保存
        let original_name = app_path.file_stem()?.to_str()?.to_string();

        let path = app_path.to_str()?.to_string();

        // Info.plistからアイコン情報を取得（オプション）
        let icon_path = Self::get_app_icon_path(app_path);

        // ローカライズ名を取得（なければファイルシステム名を使用）
        let name = Self::get_localized_name(app_path).unwrap_or_else(|| original_name.clone());

        // original_name が name と同じ場合は None にして冗長性を減らす
        let original_name = if original_name == name {
            None
        } else {
            Some(original_name)
        };

        Some(AppItem {
            name,
            path,
            icon_path,
            original_name,
        })
    }

    /// アプリのローカライズ名を取得
    fn get_localized_name(app_path: &Path) -> Option<String> {
        // まず mdls を使って Spotlight メタデータからローカライズ名を取得（最も信頼性が高い）
        if let Some(name) = Self::get_localized_name_from_mdls(app_path) {
            return Some(name);
        }

        // システムの言語設定を取得
        let langs = Self::get_preferred_languages();

        for lang in langs {
            // .lproj/InfoPlist.strings からローカライズ名を取得
            let lproj_path = app_path
                .join("Contents")
                .join("Resources")
                .join(format!("{}.lproj", lang))
                .join("InfoPlist.strings");

            if let Some(name) = Self::read_localized_name_from_strings(&lproj_path) {
                return Some(name);
            }
        }

        // Info.plist から CFBundleDisplayName または CFBundleName を取得
        let info_plist_path = app_path.join("Contents").join("Info.plist");
        if info_plist_path.exists() {
            if let Ok(plist) = Value::from_file(&info_plist_path) {
                if let Some(dict) = plist.as_dictionary() {
                    if let Some(display_name) =
                        dict.get("CFBundleDisplayName").and_then(|v| v.as_string())
                    {
                        return Some(display_name.to_string());
                    }
                    if let Some(bundle_name) = dict.get("CFBundleName").and_then(|v| v.as_string())
                    {
                        return Some(bundle_name.to_string());
                    }
                }
            }
        }

        None
    }

    /// mdls コマンドを使って Spotlight メタデータからローカライズ名を取得
    fn get_localized_name_from_mdls(app_path: &Path) -> Option<String> {
        use std::process::Command;

        let output = Command::new("mdls")
            .arg("-name")
            .arg("kMDItemDisplayName")
            .arg("-raw")
            .arg(app_path)
            .output()
            .ok()?;

        if output.status.success() {
            let name = String::from_utf8_lossy(&output.stdout).trim().to_string();
            // "(null)" や空文字列は無効
            if !name.is_empty() && name != "(null)" {
                return Some(name);
            }
        }

        None
    }

    /// InfoPlist.strings からローカライズ名を読み取る
    fn read_localized_name_from_strings(path: &Path) -> Option<String> {
        if !path.exists() {
            return None;
        }

        // .strings ファイルは plist 形式（binary または XML）の場合がある
        if let Ok(plist) = Value::from_file(path) {
            if let Some(dict) = plist.as_dictionary() {
                // CFBundleDisplayName または CFBundleName を探す
                if let Some(name) = dict.get("CFBundleDisplayName").and_then(|v| v.as_string()) {
                    return Some(name.to_string());
                }
                if let Some(name) = dict.get("CFBundleName").and_then(|v| v.as_string()) {
                    return Some(name.to_string());
                }
            }
        }

        None
    }

    /// システムの優先言語リストを取得
    fn get_preferred_languages() -> Vec<String> {
        // まず現在のロケールを確認
        let mut langs = Vec::new();

        // LANG 環境変数から言語を取得
        if let Ok(lang) = std::env::var("LANG") {
            if let Some(lang_code) = lang.split('.').next() {
                // "ja_JP" -> "ja"
                if let Some(primary) = lang_code.split('_').next() {
                    langs.push(primary.to_string());
                }
                // "ja_JP" 形式もそのまま追加（"Japanese.lproj" 対応）
                langs.push(lang_code.replace('_', "-"));
            }
        }

        // macOS 固有の言語名もサポート
        langs.extend(vec![
            "Japanese".to_string(),
            "ja".to_string(),
            "en".to_string(),
            "Base".to_string(),
        ]);

        langs
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
