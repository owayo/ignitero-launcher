use std::path::{Path, PathBuf};
use std::process::Command;

pub struct IconConverter {
    cache_dir: PathBuf,
}

impl IconConverter {
    pub fn new() -> Result<Self, String> {
        // キャッシュディレクトリを作成
        let home = std::env::var("HOME").map_err(|e| format!("Failed to get HOME: {}", e))?;
        let cache_dir = PathBuf::from(home).join(".cache/ignitero/icons");

        std::fs::create_dir_all(&cache_dir)
            .map_err(|e| format!("Failed to create cache directory: {}", e))?;

        Ok(IconConverter { cache_dir })
    }

    /// .icnsファイルをPNGに変換してキャッシュする
    pub fn convert_icns_to_png(&self, icns_path: &str) -> Result<String, String> {
        let icns_path_buf = Path::new(icns_path);

        // icnsファイルが存在するか確認
        if !icns_path_buf.exists() {
            return Err(format!("Icon file does not exist: {}", icns_path));
        }

        // キャッシュファイル名を生成（パスのハッシュを使用）
        let hash = self.hash_path(icns_path);
        let png_path = self.cache_dir.join(format!("{}.png", hash));

        // すでにキャッシュが存在する場合はそれを返す
        if png_path.exists() {
            return Ok(png_path.to_string_lossy().to_string());
        }

        // sipsコマンドを使用してPNGに変換
        let output = Command::new("sips")
            .arg("-s")
            .arg("format")
            .arg("png")
            .arg(icns_path)
            .arg("--out")
            .arg(&png_path)
            .output()
            .map_err(|e| format!("Failed to run sips command: {}", e))?;

        if !output.status.success() {
            return Err(format!(
                "sips conversion failed: {}",
                String::from_utf8_lossy(&output.stderr)
            ));
        }

        Ok(png_path.to_string_lossy().to_string())
    }

    /// パスのシンプルなハッシュを生成
    fn hash_path(&self, path: &str) -> String {
        use std::collections::hash_map::DefaultHasher;
        use std::hash::{Hash, Hasher};

        let mut hasher = DefaultHasher::new();
        path.hash(&mut hasher);
        format!("{:x}", hasher.finish())
    }

    /// アイコンキャッシュディレクトリ内のすべてのPNGファイルを削除
    pub fn clear_cache(&self) -> Result<usize, String> {
        let mut deleted_count = 0;

        if !self.cache_dir.exists() {
            return Ok(0);
        }

        let entries = std::fs::read_dir(&self.cache_dir)
            .map_err(|e| format!("Failed to read cache directory: {}", e))?;

        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().and_then(|s| s.to_str()) == Some("png")
                && std::fs::remove_file(&path).is_ok()
            {
                deleted_count += 1;
            }
        }

