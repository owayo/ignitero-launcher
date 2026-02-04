mod app_scanner;
pub mod cache;
mod directory_scanner;
mod icon_converter;
mod ime_control;
mod launcher;
mod search;
mod settings;
mod system_tray;
pub mod types;
mod update_checker;
mod window_corners;

use app_scanner::AppScanner;
use cache::CacheDB;
use directory_scanner::DirectoryScanner;
use launcher::Launcher;
use search::SearchEngine;
use serde::Serialize;
use settings::SettingsManager;

// Export public modules for testing
pub use app_scanner::AppScanner as AppScannerExport;
pub use directory_scanner::DirectoryScanner as DirectoryScannerExport;
pub use search::SearchEngine as SearchEngineExport;
pub use settings::SettingsManager as SettingsManagerExport;
use std::sync::mpsc::channel;
use std::sync::Mutex;
use std::thread;
use std::time::Duration;
use system_tray::setup_system_tray;
use tauri::tray::TrayIcon;
use tauri::{Manager, PhysicalPosition, State};
use tauri_plugin_global_shortcut::GlobalShortcutExt;
use types::{
    AppItem, CommandItem, CustomCommand, DirectoryItem, RegisteredDirectory, Settings,
    WindowPosition,
};

pub struct AppState {
    pub apps: Mutex<Vec<AppItem>>,
    pub directories: Mutex<Vec<DirectoryItem>>,
    pub commands: Mutex<Vec<CommandItem>>,
    pub search_engine: SearchEngine,
    pub settings_manager: SettingsManager,
    pub cache_db: Mutex<CacheDB>,
    pub tray_icon: Mutex<Option<TrayIcon>>,
}

#[tauri::command]
fn search_apps(query: String, state: State<AppState>) -> Vec<AppItem> {
    let apps = state.apps.lock().unwrap();
    let settings = state.settings_manager.get_settings();
    let excluded_apps = &settings.excluded_apps;

    // 検索結果から除外アプリをフィルタリング
    state
        .search_engine
        .search_apps(&apps, &query)
        .into_iter()
        .filter(|app| !excluded_apps.contains(&app.path))
        .collect()
}

#[tauri::command]
fn get_all_apps(state: State<AppState>) -> Vec<AppItem> {
    let apps = state.apps.lock().unwrap();
    apps.clone()
}

#[tauri::command]
fn search_directories(query: String, state: State<AppState>) -> Vec<DirectoryItem> {
    let directories = state.directories.lock().unwrap();
    state.search_engine.search_directories(&directories, &query)
}

#[tauri::command]
fn search_commands(query: String, state: State<AppState>) -> Vec<CommandItem> {
    let commands = state.commands.lock().unwrap();
    state.search_engine.search_commands(&commands, &query)
}

#[tauri::command]
fn add_command(command: CustomCommand, state: State<AppState>) -> Result<(), String> {
    state.settings_manager.add_command(command)?;
    refresh_commands(state)
}

#[tauri::command]
fn remove_command(alias: String, state: State<AppState>) -> Result<(), String> {
    state.settings_manager.remove_command(&alias)?;
    refresh_commands(state)
}

#[tauri::command]
fn execute_command(
    command: String,
    working_directory: Option<String>,
    state: State<AppState>,
) -> Result<(), String> {
    let settings = state.settings_manager.get_settings();
    Launcher::execute_command(
        &command,
        working_directory.as_deref(),
        &settings.default_terminal,
    )
}

fn refresh_commands(state: State<AppState>) -> Result<(), String> {
    let custom_commands = state.settings_manager.get_custom_commands();
    let command_items: Vec<CommandItem> = custom_commands
        .into_iter()
        .map(|c| CommandItem {
            alias: c.alias,
            command: c.command,
            working_directory: c.working_directory,
        })
        .collect();
    *state.commands.lock().unwrap() = command_items;
    Ok(())
}

// テスト用の公開関数
#[cfg(test)]
pub fn test_search_apps(query: String, state: &AppState) -> Vec<AppItem> {
    let apps = state.apps.lock().unwrap();
    state.search_engine.search_apps(&apps, &query)
}

