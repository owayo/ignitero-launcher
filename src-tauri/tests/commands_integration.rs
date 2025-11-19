use ignitero_launcher_lib::{
    cache::CacheDB, types, AppState, SearchEngineExport, SettingsManagerExport,
};
use std::sync::Mutex;

/// テスト用のAppStateを作成するヘルパー関数
fn create_test_state() -> AppState {
    let test_apps = vec![
        types::AppItem {
            name: "Safari".to_string(),
            path: "/Applications/Safari.app".to_string(),
            icon_path: None,
        },
        types::AppItem {
            name: "Mail".to_string(),
            path: "/Applications/Mail.app".to_string(),
            icon_path: None,
        },
        types::AppItem {
            name: "Calendar".to_string(),
            path: "/Applications/Calendar.app".to_string(),
            icon_path: None,
        },
    ];

    let test_dirs = vec![
        types::DirectoryItem {
            name: "Projects".to_string(),
            path: "/Users/test/Projects".to_string(),
            editor: Some("cursor".to_string()),
        },
        types::DirectoryItem {
            name: "Documents".to_string(),
            path: "/Users/test/Documents".to_string(),
            editor: None,
        },
    ];

    AppState {
        apps: Mutex::new(test_apps),
        directories: Mutex::new(test_dirs),
        search_engine: SearchEngineExport::new(),
        settings_manager: SettingsManagerExport::new(),
        cache_db: Mutex::new(CacheDB::new_in_memory().unwrap()),
        tray_icon: Mutex::new(None),
    }
}

#[test]
fn test_search_apps_command() {
    let state = create_test_state();
    let apps = state.apps.lock().unwrap();

    // "saf"で検索してSafariがヒットすること
    let results = state.search_engine.search_apps(&apps, "saf");
    assert_eq!(results.len(), 1);
    assert_eq!(results[0].name, "Safari");

    // "mail"で検索してMailがヒットすること
    let results = state.search_engine.search_apps(&apps, "mail");
    assert_eq!(results.len(), 1);
    assert_eq!(results[0].name, "Mail");

    // 空文字列で検索すると0件
    let results = state.search_engine.search_apps(&apps, "");
    assert_eq!(results.len(), 0);

    // マッチしないクエリは0件
    let results = state.search_engine.search_apps(&apps, "xyz");
    assert_eq!(results.len(), 0);
}

#[test]
fn test_search_directories_command() {
    let state = create_test_state();
    let dirs = state.directories.lock().unwrap();

    // "proj"で検索してProjectsがヒットすること
    let results = state.search_engine.search_directories(&dirs, "proj");
    assert_eq!(results.len(), 1);
    assert_eq!(results[0].name, "Projects");

    // "doc"で検索してDocumentsがヒットすること
    let results = state.search_engine.search_directories(&dirs, "doc");
    assert_eq!(results.len(), 1);
    assert_eq!(results[0].name, "Documents");

    // 空文字列で検索すると0件
    let results = state.search_engine.search_directories(&dirs, "");
    assert_eq!(results.len(), 0);
}

#[test]
fn test_search_apps_fuzzy_matching() {
    let state = create_test_state();
    let apps = state.apps.lock().unwrap();

    // ファジーマッチング: "sf"でSafariがヒットすること
    let results = state.search_engine.search_apps(&apps, "sf");
    assert!(results.iter().any(|app| app.name == "Safari"));

    // ファジーマッチング: "cal"でCalendarがヒットすること
    let results = state.search_engine.search_apps(&apps, "cal");
    assert!(results.iter().any(|app| app.name == "Calendar"));
}

#[test]
fn test_search_case_insensitive() {
    let state = create_test_state();
    let apps = state.apps.lock().unwrap();

    // 大文字小文字を区別しない: "SAFARI"でもヒット
    let results = state.search_engine.search_apps(&apps, "SAFARI");
    assert!(results.iter().any(|app| app.name == "Safari"));

    // 大文字小文字を区別しない: "safari"でもヒット
    let results = state.search_engine.search_apps(&apps, "safari");
    assert!(results.iter().any(|app| app.name == "Safari"));
}

#[test]
fn test_multiple_results() {
    let mut test_apps = vec![];
    for i in 0..5 {
        test_apps.push(types::AppItem {
            name: format!("TestApp{}", i),
            path: format!("/Applications/TestApp{}.app", i),
            icon_path: None,
        });
    }

    let state = AppState {
        apps: Mutex::new(test_apps),
        directories: Mutex::new(vec![]),
        search_engine: SearchEngineExport::new(),
        settings_manager: SettingsManagerExport::new(),
        cache_db: Mutex::new(CacheDB::new_in_memory().unwrap()),
        tray_icon: Mutex::new(None),
    };

    let apps = state.apps.lock().unwrap();
    // "test"で検索すると全てヒットする
    let results = state.search_engine.search_apps(&apps, "test");
    assert_eq!(results.len(), 5);
}
