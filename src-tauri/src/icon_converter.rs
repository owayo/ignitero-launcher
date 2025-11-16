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
}
