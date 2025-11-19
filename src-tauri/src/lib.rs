mod app_scanner;
mod cache;
mod directory_scanner;
mod icon_converter;
mod ime_control;
mod launcher;
mod search;
mod settings;
mod system_tray;
mod types;
mod update_checker;

use app_scanner::AppScanner;
use cache::CacheDB;
use directory_scanner::DirectoryScanner;
use launcher::Launcher;
use search::SearchEngine;
use settings::SettingsManager;
use std::sync::mpsc::channel;
use std::sync::Mutex;
use std::thread;
use std::time::Duration;
use system_tray::setup_system_tray;
use tauri::tray::TrayIcon;
#[cfg(target_os = "macos")]
use tauri::TitleBarStyle;
use tauri::{Manager, State};
use tauri_plugin_global_shortcut::GlobalShortcutExt;
use types::{AppItem, DirectoryItem, RegisteredDirectory, Settings};
#[cfg(target_os = "macos")]
use window_vibrancy::{apply_vibrancy, NSVisualEffectMaterial, NSVisualEffectState};

pub struct AppState {
    apps: Mutex<Vec<AppItem>>,
    directories: Mutex<Vec<DirectoryItem>>,
    search_engine: SearchEngine,
    settings_manager: SettingsManager,
    cache_db: Mutex<CacheDB>,
    tray_icon: Mutex<Option<TrayIcon>>,
}

#[tauri::command]
fn search_apps(query: String, state: State<AppState>) -> Vec<AppItem> {
    let apps = state.apps.lock().unwrap();
    state.search_engine.search_apps(&apps, &query)
}

#[tauri::command]
fn search_directories(query: String, state: State<AppState>) -> Vec<DirectoryItem> {
    let directories = state.directories.lock().unwrap();
    state.search_engine.search_directories(&directories, &query)
}

#[tauri::command]
fn launch_app(path: String) -> Result<(), String> {
    Launcher::launch_app(&path)
}

#[tauri::command]
fn open_directory(path: String, editor: Option<String>) -> Result<(), String> {
    Launcher::open_directory(&path, editor.as_deref())
}

#[tauri::command]
fn open_in_terminal(path: String, terminal_type: types::TerminalType) -> Result<(), String> {
    Launcher::open_in_terminal(&path, &terminal_type)
}