#[cfg(test)]
pub fn test_search_directories(query: String, state: &AppState) -> Vec<DirectoryItem> {
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
fn save_main_window_position(x: i32, y: i32, state: State<AppState>) -> Result<(), String> {
    state
        .settings_manager
        .save_main_window_position(WindowPosition { x, y })
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
        ("ghostty", "/Applications/Ghostty.app"),
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
fn get_editor_list() -> Vec<launcher::EditorInfo> {
    Launcher::get_available_editors()
}

#[tauri::command]
fn get_terminal_list() -> Vec<launcher::EditorInfo> {
    Launcher::get_available_terminals()
}

#[tauri::command]
fn convert_icon_to_png(icon_path: String) -> Result<String, String> {
    use icon_converter::IconConverter;

    let converter = IconConverter::new()?;
    converter.convert_icns_to_png(&icon_path)
}

#[tauri::command]
fn clear_icon_cache() -> Result<usize, String> {
    use icon_converter::IconConverter;

    let converter = IconConverter::new()?;
    converter.clear_cache()
}

#[tauri::command]
fn get_editor_icon_path(editor: String) -> Result<Option<String>, String> {
    let app_path = match editor.as_str() {
        "windsurf" => std::path::PathBuf::from("/Applications/Windsurf.app"),
        "cursor" => std::path::PathBuf::from("/Applications/Cursor.app"),
        "code" => std::path::PathBuf::from("/Applications/Visual Studio Code.app"),
        "antigravity" => std::path::PathBuf::from("/Applications/Antigravity.app"),
        "zed" => std::path::PathBuf::from("/Applications/Zed.app"),
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
        "ghostty" => std::path::PathBuf::from("/Applications/Ghostty.app"),
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
async fn check_update(
    force: bool,
    app: tauri::AppHandle,
    state: State<'_, AppState>,
) -> Result<update_checker::UpdateInfo, String> {
    let version = app.package_info().version.to_string();
    update_checker::check_for_updates(&state.settings_manager, version, force).await
}

#[tauri::command]
fn dismiss_update(version: String, state: State<AppState>) -> Result<(), String> {
    state.settings_manager.dismiss_update(version)
}

#[tauri::command]
fn open_editor_picker_window(
    app: tauri::AppHandle,
    directory_path: String,
    current_editor: Option<String>,
) -> Result<(), String> {
    use tauri::{WebviewUrl, WebviewWindowBuilder};

    println!(
        "[editor-picker] open requested for {} with editor {:?} (existing windows: {:?})",
        directory_path,
        current_editor,
        app.webview_windows().keys().collect::<Vec<_>>()
    );

    // エディタ選択ウィンドウが既に存在する場合は閉じて再作成
    if let Some(window) = app.get_webview_window("editor-picker") {
        println!("[editor-picker] closing existing window before reopening");
        if let Err(err) = window.close() {
            eprintln!("[editor-picker] failed to close existing window: {err}");
        }
    }

    // メインウィンドウの位置を取得
    let main_window_position = if let Some(main_window) = app.get_webview_window("main") {
        main_window.outer_position().ok()
    } else {
        None
    };

    // URLエンコードしてクエリパラメータとして渡す
    let encoded_path = urlencoding::encode(&directory_path);
    let mut url = format!("editor-picker.html?path={}", encoded_path);
    if let Some(editor) = current_editor {
        let encoded_editor = urlencoding::encode(&editor);
        url.push_str(&format!("&editor={}", encoded_editor));
    }

    println!(
        "[editor-picker] window states before build: {:?}",
        list_window_states(app.clone())
    );

    // 新規作成
    let mut builder = WebviewWindowBuilder::new(&app, "editor-picker", WebviewUrl::App(url.into()))
        .title("エディタ選択")
        .visible(true)
        .inner_size(400.0, 450.0)
        .resizable(false)
        .decorations(false)
        .transparent(true)
        .always_on_top(true)
        .skip_taskbar(true);

    // メインウィンドウと同じディスプレイに表示
    if let Some(pos) = main_window_position {
        builder = builder.position(pos.x as f64, pos.y as f64);
    } else {
        builder = builder.center();
    }

    let window = builder.build().map_err(|e| {
        eprintln!("[editor-picker] failed to build window: {e}");
        e.to_string()
    })?;

    // macOS 26 (Tahoe) 対応: ウィンドウに角丸マスクを適用
    if let Err(e) = window_corners::apply_window_corners(&window) {
        eprintln!("[editor-picker] failed to apply window corners: {e}");
    }

    // 中央に配置（メインウィンドウと同じディスプレイ上で）
    if let Err(e) = window.center() {
        eprintln!("[editor-picker] failed to center window: {e}");
    }

    window.show().map_err(|e| {
        eprintln!("[editor-picker] failed to show window: {e}");
        e.to_string()
    })?;

    window.set_focus().map_err(|e| {
        eprintln!("[editor-picker] failed to focus window: {e}");
        e.to_string()
    })?;

    println!(
        "[editor-picker] window states after build: {:?}",
        list_window_states(app.clone())
    );
    println!(
        "[editor-picker] immediate visibility check => visible: {}, focused: {}",
        window.is_visible().unwrap_or(false),
        window.is_focused().unwrap_or(false)
    );

    println!(
        "[editor-picker] window created and shown for {}",
        directory_path
    );

    Ok(())
}

#[tauri::command]
fn close_editor_picker_window(app: tauri::AppHandle) -> Result<(), String> {
    if let Some(window) = app.get_webview_window("editor-picker") {
        println!(
            "[editor-picker] close requested. visible: {}, focused: {}",
            window.is_visible().unwrap_or(false),
            window.is_focused().unwrap_or(false)
        );
        window.close().map_err(|e| e.to_string())?;
    } else {
        println!("[editor-picker] close requested but window not found");
    }
    Ok(())
}

#[tauri::command]
fn open_terminal_picker_window(
    app: tauri::AppHandle,
    directory_path: String,
) -> Result<(), String> {
    use tauri::{WebviewUrl, WebviewWindowBuilder};

    println!(
        "[terminal-picker] open requested for {} (existing windows: {:?})",
        directory_path,
        app.webview_windows().keys().collect::<Vec<_>>()
    );

    // ターミナル選択ウィンドウが既に存在する場合は閉じて再作成
    if let Some(window) = app.get_webview_window("terminal-picker") {
        println!("[terminal-picker] closing existing window before reopening");
        if let Err(err) = window.close() {
            eprintln!("[terminal-picker] failed to close existing window: {err}");
        }
    }

    // メインウィンドウの位置を取得
    let main_window_position = if let Some(main_window) = app.get_webview_window("main") {
        main_window.outer_position().ok()
    } else {
        None
    };

    // URLエンコードしてクエリパラメータとして渡す
    let encoded_path = urlencoding::encode(&directory_path);
    let url = format!("terminal-picker.html?path={}", encoded_path);

    // 新規作成
    let mut builder =
        WebviewWindowBuilder::new(&app, "terminal-picker", WebviewUrl::App(url.into()))
            .title("ターミナル選択")
            .visible(true)
            .inner_size(400.0, 450.0)
            .resizable(false)
            .decorations(false)
            .transparent(true)
            .always_on_top(true)
            .skip_taskbar(true);

    // メインウィンドウと同じディスプレイに表示
    if let Some(pos) = main_window_position {
        builder = builder.position(pos.x as f64, pos.y as f64);
    } else {
        builder = builder.center();
    }

    let window = builder.build().map_err(|e| {
        eprintln!("[terminal-picker] failed to build window: {e}");
        e.to_string()
    })?;

    // macOS 26 (Tahoe) 対応: ウィンドウに角丸マスクを適用
    if let Err(e) = window_corners::apply_window_corners(&window) {
        eprintln!("[terminal-picker] failed to apply window corners: {e}");
    }

    // 中央に配置（メインウィンドウと同じディスプレイ上で）
    if let Err(e) = window.center() {
        eprintln!("[terminal-picker] failed to center window: {e}");
    }

    window.show().map_err(|e| {
        eprintln!("[terminal-picker] failed to show window: {e}");
        e.to_string()
    })?;

    window.set_focus().map_err(|e| {
        eprintln!("[terminal-picker] failed to focus window: {e}");
        e.to_string()
    })?;

    println!(
        "[terminal-picker] window created and shown for {}",
        directory_path
    );

    Ok(())
}

#[tauri::command]
fn close_terminal_picker_window(app: tauri::AppHandle) -> Result<(), String> {
    if let Some(window) = app.get_webview_window("terminal-picker") {
        println!(
            "[terminal-picker] close requested. visible: {}, focused: {}",
            window.is_visible().unwrap_or(false),
            window.is_focused().unwrap_or(false)
        );
        window.close().map_err(|e| e.to_string())?;
    } else {
        println!("[terminal-picker] close requested but window not found");
    }
    Ok(())
}

// デバッグ用: 現在存在するWebviewウィンドウのラベル一覧を返す
#[tauri::command]
fn list_window_labels(app: tauri::AppHandle) -> Vec<String> {
    app.webview_windows().keys().cloned().collect()
}

#[derive(Debug, Serialize)]
struct WindowState {
    label: String,
    visible: bool,
    focused: bool,
}

fn build_window_state(label: &str, window: &tauri::WebviewWindow) -> WindowState {
    WindowState {
        label: label.to_string(),
        visible: window.is_visible().unwrap_or(false),
        focused: window.is_focused().unwrap_or(false),
    }
}

#[tauri::command]
fn get_window_state(app: tauri::AppHandle, label: String) -> Option<WindowState> {
    app.get_webview_window(&label)
        .as_ref()
        .map(|window| build_window_state(&label, window))
}

#[tauri::command]
fn list_window_states(app: tauri::AppHandle) -> Vec<WindowState> {
    app.webview_windows()
        .iter()
        .map(|(label, window)| build_window_state(label, window))
        .collect()
}

fn log_window_debug(window: &tauri::WebviewWindow, context: &str) {
    let position = window
        .outer_position()
        .map(|p| format!("{},{}", p.x, p.y))
        .unwrap_or_else(|e| format!("error:{e}"));
    let size = window
        .outer_size()
        .map(|s| format!("{},{}", s.width, s.height))
        .unwrap_or_else(|e| format!("error:{e}"));
    let visibility = window.is_visible().unwrap_or(false);
    let focused = window.is_focused().unwrap_or(false);
    let always_on_top = window.is_always_on_top().unwrap_or(false);

    println!(
        "[hotkey][debug] {context}: label={} pos=({}) size=({}) visible={} focused={} always_on_top={}",
        window.label(),
        position,
        size,
        visibility,
        focused,
        always_on_top
    );
}

fn ensure_main_window_ready(window: &tauri::WebviewWindow) {
    // サイズはフロントエンド側（App.tsx）のロジックに委ねる
    if let Err(e) = window.center() {
        eprintln!("[hotkey] failed to center main window: {}", e);
    }
    if let Err(e) = window.set_always_on_top(true) {
        eprintln!("[hotkey] failed to set always on top: {}", e);
    }
}

#[tauri::command]
fn open_settings_window(app: tauri::AppHandle) -> Result<(), String> {
    use tauri::{WebviewUrl, WebviewWindowBuilder};

    // 設定ウィンドウが既に存在する場合は表示
    if let Some(window) = app.get_webview_window("settings") {
        window.show().map_err(|e| e.to_string())?;
        window.set_focus().map_err(|e| e.to_string())?;
    } else {
        // メインウィンドウの位置を取得
        let main_window_position = if let Some(main_window) = app.get_webview_window("main") {
            main_window.outer_position().ok()
        } else {
            None
        };

        // 存在しない場合は新規作成
        let mut builder =
            WebviewWindowBuilder::new(&app, "settings", WebviewUrl::App("settings.html".into()))
                .title("設定 - Ignitero Launcher")
                .inner_size(800.0, 600.0)
                .resizable(true)
                .always_on_top(true);

        // メインウィンドウと同じディスプレイに表示
        if let Some(pos) = main_window_position {
            builder = builder.position(pos.x as f64, pos.y as f64);
        } else {
            builder = builder.center();
        }

        let window = builder.build().map_err(|e| e.to_string())?;

        // 中央に配置（メインウィンドウと同じディスプレイ上で）
        if let Err(e) = window.center() {
            eprintln!("[settings] failed to center window: {e}");
        }
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
                commands: Mutex::new(Vec::new()),
                search_engine,
                settings_manager,
                cache_db: Mutex::new(cache_db),
                tray_icon: Mutex::new(None),
            });

            // キャッシュを初期化
            let settings = app.state::<AppState>().settings_manager.get_settings();

            // 前回位置が保存されていれば復元し、角丸マスクを適用
            if let Some(window) = app.get_webview_window("main") {
                if let Some(ref position) = settings.main_window_position {
                    if let Err(e) =
                        window.set_position(PhysicalPosition::new(position.x, position.y))
                    {
                        eprintln!("Failed to restore main window position: {}", e);
                    }
                }

                // macOS 26 (Tahoe) 対応: ウィンドウに角丸マスクを適用
                if let Err(e) = window_corners::apply_window_corners(&window) {
                    eprintln!("Failed to apply window corners to main window: {}", e);
                }
            }

            if let Err(e) = prime_cache(&app.state::<AppState>(), &settings) {
                eprintln!("Warning: Failed to prime cache: {}", e);
            }

            // カスタムコマンドを読み込み
            {
                let state = app.state::<AppState>();
                let custom_commands = state.settings_manager.get_custom_commands();
                let command_items: Vec<CommandItem> = custom_commands
                    .into_iter()
                    .map(|c| CommandItem {
                        alias: c.alias,
                        command: c.command,
                        working_directory: c.working_directory,
                    })
                    .collect();
                *state.commands.lock().unwrap() = command_items;
            }

            // グローバルホットキーの設定 (Option+Space)
            const HOTKEY: &str = "Alt+Space";
            let app_handle = app.handle().clone();
            if let Err(e) = app.global_shortcut().on_shortcut(
                HOTKEY,
                move |_app, _shortcut, event| {
                    use tauri_plugin_global_shortcut::ShortcutState;

                    println!("[hotkey] {HOTKEY} event: {:?}", event.state());

                    // Pressedイベントのみで動作（Released時は無視）
                    if event.state() != ShortcutState::Pressed {
                        return;
                    }

                    let handle = app_handle.clone();
                    let handle_for_thread = handle.clone();
                    if let Err(e) = handle.run_on_main_thread(move || {
                        // エディタ選択ウィンドウが開いている場合は閉じてメインウィンドウを表示
                        if let Some(picker_window) =
                            handle_for_thread.get_webview_window("editor-picker")
                        {
                            if let Err(e) = picker_window.close() {
                                eprintln!("[hotkey] failed to close editor picker window: {}", e);
                            }
                            if let Some(main_window) = handle_for_thread.get_webview_window("main")
                            {
                                log_window_debug(&main_window, "before show after closing picker");
                                ensure_main_window_ready(&main_window);
                                if let Err(e) = main_window.show() {
                                    eprintln!("[hotkey] failed to show main window: {}", e);
                                } else {
                                    println!("[hotkey] showing main window");
                                }
                                if let Err(e) = main_window.set_focus() {
                                    eprintln!("[hotkey] failed to focus main window: {}", e);
                                }
                                log_window_debug(
                                    &main_window,
                                    "after show/focus with picker closed",
                                );
                                #[cfg(target_os = "macos")]
                                if let Err(e) = ime_control::force_english_input() {
                                    eprintln!("[hotkey] failed to force english input: {}", e);
                                }
                            } else {
                                eprintln!(
                                    "[hotkey] main window not found after closing editor picker"
                                );
                            }
                        // ターミナル選択ウィンドウが開いている場合は閉じてメインウィンドウを表示
                        } else if let Some(terminal_picker_window) =
                            handle_for_thread.get_webview_window("terminal-picker")
                        {
                            if let Err(e) = terminal_picker_window.close() {
                                eprintln!("[hotkey] failed to close terminal picker window: {}", e);
                            }
                            if let Some(main_window) = handle_for_thread.get_webview_window("main")
                            {
                                log_window_debug(
                                    &main_window,
                                    "before show after closing terminal picker",
                                );
                                ensure_main_window_ready(&main_window);
                                if let Err(e) = main_window.show() {
                                    eprintln!("[hotkey] failed to show main window: {}", e);
                                } else {
                                    println!("[hotkey] showing main window");
                                }
                                if let Err(e) = main_window.set_focus() {
                                    eprintln!("[hotkey] failed to focus main window: {}", e);
                                }
                                log_window_debug(
                                    &main_window,
                                    "after show/focus with terminal picker closed",
                                );
                                #[cfg(target_os = "macos")]
                                if let Err(e) = ime_control::force_english_input() {
                                    eprintln!("[hotkey] failed to force english input: {}", e);
                                }
                            } else {
                                eprintln!(
                                    "[hotkey] main window not found after closing terminal picker"
                                );
                            }
                        } else if let Some(main_window) =
                            handle_for_thread.get_webview_window("main")
                        {
                            log_window_debug(&main_window, "before toggle");
                            if main_window.is_visible().unwrap_or(false) {
                                if let Err(e) = main_window.hide() {
                                    eprintln!("[hotkey] failed to hide main window: {}", e);
                                } else {
                                    println!("[hotkey] hiding main window");
                                }
                                log_window_debug(&main_window, "after hide");
                            } else {
                                ensure_main_window_ready(&main_window);
                                if let Err(e) = main_window.show() {
                                    eprintln!("[hotkey] failed to show main window: {}", e);
                                } else {
                                    println!("[hotkey] showing main window");
                                }
                                log_window_debug(&main_window, "after show before focus");
                                if let Err(e) = main_window.set_focus() {
                                    eprintln!("[hotkey] failed to focus main window: {}", e);
                                }
                                log_window_debug(&main_window, "after focus");
                                if !main_window.is_visible().unwrap_or(false) {
                                    println!(
                                        "[hotkey] main window still hidden after show; retrying"
                                    );
                                    let _ = main_window.hide();
                                    if let Err(e) = main_window.show() {
                                        eprintln!("[hotkey] failed to re-show main window: {}", e);
                                    }
                                    log_window_debug(&main_window, "after re-show attempt");
                                }
                                // ウィンドウ表示時に英語入力に切り替え
                                #[cfg(target_os = "macos")]
                                if let Err(e) = ime_control::force_english_input() {
                                    eprintln!("[hotkey] failed to force english input: {}", e);
                                }
                            }
                        } else {
                            eprintln!("[hotkey] main window not found");
                        }
                    }) {
                        eprintln!("[hotkey] failed to dispatch to main thread: {}", e);
                    }
                },
            ) {
                eprintln!("Warning: Failed to set hotkey handler for {HOTKEY}: {}", e);
            } else {
                println!("[hotkey] Registered global shortcut handler for {HOTKEY}");
            }

            // ウィンドウイベントのハンドリング
            if let Some(window) = app.get_webview_window("main") {
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
            search_commands,
            get_all_apps,
            launch_app,
            open_directory,
            open_in_terminal,
            execute_command,
            hide_window,
            show_window,
            save_main_window_position,
            open_settings_window,
            open_editor_picker_window,
            close_editor_picker_window,
            open_terminal_picker_window,
            close_terminal_picker_window,
            get_settings,
            save_settings,
            add_directory,
            remove_directory,
            add_command,
            remove_command,
            refresh_cache,
            show_folder_picker,
            get_available_editors,
            get_available_terminals,
            get_editor_list,
            get_terminal_list,
            force_english_input_wrapper,
            convert_icon_to_png,
            clear_icon_cache,
            get_editor_icon_path,
            get_terminal_icon_path,
            check_update,
            dismiss_update,
            list_window_labels,
            list_window_states,
            get_window_state,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
