use std::sync::atomic::{AtomicBool, Ordering};

// 権限チェックの状態をキャッシュ（セッション内のみ）
static PERMISSION_CHECKED: AtomicBool = AtomicBool::new(false);
static PERMISSION_GRANTED: AtomicBool = AtomicBool::new(false);

/// アクセシビリティ権限をチェックする（プロンプトなし）
#[cfg(target_os = "macos")]
pub fn check_and_request_accessibility() -> bool {
    // キャッシュされた結果をチェック
    if PERMISSION_CHECKED.load(Ordering::Relaxed) {
        return PERMISSION_GRANTED.load(Ordering::Relaxed);
    }

    unsafe {
        #[link(name = "ApplicationServices", kind = "framework")]
        extern "C" {
            fn AXIsProcessTrusted() -> bool;
        }

        // 権限をチェック（プロンプトなし）
        let is_trusted = AXIsProcessTrusted();

        if is_trusted {
            println!("✓ Accessibility permission granted");
        } else {
            println!("⚠ Accessibility permission not granted");
        }

        PERMISSION_CHECKED.store(true, Ordering::Relaxed);
        PERMISSION_GRANTED.store(is_trusted, Ordering::Relaxed);

        is_trusted
    }
}

/// 英数キーをシミュレートしてIMEを英字入力に切り替える
#[cfg(target_os = "macos")]
fn simulate_eisu_key() -> Result<(), String> {
    // まずアクセシビリティ権限をチェック
    if !check_and_request_accessibility() {
        return Err("Accessibility permission required".to_string());
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
pub fn force_english_input() -> Result<(), String> {
    // macOS以外では何もしない
    Ok(())
}
