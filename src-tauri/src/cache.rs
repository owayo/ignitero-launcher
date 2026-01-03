use crate::types::{AppItem, DirectoryItem};
use rusqlite::{params, Connection, Result};
use std::path::PathBuf;

pub struct CacheDB {
    conn: Connection,
}

impl CacheDB {
    pub fn new() -> Result<Self> {
        let db_path = Self::get_db_path();

        // ディレクトリを作成
        if let Some(parent) = db_path.parent() {
            std::fs::create_dir_all(parent).ok();
        }

        let conn = Connection::open(db_path)?;

        let cache = Self { conn };
        cache.init_tables()?;

        Ok(cache)
    }

    /// テスト用：インメモリデータベースを作成
    pub fn new_in_memory() -> Result<Self> {
        let conn = Connection::open_in_memory()?;
        let cache = Self { conn };
        cache.init_tables()?;
        Ok(cache)
    }

    fn get_db_path() -> PathBuf {
        let home = std::env::var("HOME").unwrap_or_else(|_| String::from("/tmp"));
        PathBuf::from(home)
            .join(".config")
            .join("ignitero-launcher")
            .join("cache.db")
    }

    fn init_tables(&self) -> Result<()> {
        // アプリテーブル
        self.conn.execute(
            "CREATE TABLE IF NOT EXISTS apps (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                path TEXT NOT NULL UNIQUE,
                icon_path TEXT,
                original_name TEXT,
                last_updated INTEGER NOT NULL
            )",
            [],
        )?;

        // original_name カラムを追加（既存テーブルのマイグレーション）
        // カラムが存在しない場合のみ追加
        let _ = self
            .conn
            .execute("ALTER TABLE apps ADD COLUMN original_name TEXT", []);

        // アプリ名の検索用インデックス
        self.conn
            .execute("CREATE INDEX IF NOT EXISTS idx_apps_name ON apps(name)", [])?;

