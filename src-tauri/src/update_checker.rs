use crate::settings::SettingsManager;
use serde::Deserialize;
use std::time::{SystemTime, UNIX_EPOCH};

const GITHUB_API_URL: &str = "https://api.github.com/repos/owayo/ignitero-launcher/releases/latest";
const CACHE_DURATION_HOURS: i64 = 12; // 12時間キャッシュ

#[derive(Debug, Deserialize)]
struct GithubRelease {
    tag_name: String,
    html_url: String,
    #[serde(default)]
    prerelease: bool,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct UpdateInfo {
    pub has_update: bool,
    pub current_version: String,
    pub latest_version: Option<String>,
    pub html_url: Option<String>,
}

pub async fn check_for_updates(
    settings_manager: &SettingsManager,
    app_version: String,
    force: bool,
) -> Result<UpdateInfo, String> {
    // キャッシュをチェック
    if !force {
        let cache = settings_manager.get_update_cache();
        if let Some(last_checked) = cache.last_checked {
            let now = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_secs() as i64;

            // システムクロックの逆行を検出
            if now < last_checked {
                eprintln!(
                    "Warning: System clock moved backwards (now: {}, cached: {}). Invalidating cache.",
                    now, last_checked
                );
            } else {
                let elapsed_hours = (now - last_checked) / 3600;

                if elapsed_hours < CACHE_DURATION_HOURS {
                    // キャッシュが有効 - セマンティックバージョニングで比較
                    let has_update = if let Some(ref latest) = cache.latest_version {
                        // ユーザーが却下したバージョンと同じ場合は通知しない
                        let is_dismissed = cache.dismissed_version.as_ref() == Some(latest);
                        !is_dismissed && compare_versions(&app_version, latest)
                    } else {
                        false
                    };

                    return Ok(UpdateInfo {
                        has_update,
                        current_version: app_version,
                        latest_version: cache.latest_version,
                        html_url: cache.html_url,
                    });
                }
            }
        }
    }

    // GitHub APIからリリース情報を取得
    let client = reqwest::Client::builder()
        .user_agent("ignitero-launcher")
        .timeout(std::time::Duration::from_secs(10))
        .build()
        .map_err(|e| format!("Failed to create HTTP client: {}", e))?;

    let response = client
        .get(GITHUB_API_URL)
        .send()
        .await
        .map_err(|e| format!("Failed to fetch release info: {}", e))?;

    if !response.status().is_success() {
        return Err(format!("GitHub API returned error: {}", response.status()));
    }

    let release: GithubRelease = response
        .json()
        .await
        .map_err(|e| format!("Failed to parse release info: {}", e))?;

    // プレリリースは無視
    if release.prerelease {
        return Ok(UpdateInfo {
            has_update: false,
            current_version: app_version,
            latest_version: None,
            html_url: None,
        });
    }

    // バージョンの正規化（"v0.1.13" -> "0.1.13"）
    let latest_version = release.tag_name.trim_start_matches('v').to_string();

    // URLバリデーション - セキュリティのため
    if !release
        .html_url
        .starts_with("https://github.com/owayo/ignitero-launcher")
    {
        return Err(format!(
            "Invalid release URL: {}. Expected URL from owayo/ignitero-launcher repository.",
            release.html_url
        ));
    }

    // バージョン比較
    let has_update = compare_versions(&app_version, &latest_version);

    // キャッシュを更新
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs() as i64;

    if let Err(e) = settings_manager.save_update_cache(
        Some(now),
        Some(latest_version.clone()),
        Some(release.html_url.clone()),
    ) {
        eprintln!("Warning: Failed to save update cache: {}", e);
    }

    Ok(UpdateInfo {
        has_update,
        current_version: app_version,
        latest_version: Some(latest_version),
        html_url: Some(release.html_url),
    })
}

fn compare_versions(current: &str, latest: &str) -> bool {
    // セマンティックバージョニングの簡易比較
    // 例: "0.1.13" < "0.2.0"
    let current_parts: Vec<u32> = current.split('.').filter_map(|s| s.parse().ok()).collect();
    let latest_parts: Vec<u32> = latest.split('.').filter_map(|s| s.parse().ok()).collect();

    for i in 0..3 {
        let c = current_parts.get(i).unwrap_or(&0);
        let l = latest_parts.get(i).unwrap_or(&0);
        if l > c {
            return true;
        } else if l < c {
            return false;
        }
    }

    false
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_compare_versions() {
        assert!(!compare_versions("0.1.13", "0.1.13"));
        assert!(compare_versions("0.1.13", "0.1.14"));
        assert!(compare_versions("0.1.13", "0.2.0"));
        assert!(compare_versions("0.1.13", "1.0.0"));
        assert!(!compare_versions("0.2.0", "0.1.13"));
    }
}
