/// アクセシビリティ権限をチェックして、必要なら要求する
#[cfg(target_os = "macos")]
pub fn check_and_request_accessibility() -> bool {
    use core_foundation::base::TCFType;
    use core_foundation::boolean::CFBoolean;
    use core_foundation::dictionary::CFDictionary;
    use core_foundation::string::CFString;

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
            return true;
        }

        // 権限がない場合、プロンプトを表示して要求
        println!("⚠ Accessibility permission not granted, requesting...");

        let prompt_key = CFString::new("AXTrustedCheckOptionPrompt");
        let prompt_value = CFBoolean::true_value();

        let options =
            CFDictionary::from_CFType_pairs(&[(prompt_key.as_CFType(), prompt_value.as_CFType())]);

        let is_trusted = AXIsProcessTrustedWithOptions(options.as_concrete_TypeRef());

        if is_trusted {
            println!("✓ Accessibility permission granted");
        } else {
            println!("⚠ Accessibility permission denied. Please grant permission in System Settings > Privacy & Security > Accessibility");
        }

        is_trusted
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
    use core_foundation::base::TCFType;
    use core_foundation::dictionary::CFDictionary;
    use core_foundation::string::CFString;

    // まずキーシミュレーションを試みる（より確実）
    if let Ok(()) = simulate_eisu_key() {
        println!("✓ IME switched using key simulation");
        return Ok(());
    }

    println!("⚠ Key simulation failed, falling back to TIS API");

    unsafe {
        // TISInputSourceRef型の定義
        type TISInputSourceRef = *const std::ffi::c_void;

        // Carbon Framework関数の宣言
        #[link(name = "Carbon", kind = "framework")]
        extern "C" {
            fn TISCreateInputSourceList(
                properties: core_foundation::dictionary::CFDictionaryRef,
                include_all_installed: core_foundation::base::Boolean,
            ) -> core_foundation::array::CFArrayRef;
            fn TISSelectInputSource(source: TISInputSourceRef) -> i32;
            fn TISGetInputSourceProperty(
                source: TISInputSourceRef,
                property_key: core_foundation::string::CFStringRef,
            ) -> *const std::ffi::c_void;
        }

        let input_source_id_key = CFString::new("kTISPropertyInputSourceID");
        let category_key = CFString::new("kTISPropertyInputSourceCategory");
        let category_value = CFString::new("TISCategoryKeyboardInputSource");
        let type_key = CFString::new("kTISPropertyInputSourceType");
        let type_value = CFString::new("TISTypeKeyboardLayout");

        // キーボードレイアウトのみを取得するフィルター
        let props = CFDictionary::from_CFType_pairs(&[
            (category_key.as_CFType(), category_value.as_CFType()),
            (type_key.as_CFType(), type_value.as_CFType()),
        ]);

        let source_list = TISCreateInputSourceList(props.as_concrete_TypeRef(), 1);

        if source_list.is_null() {
            return Err("Failed to get input source list".to_string());
        }

        let array: core_foundation::array::CFArray<TISInputSourceRef> =
            core_foundation::array::CFArray::wrap_under_create_rule(source_list);

        println!("Available input sources:");

        // まずABCレイアウトを最優先で探す（macOSデフォルト）
        for i in 0..array.len() {
            let source = *array.get(i).unwrap();
            let source_id_ptr =
                TISGetInputSourceProperty(source, input_source_id_key.as_concrete_TypeRef());

            if !source_id_ptr.is_null() {
                let source_id: CFString = CFString::wrap_under_get_rule(
                    source_id_ptr as core_foundation::string::CFStringRef,
                );
                let id_str = source_id.to_string();
                println!("  - {}", id_str);

                // ABCレイアウトを最優先で選択
                if id_str == "com.apple.keylayout.ABC" {
                    let status = TISSelectInputSource(source);
                    if status == 0 {
                        println!("✓ Successfully switched to ABC layout");
                        return Ok(());
                    }
                }
            }
        }

        // ABCが見つからない場合、USレイアウトを探す
        for i in 0..array.len() {
            let source = *array.get(i).unwrap();
            let source_id_ptr =
                TISGetInputSourceProperty(source, input_source_id_key.as_concrete_TypeRef());

            if !source_id_ptr.is_null() {
                let source_id: CFString = CFString::wrap_under_get_rule(
                    source_id_ptr as core_foundation::string::CFStringRef,
                );
                let id_str = source_id.to_string();

                if id_str == "com.apple.keylayout.US" {
                    let status = TISSelectInputSource(source);
                    if status == 0 {
                        println!("✓ Successfully switched to US layout");
                        return Ok(());
                    }
                }
            }
        }

        // 最後の手段：英語っぽいレイアウトを探す
        for i in 0..array.len() {
            let source = *array.get(i).unwrap();
            let source_id_ptr =
                TISGetInputSourceProperty(source, input_source_id_key.as_concrete_TypeRef());

            if !source_id_ptr.is_null() {
                let source_id: CFString = CFString::wrap_under_get_rule(
                    source_id_ptr as core_foundation::string::CFStringRef,
                );
                let id_str = source_id.to_string();

                // keylayoutで、日本語ではないものを選択
                if id_str.contains("keylayout")
                    && !id_str.contains("Japanese")
                    && !id_str.contains("Hiragana")
                    && !id_str.contains("Katakana")
                {
                    let status = TISSelectInputSource(source);
                    if status == 0 {
                        println!("✓ Successfully switched to: {}", id_str);
                        return Ok(());
                    }
                }
            }
        }

        Err("No suitable English keyboard layout found. Please enable 'ABC' or 'U.S.' keyboard in System Settings > Keyboard > Input Sources.".to_string())
    }
}

#[cfg(not(target_os = "macos"))]
#[command]
pub fn force_english_input() -> Result<(), String> {
    // macOS以外では何もしない
    Ok(())
}