        Ok(deleted_count)
    }

    /// テスト用: カスタムキャッシュディレクトリでIconConverterを作成
    #[cfg(test)]
    pub fn with_cache_dir(cache_dir: PathBuf) -> Result<Self, String> {
        std::fs::create_dir_all(&cache_dir)
            .map_err(|e| format!("Failed to create cache directory: {}", e))?;
        Ok(IconConverter { cache_dir })
    }

    /// テスト用: hash_pathを公開
    #[cfg(test)]
    pub fn test_hash_path(&self, path: &str) -> String {
        self.hash_path(path)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs::{self, File};
    use std::io::Write;
    use tempfile::TempDir;

    #[test]
    fn test_hash_path_consistency() {
        let temp_dir = TempDir::new().unwrap();
        let converter = IconConverter::with_cache_dir(temp_dir.path().to_path_buf()).unwrap();

        let path = "/Applications/Safari.app/Contents/Resources/AppIcon.icns";
        let hash1 = converter.test_hash_path(path);
        let hash2 = converter.test_hash_path(path);

        assert_eq!(hash1, hash2, "Same path should produce same hash");
    }

    #[test]
    fn test_hash_path_different_for_different_paths() {
        let temp_dir = TempDir::new().unwrap();
        let converter = IconConverter::with_cache_dir(temp_dir.path().to_path_buf()).unwrap();

        let hash1 = converter.test_hash_path("/path/to/icon1.icns");
        let hash2 = converter.test_hash_path("/path/to/icon2.icns");

        assert_ne!(
            hash1, hash2,
            "Different paths should produce different hashes"
        );
    }

    #[test]
    fn test_hash_path_is_hex() {
        let temp_dir = TempDir::new().unwrap();
        let converter = IconConverter::with_cache_dir(temp_dir.path().to_path_buf()).unwrap();

        let hash = converter.test_hash_path("/some/path/icon.icns");

        assert!(
            hash.chars().all(|c| c.is_ascii_hexdigit()),
            "Hash should be hexadecimal"
        );
    }

    #[test]
    fn test_with_cache_dir_creates_directory() {
        let temp_dir = TempDir::new().unwrap();
        let cache_path = temp_dir.path().join("test_cache");

        assert!(!cache_path.exists());

        let _converter = IconConverter::with_cache_dir(cache_path.clone()).unwrap();

        assert!(cache_path.exists());
    }

    #[test]
    fn test_convert_icns_to_png_nonexistent_file() {
        let temp_dir = TempDir::new().unwrap();
        let converter = IconConverter::with_cache_dir(temp_dir.path().to_path_buf()).unwrap();

        let result = converter.convert_icns_to_png("/nonexistent/path/icon.icns");

        assert!(result.is_err());
        assert!(result.unwrap_err().contains("does not exist"));
    }

    #[test]
    fn test_clear_cache_empty_directory() {
        let temp_dir = TempDir::new().unwrap();
        let converter = IconConverter::with_cache_dir(temp_dir.path().to_path_buf()).unwrap();

        let deleted = converter.clear_cache().unwrap();

        assert_eq!(deleted, 0);
    }

    #[test]
    fn test_clear_cache_with_png_files() {
        let temp_dir = TempDir::new().unwrap();
        let converter = IconConverter::with_cache_dir(temp_dir.path().to_path_buf()).unwrap();

        // Create test PNG files
        for i in 0..3 {
            let png_path = temp_dir.path().join(format!("test{}.png", i));
            File::create(&png_path)
                .unwrap()
                .write_all(b"fake png")
                .unwrap();
        }

        let deleted = converter.clear_cache().unwrap();

        assert_eq!(deleted, 3);
    }

    #[test]
    fn test_clear_cache_ignores_non_png_files() {
        let temp_dir = TempDir::new().unwrap();
        let converter = IconConverter::with_cache_dir(temp_dir.path().to_path_buf()).unwrap();

        // Create mixed files
        File::create(temp_dir.path().join("test.png"))
            .unwrap()
            .write_all(b"fake png")
            .unwrap();
        File::create(temp_dir.path().join("test.txt"))
            .unwrap()
            .write_all(b"text file")
            .unwrap();
        File::create(temp_dir.path().join("test.icns"))
            .unwrap()
            .write_all(b"fake icns")
            .unwrap();

        let deleted = converter.clear_cache().unwrap();

        assert_eq!(deleted, 1, "Should only delete PNG files");

        // Verify non-PNG files still exist
        assert!(temp_dir.path().join("test.txt").exists());
        assert!(temp_dir.path().join("test.icns").exists());
    }

    #[test]
    fn test_clear_cache_nonexistent_directory() {
        let temp_dir = TempDir::new().unwrap();
        let cache_path = temp_dir.path().join("cache");
        let converter = IconConverter::with_cache_dir(cache_path.clone()).unwrap();

        // Remove the directory
        fs::remove_dir(&cache_path).unwrap();

        let deleted = converter.clear_cache().unwrap();

        assert_eq!(deleted, 0);
    }
}
