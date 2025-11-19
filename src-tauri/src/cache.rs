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
                last_updated INTEGER NOT NULL
            )",
            [],
        )?;

        // アプリ名の検索用インデックス
        self.conn
            .execute("CREATE INDEX IF NOT EXISTS idx_apps_name ON apps(name)", [])?;

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
                "INSERT INTO apps (name, path, icon_path, last_updated) VALUES (?, ?, ?, ?)",
                params![app.name, app.path, app.icon_path, now],
            )?;
        }

        tx.commit()?;
        Ok(())
    }

    /// キャッシュからアプリを読み込み
    pub fn load_apps(&self) -> Result<Vec<AppItem>> {
        let mut stmt = self
            .conn
            .prepare("SELECT name, path, icon_path FROM apps ORDER BY name")?;

        let apps = stmt
            .query_map([], |row| {
                Ok(AppItem {
                    name: row.get(0)?,
                    path: row.get(1)?,
                    icon_path: row.get(2)?,
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
