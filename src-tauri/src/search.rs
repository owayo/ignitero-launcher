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
