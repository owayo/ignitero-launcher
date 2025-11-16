use tauri::{
    menu::{Menu, MenuItem},
    tray::{TrayIcon, TrayIconBuilder},
    Emitter, Manager,
};

pub fn setup_system_tray(app: &tauri::App) -> Result<TrayIcon, Box<dyn std::error::Error>> {
    // メニューアイテムの作成
    let show_item = MenuItem::with_id(app, "show", "ウィンドウを表示", true, None::<&str>)?;
    let refresh_cache_item = MenuItem::with_id(
        app,
        "refresh_cache",
        "キャッシュを再構築",
        true,
        None::<&str>,
    )?;
    let settings_item = MenuItem::with_id(app, "settings", "設定", true, None::<&str>)?;
    let quit_item = MenuItem::with_id(app, "quit", "終了", true, None::<&str>)?;

    // メニューの作成
    let menu = Menu::with_items(
        app,
        &[&show_item, &refresh_cache_item, &settings_item, &quit_item],
    )?;

    // トレイアイコンを作成
    let tray = TrayIconBuilder::new()
        .menu(&menu)
        .icon(app.default_window_icon().unwrap().clone())
        .on_menu_event(move |app_handle, event| {
            match event.id.as_ref() {
                "quit" => {
                    app_handle.exit(0);
                }
                "show" => {
                    if let Some(window) = app_handle.get_webview_window("main") {
                        let _ = window.show();
                        let _ = window.set_focus();
                    }
                }
                "refresh_cache" => {
                    // キャッシュ再構築をバックグラウンドで実行
                    let app_handle_clone = app_handle.clone();
                    std::thread::spawn(move || {
                        // refresh_cacheコマンドを呼び出し
                        use crate::perform_cache_refresh;
                        use crate::AppState;

                        if let Some(state) = app_handle_clone.try_state::<AppState>() {
                            println!("Refreshing cache from tray menu...");
                            let _ = perform_cache_refresh(&state);

                            // 完了通知をemitで送信
                            if let Some(window) = app_handle_clone.get_webview_window("main") {
                                let _ = window.emit("cache-refreshed", ());
                            }
                        }
                    });
                }
                "settings" => {
                    // 設定ウィンドウが既に存在する場合は表示、存在しない場合は作成
                    if let Some(window) = app_handle.get_webview_window("settings") {
                        let _ = window.show();
                        let _ = window.set_focus();
                    } else {
                        use tauri::WebviewUrl;
                        use tauri::WebviewWindowBuilder;

                        let _ = WebviewWindowBuilder::new(
                            app_handle,
                            "settings",
                            WebviewUrl::App("settings.html".into()),
                        )
                        .title("設定 - Ignitero Launcher")
                        .inner_size(800.0, 600.0)
                        .resizable(true)
                        .center()
                        .build();
                    }
                }
                _ => {}
            }
        })
        .build(app)?;

    Ok(tray)
}
