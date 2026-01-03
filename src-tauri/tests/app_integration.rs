use ignitero_launcher_lib::cache::CacheDB;
use ignitero_launcher_lib::{types, SearchEngineExport};
use std::path::Path;

#[test]
fn test_cache_db_lifecycle() {
    // インメモリキャッシュの作成とライフサイクル
    let cache = CacheDB::new_in_memory().expect("Failed to create in-memory cache");

    // テストアプリのキャッシュ
    let test_apps = vec![types::AppItem {
        name: "TestApp".to_string(),
        path: "/Applications/TestApp.app".to_string(),
        icon_path: None,
        original_name: None,
    }];

    cache.save_apps(&test_apps).expect("Failed to save apps");

    // キャッシュから取得
    let cached_apps = cache.load_apps().expect("Failed to load apps");
    assert_eq!(cached_apps.len(), 1);
    assert_eq!(cached_apps[0].name, "TestApp");

    // キャッシュクリア
    cache.clear_cache().expect("Failed to clear cache");
    let cached_apps = cache.load_apps().expect("Failed to load apps");
    assert_eq!(cached_apps.len(), 0);
}

#[test]
fn test_search_engine_with_empty_data() {
    let engine = SearchEngineExport::new();

    // 空のアプリリストで検索
    let results = engine.search_apps(&[], "test");
    assert_eq!(results.len(), 0);

    // 空のディレクトリリストで検索
    let results = engine.search_directories(&[], "test");
    assert_eq!(results.len(), 0);
}

#[test]
fn test_search_engine_with_large_dataset() {
    let engine = SearchEngineExport::new();

    // 100個のアプリを作成
    let apps: Vec<_> = (0..100)
        .map(|i| types::AppItem {
            name: format!("App{}", i),
            path: format!("/Applications/App{}.app", i),
            icon_path: None,
            original_name: None,
        })
        .collect();

    // "App"で検索すると20件に制限される
    let results = engine.search_apps(&apps, "App");
    assert_eq!(results.len(), 20);

    // 特定の番号で検索
    let results = engine.search_apps(&apps, "App42");
    assert!(results.iter().any(|app| app.name == "App42"));
}

#[test]
fn test_directory_scanner_with_nonexistent_path() {
    use ignitero_launcher_lib::DirectoryScannerExport;

    // 存在しないパスでスキャン
    let dirs = DirectoryScannerExport::scan_subdirectories(Path::new("/nonexistent/path"));

    // エラーにならず、空のリストが返る
    assert_eq!(dirs.len(), 0);
}

#[test]
fn test_app_scanner_static_method() {
    use ignitero_launcher_lib::AppScannerExport;

    // AppScannerは静的メソッドを持つ
    // 実際の/Applications配下をスキャンするため、結果の検証は行わない
    // （テスト環境によって結果が異なるため）
    let _apps = AppScannerExport::scan_applications();

    // パニックしないことを確認（アサーションなし）
}

#[test]
fn test_integration_search_flow() {
    // 統合的な検索フロー
    let engine = SearchEngineExport::new();

    let apps = vec![
        types::AppItem {
            name: "Safari".to_string(),
            path: "/Applications/Safari.app".to_string(),
            icon_path: None,
            original_name: None,
        },
        types::AppItem {
            name: "Mail".to_string(),
            path: "/Applications/Mail.app".to_string(),
            icon_path: None,
            original_name: None,
        },
        types::AppItem {
            name: "Calendar".to_string(),
            path: "/Applications/Calendar.app".to_string(),
            icon_path: None,
            original_name: None,
        },
    ];

    // 段階的な検索
    let results = engine.search_apps(&apps, "s");
    assert!(results.len() > 0);

    let results = engine.search_apps(&apps, "sa");
    assert!(results.len() > 0);

    let results = engine.search_apps(&apps, "saf");
    assert_eq!(results.len(), 1);
    assert_eq!(results[0].name, "Safari");
}

#[test]
fn test_cache_save_load_cycle() {
    // インメモリキャッシュで保存・読み込みサイクルをテスト
    let cache = CacheDB::new_in_memory().expect("Failed to create cache");

    let test_apps = vec![
        types::AppItem {
            name: "App1".to_string(),
            path: "/Applications/App1.app".to_string(),
            icon_path: None,
            original_name: None,
        },
        types::AppItem {
            name: "App2".to_string(),
            path: "/Applications/App2.app".to_string(),
            icon_path: Some("/path/to/icon.png".to_string()),
            original_name: None,
        },
    ];

    // 保存
    cache.save_apps(&test_apps).expect("Failed to save apps");

    // 読み込み
    let loaded_apps = cache.load_apps().expect("Failed to load apps");
    assert_eq!(loaded_apps.len(), 2);
    assert_eq!(loaded_apps[0].name, "App1");
    assert_eq!(loaded_apps[1].name, "App2");
    assert_eq!(
        loaded_apps[1].icon_path,
        Some("/path/to/icon.png".to_string())
    );
}

#[test]
fn test_cache_directories() {
    let cache = CacheDB::new_in_memory().expect("Failed to create cache");

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

    // 保存
    cache
        .save_directories(&test_dirs)
        .expect("Failed to save directories");

    // 読み込み
    let loaded_dirs = cache
        .load_directories()
        .expect("Failed to load directories");
    assert_eq!(loaded_dirs.len(), 2);
    assert_eq!(loaded_dirs[0].name, "Documents");
    assert_eq!(loaded_dirs[1].name, "Projects");
}

#[test]
fn test_concurrent_search() {
    use std::sync::Arc;
    use std::thread;

    let engine = Arc::new(SearchEngineExport::new());
    let apps = Arc::new(vec![
        types::AppItem {
            name: "Safari".to_string(),
            path: "/Applications/Safari.app".to_string(),
            icon_path: None,
            original_name: None,
        },
        types::AppItem {
            name: "Mail".to_string(),
            path: "/Applications/Mail.app".to_string(),
            icon_path: None,
            original_name: None,
        },
    ]);

    // 複数スレッドから同時に検索
    let mut handles = vec![];
    for _ in 0..5 {
        let engine = Arc::clone(&engine);
        let apps = Arc::clone(&apps);
        let handle = thread::spawn(move || {
            let results = engine.search_apps(&apps, "saf");
            assert_eq!(results.len(), 1);
        });
        handles.push(handle);
    }

    for handle in handles {
        handle.join().expect("Thread panicked");
    }
}
