//! macOS ウィンドウ角丸マスク適用モジュール
//!
//! macOS 26 (Tahoe) の Liquid Glass デザイン変更による角丸アーティファクト問題を修正する。
//! CALayer の masksToBounds を使用してコンテンツを角丸でクリップする。

/// CSS border-radius: 12px と一致する角丸半径
pub const CORNER_RADIUS: f64 = 12.0;

/// macOS バージョン種別
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MacOSVersion {
    /// macOS 26 (Tahoe) 以降
    Tahoe,
    /// macOS 25 以前
    PreTahoe,
    /// バージョン検出失敗
    Unknown,
}

/// macOS バージョンを検出する
///
/// # Returns
/// - `MacOSVersion::Tahoe` - macOS 26 以降
/// - `MacOSVersion::PreTahoe` - macOS 25 以前
/// - `MacOSVersion::Unknown` - 検出失敗時
#[cfg(target_os = "macos")]
pub fn detect_macos_version() -> MacOSVersion {
    use std::process::Command;

    // sw_vers コマンドで macOS バージョンを取得
    let output = match Command::new("sw_vers").arg("-productVersion").output() {
        Ok(output) => output,
        Err(e) => {
            eprintln!("[window_corners] Failed to execute sw_vers: {}", e);
            return MacOSVersion::Unknown;
        }
    };

    if !output.status.success() {
        eprintln!("[window_corners] sw_vers command failed");
        return MacOSVersion::Unknown;
    }

    let version_str = match String::from_utf8(output.stdout) {
        Ok(s) => s.trim().to_string(),
        Err(e) => {
            eprintln!("[window_corners] Failed to parse sw_vers output: {}", e);
            return MacOSVersion::Unknown;
        }
    };

    // バージョン文字列をパース (例: "26.0" or "15.2.1")
    let major_version = match version_str.split('.').next() {
        Some(major) => match major.parse::<u32>() {
            Ok(v) => v,
            Err(e) => {
                eprintln!(
                    "[window_corners] Failed to parse major version '{}': {}",
                    major, e
                );
                return MacOSVersion::Unknown;
            }
        },
        None => {
            eprintln!("[window_corners] Invalid version format: {}", version_str);
            return MacOSVersion::Unknown;
        }
    };

    println!(
        "[window_corners] Detected macOS version: {} (major: {})",
        version_str, major_version
    );

    // macOS 26 (Tahoe) 以降かどうかを判定
    if major_version >= 26 {
        MacOSVersion::Tahoe
    } else {
        MacOSVersion::PreTahoe
    }
}

/// macOS 以外の OS では Unknown を返す
#[cfg(not(target_os = "macos"))]
pub fn detect_macos_version() -> MacOSVersion {
    MacOSVersion::Unknown
}