        // original_name の検索用インデックス
        self.conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_apps_original_name ON apps(original_name)",
            [],
        )?;

        // ディレクトリテーブル
        self.conn.execute(
            "CREATE TABLE IF NOT EXISTS directories (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                path TEXT NOT NULL UNIQUE,
                editor TEXT,
                last_updated INTEGER NOT NULL
            )",
            [],
        )?;

        // ディレクトリ名の検索用インデックス
        self.conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_directories_name ON directories(name)",
            [],
        )?;

        // メタデータテーブル（最終更新時刻など）
        self.conn.execute(
            "CREATE TABLE IF NOT EXISTS metadata (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            )",
            [],
        )?;

        Ok(())
    }

    /// アプリをキャッシュに保存
    pub fn save_apps(&self, apps: &[AppItem]) -> Result<()> {
        let tx = self.conn.unchecked_transaction()?;

        // 既存のアプリを削除
        tx.execute("DELETE FROM apps", [])?;

        // 新しいアプリを挿入
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs() as i64;

        for app in apps {
            tx.execute(
                "INSERT INTO apps (name, path, icon_path, original_name, last_updated) VALUES (?, ?, ?, ?, ?)",
                params![app.name, app.path, app.icon_path, app.original_name, now],
            )?;
        }

        tx.commit()?;
        Ok(())
    }

    /// キャッシュからアプリを読み込み
    pub fn load_apps(&self) -> Result<Vec<AppItem>> {
        let mut stmt = self
            .conn
            .prepare("SELECT name, path, icon_path, original_name FROM apps ORDER BY name")?;

        let apps = stmt
            .query_map([], |row| {
                Ok(AppItem {
                    name: row.get(0)?,
                    path: row.get(1)?,
                    icon_path: row.get(2)?,
                    original_name: row.get(3)?,
                })
            })?
            .collect::<Result<Vec<_>>>()?;

        Ok(apps)
    }

    /// ディレクトリをキャッシュに保存
    pub fn save_directories(&self, directories: &[DirectoryItem]) -> Result<()> {
        let tx = self.conn.unchecked_transaction()?;

        // 既存のディレクトリを削除
        tx.execute("DELETE FROM directories", [])?;

        // 新しいディレクトリを挿入
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs() as i64;

        for dir in directories {
            tx.execute(
                "INSERT INTO directories (name, path, editor, last_updated) VALUES (?, ?, ?, ?)",
                params![dir.name, dir.path, dir.editor, now],
            )?;
        }

        tx.commit()?;
        Ok(())
    }

    /// キャッシュからディレクトリを読み込み
    pub fn load_directories(&self) -> Result<Vec<DirectoryItem>> {
        let mut stmt = self
            .conn
            .prepare("SELECT name, path, editor FROM directories ORDER BY name")?;

        let directories = stmt
            .query_map([], |row| {
                Ok(DirectoryItem {
                    name: row.get(0)?,
                    path: row.get(1)?,
                    editor: row.get(2)?,
                })
            })?
            .collect::<Result<Vec<_>>>()?;

        Ok(directories)
    }

    /// キャッシュが空かどうかをチェック
    pub fn is_empty(&self) -> Result<bool> {
        let app_count: i64 = self
            .conn
            .query_row("SELECT COUNT(*) FROM apps", [], |row| row.get(0))?;

        let dir_count: i64 =
            self.conn
                .query_row("SELECT COUNT(*) FROM directories", [], |row| row.get(0))?;

        Ok(app_count == 0 && dir_count == 0)
    }

    /// 最終更新時刻を取得（UNIXタイムスタンプ）
    pub fn get_last_update_time(&self) -> Result<Option<i64>> {
        let result: Result<String> = self.conn.query_row(
            "SELECT value FROM metadata WHERE key = 'last_update_time'",
            [],
            |row| row.get(0),
        );

        match result {
            Ok(value) => Ok(Some(value.parse().unwrap_or(0))),
            Err(_) => Ok(None),
        }
    }

    /// 最終更新時刻を設定
    pub fn set_last_update_time(&self, timestamp: i64) -> Result<()> {
        self.conn.execute(
            "INSERT OR REPLACE INTO metadata (key, value) VALUES ('last_update_time', ?)",
            params![timestamp.to_string()],
        )?;
        Ok(())
    }

    /// キャッシュが更新が必要かチェック（指定時間経過しているか）
    pub fn needs_update(&self, interval_hours: u32) -> Result<bool> {
        if let Some(last_update) = self.get_last_update_time()? {
            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs() as i64;

            let interval_seconds = (interval_hours as i64) * 3600;
            Ok(now - last_update >= interval_seconds)
        } else {
            // 更新時刻が記録されていない場合は更新が必要
            Ok(true)
        }
    }

    /// キャッシュをクリア（テスト用）
    pub fn clear_cache(&self) -> Result<()> {
        self.conn.execute("DELETE FROM apps", [])?;
        self.conn.execute("DELETE FROM directories", [])?;
        self.conn.execute("DELETE FROM metadata", [])?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::{AppItem, DirectoryItem};

    #[test]
    fn test_new_in_memory() {
        let cache = CacheDB::new_in_memory().expect("Failed to create in-memory cache");
        assert!(cache.is_empty().expect("Failed to check if empty"));
    }

    #[test]
    fn test_save_and_load_apps() {
        let cache = CacheDB::new_in_memory().expect("Failed to create cache");

        let apps = vec![
            AppItem {
                name: "Safari".to_string(),
                path: "/Applications/Safari.app".to_string(),
                icon_path: None,
                original_name: None,
            },
            AppItem {
                name: "Mail".to_string(),
                path: "/Applications/Mail.app".to_string(),
                icon_path: Some("/path/to/icon.png".to_string()),
                original_name: None,
            },
        ];

        cache.save_apps(&apps).expect("Failed to save apps");
        let loaded = cache.load_apps().expect("Failed to load apps");

        assert_eq!(loaded.len(), 2);
        assert_eq!(loaded[0].name, "Mail");
        assert_eq!(loaded[1].name, "Safari");
    }

    #[test]
    fn test_save_and_load_directories() {
        let cache = CacheDB::new_in_memory().expect("Failed to create cache");

        let dirs = vec![
            DirectoryItem {
                name: "Projects".to_string(),
                path: "/Users/test/Projects".to_string(),
                editor: Some("cursor".to_string()),
            },
            DirectoryItem {
                name: "Documents".to_string(),
                path: "/Users/test/Documents".to_string(),
                editor: None,
            },
        ];

        cache
            .save_directories(&dirs)
            .expect("Failed to save directories");
        let loaded = cache
            .load_directories()
            .expect("Failed to load directories");

        assert_eq!(loaded.len(), 2);
        assert_eq!(loaded[0].name, "Documents");
        assert_eq!(loaded[1].name, "Projects");
    }

    #[test]
    fn test_is_empty() {
        let cache = CacheDB::new_in_memory().expect("Failed to create cache");

        assert!(cache.is_empty().expect("Failed to check if empty"));

        let apps = vec![AppItem {
            name: "TestApp".to_string(),
            path: "/Applications/TestApp.app".to_string(),
            icon_path: None,
            original_name: None,
        }];

        cache.save_apps(&apps).expect("Failed to save apps");
        assert!(!cache.is_empty().expect("Failed to check if empty"));

        cache.clear_cache().expect("Failed to clear cache");
        assert!(cache.is_empty().expect("Failed to check if empty"));
    }

    #[test]
    fn test_update_time_operations() {
        let cache = CacheDB::new_in_memory().expect("Failed to create cache");

        // 初期状態ではNone
        assert_eq!(
            cache.get_last_update_time().expect("Failed to get time"),
            None
        );

        // 時刻を設定
        let timestamp = 1234567890;
        cache
            .set_last_update_time(timestamp)
            .expect("Failed to set time");

        // 取得して確認
        assert_eq!(
            cache.get_last_update_time().expect("Failed to get time"),
            Some(timestamp)
        );
    }

    #[test]
    fn test_needs_update() {
        let cache = CacheDB::new_in_memory().expect("Failed to create cache");

        // 更新時刻が未設定の場合は更新が必要
        assert!(cache.needs_update(1).expect("Failed to check needs_update"));

        // 現在時刻を設定
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs() as i64;

        cache.set_last_update_time(now).expect("Failed to set time");

        // 1時間以内なら更新不要
        assert!(!cache.needs_update(1).expect("Failed to check needs_update"));

        // 過去の時刻を設定
        let old_time = now - 7200; // 2時間前
        cache
            .set_last_update_time(old_time)
            .expect("Failed to set time");

        // 1時間経過しているので更新が必要
        assert!(cache.needs_update(1).expect("Failed to check needs_update"));

        // 3時間以内なら更新不要
        assert!(!cache.needs_update(3).expect("Failed to check needs_update"));
    }

    #[test]
    fn test_overwrite_apps() {
        let cache = CacheDB::new_in_memory().expect("Failed to create cache");

        // 最初のアプリを保存
        let apps1 = vec![AppItem {
            name: "App1".to_string(),
            path: "/Applications/App1.app".to_string(),
            icon_path: None,
            original_name: None,
        }];
        cache.save_apps(&apps1).expect("Failed to save apps");

        // 上書き
        let apps2 = vec![
            AppItem {
                name: "App2".to_string(),
                path: "/Applications/App2.app".to_string(),
                icon_path: None,
                original_name: None,
            },
            AppItem {
                name: "App3".to_string(),
                path: "/Applications/App3.app".to_string(),
                icon_path: None,
                original_name: None,
            },
        ];
        cache.save_apps(&apps2).expect("Failed to save apps");

        let loaded = cache.load_apps().expect("Failed to load apps");
        assert_eq!(loaded.len(), 2);
        assert!(loaded.iter().any(|app| app.name == "App2"));
        assert!(loaded.iter().any(|app| app.name == "App3"));
        assert!(!loaded.iter().any(|app| app.name == "App1"));
    }

    #[test]
    fn test_empty_save() {
        let cache = CacheDB::new_in_memory().expect("Failed to create cache");

        // 空のリストを保存
        cache.save_apps(&[]).expect("Failed to save empty apps");
        cache
            .save_directories(&[])
            .expect("Failed to save empty directories");

        assert!(cache.is_empty().expect("Failed to check if empty"));
    }

    #[test]
    fn test_icon_path_persistence() {
        let cache = CacheDB::new_in_memory().expect("Failed to create cache");

        let apps = vec![
            AppItem {
                name: "App1".to_string(),
                path: "/Applications/App1.app".to_string(),
                icon_path: Some("/path/to/icon1.png".to_string()),
                original_name: None,
            },
            AppItem {
                name: "App2".to_string(),
                path: "/Applications/App2.app".to_string(),
                icon_path: None,
                original_name: None,
            },
        ];

        cache.save_apps(&apps).expect("Failed to save apps");
        let loaded = cache.load_apps().expect("Failed to load apps");

        assert_eq!(loaded.len(), 2);
        let app1 = loaded.iter().find(|app| app.name == "App1").unwrap();
        let app2 = loaded.iter().find(|app| app.name == "App2").unwrap();

        assert_eq!(app1.icon_path, Some("/path/to/icon1.png".to_string()));
        assert_eq!(app2.icon_path, None);
    }

    #[test]
    fn test_original_name_persistence() {
        let cache = CacheDB::new_in_memory().expect("Failed to create cache");

        let apps = vec![
            AppItem {
                name: "ターミナル".to_string(),
                path: "/Applications/Utilities/Terminal.app".to_string(),
                icon_path: None,
                original_name: Some("Terminal".to_string()),
            },
            AppItem {
                name: "Safari".to_string(),
                path: "/Applications/Safari.app".to_string(),
                icon_path: None,
                original_name: None, // 英語名と同じ場合はNone
            },
        ];

        cache.save_apps(&apps).expect("Failed to save apps");
        let loaded = cache.load_apps().expect("Failed to load apps");

        assert_eq!(loaded.len(), 2);
        let terminal = loaded
            .iter()
            .find(|app| app.path.contains("Terminal"))
            .unwrap();
        let safari = loaded
            .iter()
            .find(|app| app.path.contains("Safari"))
            .unwrap();

        assert_eq!(terminal.name, "ターミナル");
        assert_eq!(terminal.original_name, Some("Terminal".to_string()));
        assert_eq!(safari.name, "Safari");
        assert_eq!(safari.original_name, None);
    }

    #[test]
    fn test_editor_persistence() {
        let cache = CacheDB::new_in_memory().expect("Failed to create cache");

        let dirs = vec![
            DirectoryItem {
                name: "Projects".to_string(),
                path: "/Users/test/Projects".to_string(),
                editor: Some("cursor".to_string()),
            },
            DirectoryItem {
                name: "Documents".to_string(),
                path: "/Users/test/Documents".to_string(),
                editor: None,
            },
        ];

        cache
            .save_directories(&dirs)
            .expect("Failed to save directories");
        let loaded = cache
            .load_directories()
            .expect("Failed to load directories");

        assert_eq!(loaded.len(), 2);
        let projects = loaded.iter().find(|dir| dir.name == "Projects").unwrap();
        let documents = loaded.iter().find(|dir| dir.name == "Documents").unwrap();

        assert_eq!(projects.editor, Some("cursor".to_string()));
        assert_eq!(documents.editor, None);
    }
}