#[tauri::command]
fn hide_window(app: tauri::AppHandle) -> Result<(), String> {
    if let Some(window) = app.get_webview_window("main") {
        window.hide().map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
fn show_window(app: tauri::AppHandle) -> Result<(), String> {
    if let Some(window) = app.get_webview_window("main") {
        window.show().map_err(|e| e.to_string())?;
        window.set_focus().map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
fn force_english_input_wrapper(app: tauri::AppHandle) -> Result<(), String> {
    let (tx, rx) = channel();

    app.run_on_main_thread(move || {
        let result = ime_control::force_english_input();
        let _ = tx.send(result);
    })
    .map_err(|e| e.to_string())?;

    rx.recv().map_err(|e| e.to_string())?
}

#[tauri::command]
fn get_settings(state: State<AppState>) -> Settings {
    state.settings_manager.get_settings()
}

#[tauri::command]
fn save_settings(settings: Settings, state: State<AppState>) -> Result<(), String> {
    state.settings_manager.save_settings(settings)
}

#[tauri::command]
fn add_directory(directory: RegisteredDirectory, state: State<AppState>) -> Result<(), String> {
    state.settings_manager.add_directory(directory)?;
    refresh_directories(state)
}

#[tauri::command]
fn remove_directory(path: String, state: State<AppState>) -> Result<(), String> {
    state.settings_manager.remove_directory(&path)?;
    refresh_directories(state)
}

#[tauri::command]
fn refresh_cache(state: State<AppState>) -> Result<(), String> {
    // TODO: 将来的にはspawn_blockingで非同期化してUIをブロックしないようにする
    perform_cache_refresh(&state)
}

#[tauri::command]
fn show_folder_picker(app: tauri::AppHandle) -> Result<Option<String>, String> {
    use std::sync::{Arc, Mutex};
    use tauri_plugin_dialog::DialogExt;

    let result = Arc::new(Mutex::new(None));
    let result_clone = result.clone();

    app.dialog()
        .file()
        .set_directory("/")
        .pick_folder(move |folder_path| {
            *result_clone.lock().unwrap() = folder_path;
        });

    // コールバックの実行を待つ（簡易的な実装）
    std::thread::sleep(std::time::Duration::from_millis(100));

    let folder = result.lock().unwrap().clone();
    Ok(folder.map(|path| path.to_string()))
}

#[tauri::command]
fn get_available_editors() -> Vec<String> {
    use std::path::Path;

    let mut available = Vec::new();

    // 各エディタのアプリケーションパスをチェック
    let editors = vec![
        ("windsurf", "/Applications/Windsurf.app"),
        ("cursor", "/Applications/Cursor.app"),
        ("code", "/Applications/Visual Studio Code.app"),
        ("antigravity", "/Applications/Antigravity.app"),
    ];

    for (identifier, app_path) in editors {
        // アプリケーションが存在するかチェック
        if Path::new(app_path).exists() {
            available.push(identifier.to_string());
        }
    }

    available
}

#[tauri::command]
fn get_available_terminals() -> Vec<String> {
    use std::path::Path;

    let mut available = Vec::new();

    // macOSデフォルトターミナルは常に利用可能
    available.push("terminal".to_string());

    // 各ターミナルのアプリケーションパスをチェック
    let terminals = vec![
        ("iterm2", "/Applications/iTerm.app"),
        ("warp", "/Applications/Warp.app"),
    ];

    for (identifier, app_path) in terminals {
        // アプリケーションが存在するかチェック
        if Path::new(app_path).exists() {
            available.push(identifier.to_string());
        }
    }

    available
}

#[tauri::command]
fn convert_icon_to_png(icon_path: String) -> Result<String, String> {
    use icon_converter::IconConverter;

    let converter = IconConverter::new()?;
    converter.convert_icns_to_png(&icon_path)
}

#[tauri::command]
fn get_editor_icon_path(editor: String) -> Result<Option<String>, String> {
    let app_path = match editor.as_str() {
        "windsurf" => std::path::PathBuf::from("/Applications/Windsurf.app"),
        "cursor" => std::path::PathBuf::from("/Applications/Cursor.app"),
        "code" => std::path::PathBuf::from("/Applications/Visual Studio Code.app"),
        "antigravity" => std::path::PathBuf::from("/Applications/Antigravity.app"),
        _ => return Ok(None),
    };

    // アプリが存在しない場合はNoneを返す
    if !app_path.exists() {
        return Ok(None);
    }

    // AppScannerを使ってアイコンパスを取得
    let icon_path = match AppScanner::get_app_icon_path(&app_path) {
        Some(path) => path,
        None => return Ok(None),
    };

    // IconConverterを使ってPNGに変換
    let converter = icon_converter::IconConverter::new()?;
    match converter.convert_icns_to_png(&icon_path) {
        Ok(png_path) => Ok(Some(png_path)),
        Err(e) => {
            eprintln!("Failed to convert icon for {}: {}", editor, e);
            Ok(None)
        }
    }
}

#[tauri::command]
fn get_terminal_icon_path(terminal: String) -> Result<Option<String>, String> {
    let app_path = match terminal.as_str() {
        "terminal" => std::path::PathBuf::from("/System/Applications/Utilities/Terminal.app"),
        "iterm2" => std::path::PathBuf::from("/Applications/iTerm.app"),
        "warp" => std::path::PathBuf::from("/Applications/Warp.app"),
        _ => return Ok(None),
    };

    // アプリが存在しない場合はNoneを返す
    if !app_path.exists() {
        return Ok(None);
    }

    // AppScannerを使ってアイコンパスを取得
    let icon_path = match AppScanner::get_app_icon_path(&app_path) {
        Some(path) => path,
        None => return Ok(None),
    };

    // IconConverterを使ってPNGに変換
    let converter = icon_converter::IconConverter::new()?;
    match converter.convert_icns_to_png(&icon_path) {
        Ok(png_path) => Ok(Some(png_path)),
        Err(e) => {
            eprintln!("Failed to convert icon for {}: {}", terminal, e);
            Ok(None)
        }
    }
}

#[tauri::command]
async fn check_update(force: bool, app: tauri::AppHandle, state: State<'_, AppState>) -> Result<update_checker::UpdateInfo, String> {
    let version = app.package_info().version.to_string();
    update_checker::check_for_updates(&state.settings_manager, version, force).await
}

#[tauri::command]
fn dismiss_update(version: String, state: State<AppState>) -> Result<(), String> {
    state.settings_manager.dismiss_update(version)
}

#[tauri::command]
fn open_settings_window(app: tauri::AppHandle) -> Result<(), String> {
    use tauri::WebviewUrl;
    use tauri::WebviewWindowBuilder;

    // 設定ウィンドウが既に存在する場合は表示
    if let Some(window) = app.get_webview_window("settings") {
        window.show().map_err(|e| e.to_string())?;
        window.set_focus().map_err(|e| e.to_string())?;
    } else {
        // 存在しない場合は新規作成
        WebviewWindowBuilder::new(&app, "settings", WebviewUrl::App("settings.html".into()))
            .title("設定 - Ignitero Launcher")
            .inner_size(800.0, 600.0)
            .resizable(true)
            .center()
            .build()
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

pub fn perform_cache_refresh(state: &State<AppState>) -> Result<(), String> {
    let mut all_apps = Vec::new();

    // /Applications配下をスキャン
    all_apps.extend(AppScanner::scan_applications());

    // 登録ディレクトリでscan_for_apps=trueのものをスキャン
    let registered_dirs = state.settings_manager.get_registered_directories();
    for dir in &registered_dirs {
        if dir.scan_for_apps {
            let path = std::path::PathBuf::from(&dir.path);
            if path.exists() {
                all_apps.extend(AppScanner::scan_directory(&path, 3));
            }
        }
    }

    // アイコンを一括変換
    let converter = icon_converter::IconConverter::new()?;
    for app in &mut all_apps {
        if let Some(icon_path) = &app.icon_path {
            match converter.convert_icns_to_png(icon_path) {
                Ok(png_path) => {
                    app.icon_path = Some(png_path);
                }
                Err(e) => {
                    eprintln!("Failed to convert icon for {}: {}", app.name, e);
                    app.icon_path = None;
                }
            }
        }
    }

    // ディレクトリのスキャン
    let mut all_directories = Vec::new();
    for reg_dir in registered_dirs {
        let path = std::path::PathBuf::from(&reg_dir.path);
        if path.exists() {
            // 親ディレクトリ自身の処理
            if reg_dir.parent_open_mode != types::OpenMode::None {
                if let Some(default_name) = path.file_name().and_then(|n| n.to_str()) {
                    // parent_search_keywordがあればそれを使用、なければディレクトリ名
                    let display_name = reg_dir
                        .parent_search_keyword
                        .as_ref()
                        .filter(|k| !k.is_empty())
                        .map(|k| k.as_str())
                        .unwrap_or(default_name);

                    all_directories.push(types::DirectoryItem {
                        name: display_name.to_string(),
                        path: path.to_string_lossy().to_string(),
                        editor: if reg_dir.parent_open_mode == types::OpenMode::Editor {
                            reg_dir.parent_editor.clone()
                        } else {
                            None
                        },
                    });
                }
            }

            // サブディレクトリの処理
            if reg_dir.subdirs_open_mode != types::OpenMode::None {
                let mut subdirs = DirectoryScanner::scan_subdirectories(&path);
                for dir in &mut subdirs {
                    dir.editor = if reg_dir.subdirs_open_mode == types::OpenMode::Editor {
                        reg_dir.subdirs_editor.clone()
                    } else {
                        None
                    };
                }
                all_directories.extend(subdirs);
            }
        }
    }

    // キャッシュに保存
    let cache_db = state.cache_db.lock().unwrap();
    cache_db
        .save_apps(&all_apps)
        .map_err(|e| format!("Failed to save apps to cache: {}", e))?;
    cache_db
        .save_directories(&all_directories)
        .map_err(|e| format!("Failed to save directories to cache: {}", e))?;

    // 最終更新時刻を記録
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs() as i64;
    cache_db
        .set_last_update_time(now)
        .map_err(|e| format!("Failed to set last update time: {}", e))?;

    // メモリ上のデータを更新
    *state.apps.lock().unwrap() = all_apps;
    *state.directories.lock().unwrap() = all_directories;

    println!("Cache updated successfully at {}", now);
    Ok(())
}

// キャッシュの初期化（起動時）
fn prime_cache(state: &State<AppState>, settings: &Settings) -> Result<(), String> {
    let cache_db = state.cache_db.lock().unwrap();
    let is_empty = cache_db.is_empty().unwrap_or(true);
    drop(cache_db);

    // キャッシュが空または起動時更新が有効な場合はリフレッシュ
    if is_empty || settings.cache_update.update_on_startup {
        println!(
            "Priming cache (empty: {}, update_on_startup: {})",
            is_empty, settings.cache_update.update_on_startup
        );
        perform_cache_refresh(state)
    } else {
        // キャッシュからロード
        println!("Loading from cache...");
        let cache_db = state.cache_db.lock().unwrap();
        let apps = cache_db.load_apps().map_err(|e| e.to_string())?;
        let directories = cache_db.load_directories().map_err(|e| e.to_string())?;
        drop(cache_db);

        *state.apps.lock().unwrap() = apps;
        *state.directories.lock().unwrap() = directories;
        Ok(())
    }
}

fn refresh_directories(state: State<AppState>) -> Result<(), String> {
    perform_cache_refresh(&state)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .setup(|app| {
            // macOSでDockアイコンを非表示にする
            #[cfg(target_os = "macos")]
            {
                use tauri::ActivationPolicy;
                app.set_activation_policy(ActivationPolicy::Accessory);
            }

            // 初期状態の構築
            let settings_manager = SettingsManager::new();
            let search_engine = SearchEngine::new();
            let cache_db = CacheDB::new().expect("Failed to initialize cache DB");

            // AppState を先に管理
            app.manage(AppState {
                apps: Mutex::new(Vec::new()),
                directories: Mutex::new(Vec::new()),
                search_engine,
                settings_manager,
                cache_db: Mutex::new(cache_db),
                tray_icon: Mutex::new(None),
            });

            // キャッシュを初期化
            let settings = app.state::<AppState>().settings_manager.get_settings();
            if let Err(e) = prime_cache(&app.state::<AppState>(), &settings) {
                eprintln!("Warning: Failed to prime cache: {}", e);
            }

            // グローバルホットキーの設定 (Option+Space)
            let app_handle = app.handle().clone();
            if let Err(e) =
                app.global_shortcut()
                    .on_shortcut("Alt+Space", move |_app, _shortcut, event| {
                        use tauri_plugin_global_shortcut::ShortcutState;

                        // Pressedイベントのみで動作（Released時は無視）
                        if event.state() != ShortcutState::Pressed {
                            return;
                        }

                        if let Some(window) = app_handle.get_webview_window("main") {
                            if window.is_visible().unwrap_or(false) {
                                let _ = window.hide();
                            } else {
                                let _ = window.show();
                                let _ = window.set_focus();
                                // ウィンドウ表示時に英語入力に切り替え
                                #[cfg(target_os = "macos")]
                                let _ = ime_control::force_english_input();
                            }
                        }
                    })
            {
                eprintln!("Warning: Failed to set hotkey handler: {}", e);
            }

            // グローバルホットキーを登録
            if let Err(e) = app.global_shortcut().register("Alt+Space") {
                eprintln!("Warning: Failed to register hotkey Alt+Space: {}", e);
                eprintln!("You can still use the app from the menu bar or by clicking the window");
            }

            // ウィンドウイベントのハンドリング
            if let Some(window) = app.get_webview_window("main") {
                #[cfg(target_os = "macos")]
                {
                    let _ = window.set_title_bar_style(TitleBarStyle::Overlay);
                    if let Err(err) = apply_vibrancy(
                        &window,
                        NSVisualEffectMaterial::HudWindow,
                        Some(NSVisualEffectState::Active),
                        Some(12.0),
                    ) {
                        eprintln!("Failed to apply vibrancy: {err}");
                    }
                }

                let window_clone = window.clone();
                window.on_window_event(move |event| {
                    match event {
                        // ×ボタンでの終了を防ぎ、ウィンドウを隠す
                        tauri::WindowEvent::CloseRequested { api, .. } => {
                            api.prevent_close();
                            let _ = window_clone.hide();
                        }
                        // フォーカス時にIME制御（macOSのみ）
                        #[cfg(target_os = "macos")]
                        tauri::WindowEvent::Focused(true) => {
                            if let Err(e) = ime_control::force_english_input() {
                                eprintln!("IME switch failed: {}", e);
                            }
                        }
                        _ => {}
                    }
                });
            }

            // メニューバーのセットアップ
            let tray_icon = setup_system_tray(app).expect("Failed to setup menu bar");

            // TrayIconをAppStateに保存
            if let Some(state) = app.try_state::<AppState>() {
                *state.tray_icon.lock().unwrap() = Some(tray_icon);
            }

            // 自動更新タイマーの起動
            let settings = app.state::<AppState>().settings_manager.get_settings();
            if settings.cache_update.auto_update_enabled {
                let app_handle_timer = app.handle().clone();

                thread::spawn(move || {
                    loop {
                        thread::sleep(Duration::from_secs(3600)); // 1時間ごとにチェック

                        if let Some(state) = app_handle_timer.try_state::<AppState>() {
                            let settings = state.settings_manager.get_settings();

                            if settings.cache_update.auto_update_enabled {
                                let interval_hours =
                                    settings.cache_update.auto_update_interval_hours;
                                let cache_db = state.cache_db.lock().unwrap();
                                let needs_update =
                                    cache_db.needs_update(interval_hours).unwrap_or(false);
                                drop(cache_db);

                                if needs_update {
                                    println!(
                                        "Auto-updating cache (interval: {} hours)...",
                                        interval_hours
                                    );
                                    let _ = perform_cache_refresh(&state);
                                }
                            }
                        }
                    }
                });
            }

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            search_apps,
            search_directories,
            launch_app,
            open_directory,
            open_in_terminal,
            hide_window,
            show_window,
            open_settings_window,
            get_settings,
            save_settings,
            add_directory,
            remove_directory,
            refresh_cache,
            show_folder_picker,
            get_available_editors,
            get_available_terminals,
            force_english_input_wrapper,
            convert_icon_to_png,
            get_editor_icon_path,
            get_terminal_icon_path,
            check_update,
            dismiss_update,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