/// CALayer を使用してウィンドウに角丸マスクを適用する
///
/// contentView の CALayer に cornerRadius と masksToBounds を設定し、
/// コンテンツを角丸でクリップする。これにより macOS 26 (Tahoe) の
/// Liquid Glass デザインでも黒い三角形アーティファクトが発生しない。
///
/// # Arguments
/// * `window` - 角丸を適用する Tauri WebviewWindow
///
/// # Returns
/// * `Ok(())` - 適用成功
/// * `Err(String)` - 適用失敗（アプリは継続動作）
#[cfg(target_os = "macos")]
#[allow(deprecated)]
pub fn apply_window_corners(window: &tauri::WebviewWindow) -> Result<(), String> {
    use cocoa::base::{id, nil, YES};
    use cocoa::foundation::NSString;
    use objc::runtime::{Class, Object, BOOL};
    use objc::{msg_send, sel, sel_impl};

    let version = detect_macos_version();
    println!(
        "[window_corners] Applying CALayer corner mask (radius: {}) for {:?}",
        CORNER_RADIUS, version
    );

    unsafe {
        // Tauri ウィンドウから NSWindow を取得
        let ns_window_ptr = window
            .ns_window()
            .map_err(|e| format!("Failed to get NSWindow: {}", e))?;
        let ns_window: *mut Object = ns_window_ptr as *mut Object;

        // ウィンドウを透明に設定
        let _: () = msg_send![ns_window, setOpaque: false as BOOL];

        // 背景色をクリアに設定
        let ns_color_class = Class::get("NSColor").ok_or("NSColor class not found")?;
        let clear_color: id = msg_send![ns_color_class, clearColor];
        let _: () = msg_send![ns_window, setBackgroundColor: clear_color];

        // contentView を取得
        let content_view: id = msg_send![ns_window, contentView];
        if content_view == nil {
            return Err("[window_corners] contentView is nil".to_string());
        }

        // wantsLayer = YES を設定して layer-backed view にする
        let _: () = msg_send![content_view, setWantsLayer: YES];

        // layer を取得
        let layer: id = msg_send![content_view, layer];
        if layer == nil {
            return Err("[window_corners] layer is nil".to_string());
        }

        // cornerRadius を設定
        let _: () = msg_send![layer, setCornerRadius: CORNER_RADIUS];

        // masksToBounds = YES でコンテンツをクリップ
        let _: () = msg_send![layer, setMasksToBounds: YES];

        // macOS 26+ では cornerCurve を continuous に設定（Liquid Glass スタイル）
        if version == MacOSVersion::Tahoe {
            // kCACornerCurveContinuous = "continuous"
            let continuous_str = NSString::alloc(nil).init_str("continuous");
            let _: () = msg_send![layer, setCornerCurve: continuous_str];
            println!("[window_corners] Set cornerCurve to continuous for Tahoe");
        }

        println!(
            "[window_corners] Successfully applied CALayer corner mask (radius: {})",
            CORNER_RADIUS
        );
    }

    Ok(())
}

/// macOS 以外の OS では何もしない
#[cfg(not(target_os = "macos"))]
pub fn apply_window_corners(_window: &tauri::WebviewWindow) -> Result<(), String> {
    println!("[window_corners] Not on macOS, skipping corner application");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_corner_radius_matches_css() {
        // CSS border-radius: 12px と一致することを確認
        assert_eq!(CORNER_RADIUS, 12.0);
    }

    #[test]
    fn test_macos_version_enum_equality() {
        // enum の等価性テスト
        assert_eq!(MacOSVersion::Tahoe, MacOSVersion::Tahoe);
        assert_eq!(MacOSVersion::PreTahoe, MacOSVersion::PreTahoe);
        assert_eq!(MacOSVersion::Unknown, MacOSVersion::Unknown);
        assert_ne!(MacOSVersion::Tahoe, MacOSVersion::PreTahoe);
    }

    #[test]
    fn test_macos_version_enum_debug() {
        // Debug trait が実装されていることを確認
        let tahoe = format!("{:?}", MacOSVersion::Tahoe);
        let pre_tahoe = format!("{:?}", MacOSVersion::PreTahoe);
        let unknown = format!("{:?}", MacOSVersion::Unknown);

        assert!(tahoe.contains("Tahoe"));
        assert!(pre_tahoe.contains("PreTahoe"));
        assert!(unknown.contains("Unknown"));
    }

    #[test]
    fn test_macos_version_clone() {
        // Clone trait が実装されていることを確認
        let original = MacOSVersion::Tahoe;
        let cloned = original.clone();
        assert_eq!(original, cloned);
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn test_detect_macos_version_returns_valid_value() {
        // macOS 環境では Unknown 以外の値が返ることを確認
        // (実際の macOS バージョンによって Tahoe または PreTahoe が返る)
        let version = detect_macos_version();
        // 現在の環境は macOS なので、Unknown でなければ成功
        // 注: 実際の環境が Tahoe 未満なら PreTahoe が返る
        assert!(
            version == MacOSVersion::Tahoe || version == MacOSVersion::PreTahoe,
            "Expected Tahoe or PreTahoe on macOS, got {:?}",
            version
        );
    }

    #[cfg(not(target_os = "macos"))]
    #[test]
    fn test_detect_macos_version_returns_unknown_on_non_macos() {
        // macOS 以外では Unknown が返ることを確認
        let version = detect_macos_version();
        assert_eq!(version, MacOSVersion::Unknown);
    }
}
