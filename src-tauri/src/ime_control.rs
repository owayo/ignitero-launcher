#[cfg(target_os = "macos")]
pub fn force_english_input() -> Result<(), String> {
    use core_foundation::base::TCFType;
    use core_foundation::dictionary::CFDictionary;
    use core_foundation::string::CFString;

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
