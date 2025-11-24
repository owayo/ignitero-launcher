use std::sync::atomic::{AtomicBool, AtomicU8, Ordering};

#[cfg(target_os = "macos")]
use serde::{Deserialize, Serialize};
#[cfg(target_os = "macos")]
use std::fs;
#[cfg(target_os = "macos")]
use std::path::PathBuf;
#[cfg(target_os = "macos")]
use std::sync::Mutex;
#[cfg(target_os = "macos")]
use std::time::{SystemTime, UNIX_EPOCH};

// 権限チェックの状態をキャッシュ
static PERMISSION_CHECKED: AtomicBool = AtomicBool::new(false);
static PERMISSION_GRANTED: AtomicBool = AtomicBool::new(false);
static PROMPT_SHOWN: AtomicU8 = AtomicU8::new(0);

#[cfg(target_os = "macos")]
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
struct AccessibilityPermissionCache {
    granted: bool,
    #[serde(default)]
    last_checked: Option<i64>,
}

// 永続化された権限チェックのキャッシュ
#[cfg(target_os = "macos")]
static PERMISSION_CACHE: Mutex<Option<AccessibilityPermissionCache>> = Mutex::new(None);

#[cfg(target_os = "macos")]
fn get_cache_file_path() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| String::from("/tmp"));
    PathBuf::from(home)
        .join(".config")
        .join("ignitero-launcher")
        .join("accessibility.json")
}

#[cfg(target_os = "macos")]
fn load_cached_permission() -> Option<AccessibilityPermissionCache> {
    // メモリ上のキャッシュがあればそれを返す
    if let Some(cache) = PERMISSION_CACHE.lock().unwrap().clone() {
        return Some(cache);
    }

    let path = get_cache_file_path();
    if let Ok(content) = fs::read_to_string(&path) {
        if let Ok(cache) = serde_json::from_str::<AccessibilityPermissionCache>(&content) {
            *PERMISSION_CACHE.lock().unwrap() = Some(cache.clone());
            return Some(cache);
        }
    }

    None
}

#[cfg(target_os = "macos")]
fn persist_permission_state(granted: bool) {
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .ok()
        .map(|d| d.as_secs() as i64);

    let cache = AccessibilityPermissionCache {
        granted,
        last_checked: timestamp,
    };

    {
        *PERMISSION_CACHE.lock().unwrap() = Some(cache.clone());
    }

    let path = get_cache_file_path();
    if let Some(parent) = path.parent() {
        if let Err(e) = fs::create_dir_all(parent) {
            eprintln!("Failed to create accessibility cache dir: {}", e);
            return;
        }
    }

    match serde_json::to_string_pretty(&cache) {
        Ok(content) => {
            if let Err(e) = fs::write(&path, content) {
                eprintln!("Failed to persist accessibility cache: {}", e);
            }
        }
        Err(e) => eprintln!("Failed to serialize accessibility cache: {}", e),
    }
}

