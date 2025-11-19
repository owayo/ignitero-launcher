use crate::types::{AppItem, DirectoryItem};
use fuzzy_matcher::skim::SkimMatcherV2;
use fuzzy_matcher::FuzzyMatcher;

/// 検索用に文字列を正規化（全角→半角、小文字化）
fn normalize_for_search(s: &str) -> String {
    s.chars()
        .map(|c| {
            // 全角英数字を半角に変換
            if c >= 'Ａ' && c <= 'Ｚ' {
                char::from_u32(c as u32 - 0xFEE0).unwrap_or(c)
            } else if c >= 'ａ' && c <= 'ｚ' {
                char::from_u32(c as u32 - 0xFEE0).unwrap_or(c)
            } else if c >= '０' && c <= '９' {
                char::from_u32(c as u32 - 0xFEE0).unwrap_or(c)
            } else {
                c
            }
        })
        .collect::<String>()
        .to_lowercase()
}

pub struct SearchEngine {
    matcher: SkimMatcherV2,
}

impl SearchEngine {
    pub fn new() -> Self {
        Self {
            matcher: SkimMatcherV2::default(),
        }
    }

    /// アプリを検索
    pub fn search_apps(&self, apps: &[AppItem], query: &str) -> Vec<AppItem> {
        if query.is_empty() {
            return Vec::new();
        }

        let normalized_query = normalize_for_search(query);

        let mut results: Vec<(i64, AppItem)> = apps
            .iter()
            .filter_map(|app| {
                let normalized_name = normalize_for_search(&app.name);
                self.matcher
                    .fuzzy_match(&normalized_name, &normalized_query)
                    .map(|score| (score, app.clone()))
            })
            .collect();

        // スコアで降順ソート
        results.sort_by(|a, b| b.0.cmp(&a.0));

        // 上位20件を返す
        results.into_iter().take(20).map(|(_, app)| app).collect()
    }

    /// ディレクトリを検索
    pub fn search_directories(&self, dirs: &[DirectoryItem], query: &str) -> Vec<DirectoryItem> {
        if query.is_empty() {
            return Vec::new();
        }

        let normalized_query = normalize_for_search(query);

        let mut results: Vec<(i64, DirectoryItem)> = dirs
            .iter()
            .filter_map(|dir| {
                let normalized_name = normalize_for_search(&dir.name);
                self.matcher
                    .fuzzy_match(&normalized_name, &normalized_query)
                    .map(|score| (score, dir.clone()))
            })
            .collect();

        // スコアで降順ソート
        results.sort_by(|a, b| b.0.cmp(&a.0));

        // 上位20件を返す
        results.into_iter().take(20).map(|(_, dir)| dir).collect()
    }
}

impl Default for SearchEngine {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_normalize_for_search() {
        // 全角英数字を半角に変換
        assert_eq!(normalize_for_search("ＡＢＣ"), "abc");
        assert_eq!(normalize_for_search("ａｂｃ"), "abc");
        assert_eq!(normalize_for_search("０１２"), "012");

        // 大文字を小文字に変換
        assert_eq!(normalize_for_search("ABC"), "abc");

        // 混在
        assert_eq!(normalize_for_search("Ａｂｃ１２３"), "abc123");
    }

    #[test]
    fn test_search_apps_empty_query() {
        let engine = SearchEngine::new();
        let apps = vec![AppItem {
            name: "Safari".to_string(),
            path: "/Applications/Safari.app".to_string(),
            icon_path: None,
        }];

        let results = engine.search_apps(&apps, "");
        assert_eq!(results.len(), 0);
    }

    #[test]
    fn test_search_apps_basic() {
        let engine = SearchEngine::new();
        let apps = vec![
            AppItem {
                name: "Safari".to_string(),
                path: "/Applications/Safari.app".to_string(),
                icon_path: None,
            },
            AppItem {
                name: "Mail".to_string(),
                path: "/Applications/Mail.app".to_string(),
                icon_path: None,
            },
        ];

        let results = engine.search_apps(&apps, "saf");
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].name, "Safari");
    }

    #[test]
    fn test_search_apps_fuzzy_match() {
        let engine = SearchEngine::new();
        let apps = vec![
            AppItem {
                name: "Safari".to_string(),
                path: "/Applications/Safari.app".to_string(),
                icon_path: None,
            },
            AppItem {
                name: "System Settings".to_string(),
                path: "/Applications/System Settings.app".to_string(),
                icon_path: None,
            },
        ];

        // "sf" should match "Safari" (fuzzy match)
        let results = engine.search_apps(&apps, "sf");
        assert!(results.iter().any(|app| app.name == "Safari"));
    }

    #[test]
    fn test_search_apps_full_width() {
        let engine = SearchEngine::new();
        let apps = vec![AppItem {
            name: "Safari".to_string(),
            path: "/Applications/Safari.app".to_string(),
            icon_path: None,
        }];

        // 全角でも検索できる
        let results = engine.search_apps(&apps, "ｓａｆ");
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].name, "Safari");
    }

    #[test]
    fn test_search_directories_empty_query() {
        let engine = SearchEngine::new();
        let dirs = vec![DirectoryItem {
            name: "Project".to_string(),
            path: "/Users/test/Project".to_string(),
            editor: None,
        }];

        let results = engine.search_directories(&dirs, "");
        assert_eq!(results.len(), 0);
    }

    #[test]
    fn test_search_directories_basic() {
        let engine = SearchEngine::new();
        let dirs = vec![
            DirectoryItem {
                name: "Project".to_string(),
                path: "/Users/test/Project".to_string(),
                editor: None,
            },
            DirectoryItem {
                name: "Documents".to_string(),
                path: "/Users/test/Documents".to_string(),
                editor: None,
            },
        ];

        let results = engine.search_directories(&dirs, "proj");
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].name, "Project");
    }

    #[test]
    fn test_search_limit_to_20() {
        let engine = SearchEngine::new();

        // 30個のアプリを作成
        let apps: Vec<AppItem> = (0..30)
            .map(|i| AppItem {
                name: format!("App{}", i),
                path: format!("/Applications/App{}.app", i),
                icon_path: None,
            })
            .collect();

        // "App"で検索すると全てマッチするが、20件に制限される
        let results = engine.search_apps(&apps, "app");
        assert_eq!(results.len(), 20);
    }
}