/// アクセシビリティ権限をチェックして、必要なら要求する（初回のみ）
#[cfg(target_os = "macos")]
pub fn check_and_request_accessibility() -> bool {
    use core_foundation::base::TCFType;
    use core_foundation::boolean::CFBoolean;
    use core_foundation::dictionary::CFDictionary;
    use core_foundation::string::CFString;

    // キャッシュされた結果をチェック
    if PERMISSION_CHECKED.load(Ordering::Relaxed) {
        return PERMISSION_GRANTED.load(Ordering::Relaxed);
    }

    // 永続化されたキャッシュを読み込んで、直近でチェックしているかを確認
    let cached_permission = load_cached_permission();
    let recently_checked = cached_permission
        .as_ref()
        .and_then(|cache| cache.last_checked)
        .and_then(|last_checked| {
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .ok()
                .map(|now| now.as_secs() as i64 - last_checked)
        })
        .map(|elapsed| elapsed < 300) // 5分以内のチェック結果があれば再プロンプトを抑止
        .unwrap_or(false);

    unsafe {
        #[link(name = "ApplicationServices", kind = "framework")]
        extern "C" {
            fn AXIsProcessTrusted() -> bool;
            fn AXIsProcessTrustedWithOptions(
                options: core_foundation::dictionary::CFDictionaryRef,
            ) -> bool;
        }

        // まず権限をチェック
        if AXIsProcessTrusted() {
            println!("✓ Accessibility permission already granted");
            PERMISSION_CHECKED.store(true, Ordering::Relaxed);
            PERMISSION_GRANTED.store(true, Ordering::Relaxed);
            persist_permission_state(true);
            return true;
        }

        // 権限がない場合はプロンプト表示の頻度を制御する
        // 権限がない場合、初回のみプロンプトを表示
        let prompt_count = PROMPT_SHOWN.fetch_add(1, Ordering::Relaxed);

        if prompt_count == 0 && !recently_checked {
            // 初回のみプロンプトを表示
            println!("⚠ Accessibility permission not granted, requesting...");

            let prompt_key = CFString::new("AXTrustedCheckOptionPrompt");
            let prompt_value = CFBoolean::true_value();

            let options = CFDictionary::from_CFType_pairs(&[(
                prompt_key.as_CFType(),
                prompt_value.as_CFType(),
            )]);

            let is_trusted = AXIsProcessTrustedWithOptions(options.as_concrete_TypeRef());

            if is_trusted {
                println!("✓ Accessibility permission granted");
                PERMISSION_CHECKED.store(true, Ordering::Relaxed);
                PERMISSION_GRANTED.store(true, Ordering::Relaxed);
                persist_permission_state(true);
            } else {
                println!("⚠ Accessibility permission denied. Please grant permission in System Settings > Privacy & Security > Accessibility");
                PERMISSION_CHECKED.store(true, Ordering::Relaxed);
                PERMISSION_GRANTED.store(false, Ordering::Relaxed);
                persist_permission_state(false);
            }

            is_trusted
        } else {
            // 2回目以降はプロンプトなしでチェックのみ
            let is_trusted = AXIsProcessTrusted();
            PERMISSION_CHECKED.store(true, Ordering::Relaxed);
            PERMISSION_GRANTED.store(is_trusted, Ordering::Relaxed);
            persist_permission_state(is_trusted);
            is_trusted
        }
    }
}

/// 英数キーをシミュレートしてIMEを英字入力に切り替える
#[cfg(target_os = "macos")]
fn simulate_eisu_key() -> Result<(), String> {
    // まずアクセシビリティ権限をチェック
    if !check_and_request_accessibility() {
        return Err("Accessibility permission required. Please grant permission in System Settings > Privacy & Security > Accessibility, then restart the app.".to_string());
    }

    unsafe {
        // Core Graphics Framework関数の宣言
        type CGEventRef = *mut std::ffi::c_void;
        type CGEventSourceRef = *mut std::ffi::c_void;

        #[repr(u32)]
        #[allow(dead_code)]
        enum CGEventType {
            KeyDown = 10,
            KeyUp = 11,
        }

        #[link(name = "CoreGraphics", kind = "framework")]
        extern "C" {
            fn CGEventSourceCreate(state_id: i32) -> CGEventSourceRef;
            fn CGEventCreateKeyboardEvent(
                source: CGEventSourceRef,
                virtual_key: u16,
                key_down: bool,
            ) -> CGEventRef;
            fn CGEventPost(tap: u32, event: CGEventRef);
            fn CFRelease(cf: *const std::ffi::c_void);
        }

        // 英数キーのキーコード (kVK_JIS_Eisu)
        const VK_JIS_EISU: u16 = 102;

        // イベントソースを作成
        let event_source = CGEventSourceCreate(1); // kCGEventSourceStateHIDSystemState
        if event_source.is_null() {
            return Err("Failed to create event source".to_string());
        }

        // 英数キーの押下イベントを作成
        let key_down_event = CGEventCreateKeyboardEvent(event_source, VK_JIS_EISU, true);
        if key_down_event.is_null() {
            CFRelease(event_source);
            return Err("Failed to create key down event".to_string());
        }

        // 英数キーの解放イベントを作成
        let key_up_event = CGEventCreateKeyboardEvent(event_source, VK_JIS_EISU, false);
        if key_up_event.is_null() {
            CFRelease(key_down_event);
            CFRelease(event_source);
            return Err("Failed to create key up event".to_string());
        }

        // イベントを送信（押下→解放）
        CGEventPost(0, key_down_event); // kCGHIDEventTap
        CGEventPost(0, key_up_event);

        // リソースを解放
        CFRelease(key_up_event);
        CFRelease(key_down_event);
        CFRelease(event_source);

        println!("✓ Simulated EISU key press");
        Ok(())
    }
}

#[cfg(target_os = "macos")]
pub fn force_english_input() -> Result<(), String> {
    simulate_eisu_key()
}

#[cfg(not(target_os = "macos"))]
#[command]
pub fn force_english_input() -> Result<(), String> {
    // macOS以外では何もしない
    Ok(())
}
