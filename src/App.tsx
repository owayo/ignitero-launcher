import React, {
  useState,
  useEffect,
  useCallback,
  useRef,
  useMemo,
} from 'react';
import { Input, List, Typography, Space, Button, Tooltip, Alert } from 'antd';
import {
  AppstoreOutlined,
  FolderFilled,
  SearchOutlined,
  SettingOutlined,
  ReloadOutlined,
  MoreOutlined,
  CalculatorOutlined,
} from '@ant-design/icons';
import { invoke, convertFileSrc } from '@tauri-apps/api/core';
import { getCurrentWindow, LogicalSize } from '@tauri-apps/api/window';
import { listen } from '@tauri-apps/api/event';
import { open } from '@tauri-apps/plugin-shell';
import type { AppItem, DirectoryItem, WindowState } from './types';
import { evaluateExpression } from './calculator';
import './App.css';

const { Text } = Typography;

interface UpdateInfo {
  has_update: boolean;
  current_version: string;
  latest_version: string | null;
  html_url: string | null;
}

type SearchResult = AppItem | DirectoryItem;

function isAppItem(item: SearchResult): item is AppItem {
  return 'icon_path' in item;
}

// 選択履歴の型定義
interface SelectionHistory {
  keyword: string;
  selectedPath: string;
  timestamp: number;
}

const HISTORY_STORAGE_KEY = 'ignitero_selection_history';
const MAX_HISTORY_COUNT = 50;

// 履歴をLocalStorageから読み込み
const loadHistory = (): SelectionHistory[] => {
  try {
    const stored = localStorage.getItem(HISTORY_STORAGE_KEY);
    return stored ? JSON.parse(stored) : [];
  } catch (error) {
    console.error('Failed to load history:', error);
    return [];
  }
};

// 履歴をLocalStorageに保存
const saveHistory = (history: SelectionHistory[]) => {
  try {
    localStorage.setItem(HISTORY_STORAGE_KEY, JSON.stringify(history));
  } catch (error) {
    console.error('Failed to save history:', error);
  }
};

// キーワードで選択された項目の頻度を計算
const calculateFrequency = (
  keyword: string,
  path: string,
  history: SelectionHistory[],
): number => {
  return history.filter(
    (h) =>
      h.keyword.toLowerCase() === keyword.toLowerCase() &&
      h.selectedPath === path,
  ).length;
};

// エディタアイコンキャッシュ（アプリ全体で共有）
const editorIconCache = new Map<string, string>();

// アイコンコンポーネント
const ItemIcon: React.FC<{ item: SearchResult }> = ({ item }) => {
  const [hasError, setHasError] = React.useState(false);
  const [editorIconPath, setEditorIconPath] = React.useState<string | null>(
    null,
  );

  // エディタアイコンのPNGパスを取得
  useEffect(() => {
    if (!isAppItem(item) && item.editor) {
      // キャッシュをチェック
      const cached = editorIconCache.get(item.editor);
      if (cached) {
        setEditorIconPath(cached);
        return;
      }

      console.log('Fetching editor icon for:', item.editor);
      invoke<string | null>('get_editor_icon_path', { editor: item.editor })
        .then((pngPath) => {
          console.log('Got editor icon path:', pngPath);
          if (pngPath) {
            editorIconCache.set(item.editor!, pngPath); // キャッシュに保存
            setEditorIconPath(pngPath);
          }
        })
        .catch((error) => {
          console.error('Failed to get editor icon path:', error);
        });
    }
  }, [!isAppItem(item) ? item.editor : undefined]); // DirectoryItemの場合のみeditorを依存に

  if (isAppItem(item)) {
    if (item.icon_path && !hasError) {
      const iconUrl = convertFileSrc(item.icon_path);
      console.log('Loading icon:', item.icon_path, '→', iconUrl);
      return (
        <img
          src={iconUrl}
          alt=""
          style={{ width: 32, height: 32, borderRadius: 4 }}
          onError={() => {
            console.error('Failed to load icon:', item.icon_path, '→', iconUrl);
            setHasError(true);
          }}
        />
      );
    }
    return <AppstoreOutlined style={{ fontSize: '32px' }} />;
  } else {
    // ディレクトリアイコン
    // エディタが設定されている場合、フォルダアイコンの中央にエディタアイコンを重ねる
    if (item.editor && editorIconPath) {
      const editorIconUrl = convertFileSrc(editorIconPath);

      return (
        <div style={{ position: 'relative', width: 32, height: 32 }}>
          <FolderFilled
            style={{
              fontSize: '32px',
              color: '#1890ff',
              position: 'absolute',
              top: 0,
              left: 0,
            }}
          />
          <img
            src={editorIconUrl}
            alt=""
            style={{
              width: 16,
              height: 16,
              borderRadius: 2,
              position: 'absolute',
              top: 'calc(50% + 2px)',
              left: '50%',
              transform: 'translate(-50%, -50%)',
            }}
            onError={() => {
              console.error('Failed to load editor icon:', editorIconPath);
              setEditorIconPath(null);
            }}
          />
        </div>
      );
    }

    // エディタなしまたはアイコン読み込み失敗時は通常のフォルダアイコン
    return <FolderFilled style={{ fontSize: '32px', color: '#1890ff' }} />;
  }
};

function App() {
  const [searchQuery, setSearchQuery] = useState('');
  const [displayQuery, setDisplayQuery] = useState(''); // IME表示用
  const [results, setResults] = useState<SearchResult[]>([]);
  const [selectedIndex, setSelectedIndex] = useState(0);
  const [isComposing, _setIsComposing] = useState(false);
  const [selectionHistory, setSelectionHistory] = useState<SelectionHistory[]>(
    () => loadHistory(),
  );
  const [updateInfo, setUpdateInfo] = useState<UpdateInfo | null>(null);
  const inputRef = React.useRef<any>(null);
  const shouldForceIME = React.useRef(true);
  const itemRefs = useRef<(HTMLDivElement | null)[]>([]); // リスト項目のref配列
  const defaultTerminal = useRef<'terminal' | 'iterm2' | 'warp'>('terminal'); // デフォルトターミナル
  const moveSaveTimeout = useRef<number | null>(null);
  const appWindowRef = useRef(getCurrentWindow());

  // 計算式の評価結果
  const calculationResult = useMemo(() => {
    return evaluateExpression(searchQuery);
  }, [searchQuery]);

  // デフォルトターミナル設定を読み込む
  useEffect(() => {
    invoke<any>('get_settings')
      .then((settings) => {
        defaultTerminal.current = settings.default_terminal || 'terminal';
      })
      .catch((error) => {
        console.error('Failed to load settings:', error);
      });

    // 設定変更イベントをリスニング
    const unlisten = listen('settings-changed', () => {
      invoke<any>('get_settings')
        .then((settings) => {
          defaultTerminal.current = settings.default_terminal || 'terminal';
        })
        .catch((error) => {
          console.error('Failed to reload settings:', error);
        });
    });

    return () => {
      unlisten.then((fn) => fn());
    };
  }, []);

  // ウィンドウ移動時に位置を保存（設定ファイルに保持して次回復元）
  useEffect(() => {
    const appWindow = getCurrentWindow();
    const unlistenPromise = appWindow.onMoved(({ payload: position }) => {
      if (moveSaveTimeout.current) {
        clearTimeout(moveSaveTimeout.current);
      }

      moveSaveTimeout.current = window.setTimeout(() => {
        invoke('save_main_window_position', {
          x: Math.round(position.x),
          y: Math.round(position.y),
        }).catch((error) => {
          console.error('Failed to save window position:', error);
        });
      }, 150);
    });

    return () => {
      unlistenPromise.then((fn) => fn());
      if (moveSaveTimeout.current) {
        clearTimeout(moveSaveTimeout.current);
      }
    };
  }, []);

  // 検索結果に応じてウィンドウサイズを動的に変更
  useEffect(() => {
    const appWindow = getCurrentWindow();
    const hasResults = results.length > 0;

    // 検索結果がない場合は小さいサイズ（入力欄のみ）
    // 検索結果がある場合は大きいサイズ
    const newSize = hasResults
      ? new LogicalSize(600, 500)
      : new LogicalSize(600, 80);

    appWindow.setSize(newSize).catch((error) => {
      console.error('Failed to set window size:', error);
    });
  }, [results.length]);

  // 検索処理
  const performSearch = useCallback(
    async (
      romajiQuery: string,
      kanaQuery: string,
      _composing: boolean = false,
    ) => {
      console.log('performSearch called:', {
        romajiQuery,
        kanaQuery,
        composing: _composing,
      });

      if (!romajiQuery.trim() && !kanaQuery.trim()) {
        setResults([]);
        return;
      }

      try {
        // ローマ字クエリとかなクエリの両方で検索
        const [
          romajiAppResults,
          romajiDirResults,
          kanaAppResults,
          kanaDirResults,
        ] = await Promise.all([
          romajiQuery.trim()
            ? invoke<AppItem[]>('search_apps', { query: romajiQuery })
            : Promise.resolve([]),
          romajiQuery.trim()
            ? invoke<DirectoryItem[]>('search_directories', {
                query: romajiQuery,
              })
            : Promise.resolve([]),
          kanaQuery.trim()
            ? invoke<AppItem[]>('search_apps', { query: kanaQuery })
            : Promise.resolve([]),
          kanaQuery.trim()
            ? invoke<DirectoryItem[]>('search_directories', {
                query: kanaQuery,
              })
            : Promise.resolve([]),
        ]);

        console.log('Search results:', {
          romajiApps: romajiAppResults.length,
          romajiDirs: romajiDirResults.length,
          kanaApps: kanaAppResults.length,
          kanaDirs: kanaDirResults.length,
        });

        // 結果をマージして重複を削除
        const appMap = new Map<string, AppItem>();
        [...romajiAppResults, ...kanaAppResults].forEach((app) => {
          appMap.set(app.path, app);
        });

        const dirMap = new Map<string, DirectoryItem>();
        [...romajiDirResults, ...kanaDirResults].forEach((dir) => {
          dirMap.set(dir.path, dir);
        });

        const allResults: SearchResult[] = [
          ...Array.from(appMap.values()),
          ...Array.from(dirMap.values()),
        ];

        // 履歴に基づいて結果をソート
        const sortedResults = allResults.sort((a, b) => {
          const freqA = calculateFrequency(
            romajiQuery,
            a.path,
            selectionHistory,
          );
          const freqB = calculateFrequency(
            romajiQuery,
            b.path,
            selectionHistory,
          );
          return freqB - freqA; // 頻度が高い順
        });

        setResults(sortedResults);
        setSelectedIndex(0);
      } catch (error) {
        console.error('Search error:', error);
      }
    },
    [selectionHistory],
  );

  // 検索クエリ変更時
  useEffect(() => {
    const timer = setTimeout(() => {
      performSearch(searchQuery, displayQuery, isComposing);
    }, 150);

    return () => clearTimeout(timer);
  }, [searchQuery, displayQuery, isComposing, performSearch]);

  // ウィンドウサイズの動的変更
  useEffect(() => {
    const appWindow = getCurrentWindow();
    const shouldExpand = searchQuery.length > 0;

    const resizeWindow = async () => {
      try {
        if (shouldExpand) {
          // 検索中または設定画面表示時は大きく
          await appWindow.setSize(new LogicalSize(600, 500));
        } else {
          // 初期状態は入力欄のみの高さ
          await appWindow.setSize(new LogicalSize(600, 80));
        }
      } catch (error) {
        console.error('Failed to resize window:', error);
      }
    };

    resizeWindow();
  }, [searchQuery]);

  // 選択項目を自動的にビューポート内にスクロール
  useEffect(() => {
    const selectedElement = itemRefs.current[selectedIndex];
    if (selectedElement) {
      selectedElement.scrollIntoView({
        behavior: 'auto', // キーボードナビゲーションは即座にスクロール
        block: 'nearest',
      });
    }
  }, [selectedIndex, results.map((r) => r.path).join(',')]);

  // ウィンドウの可視性変更イベントを監視
  useEffect(() => {
    const appWindow = getCurrentWindow();

    const unlisten = appWindow.onFocusChanged(async ({ payload: focused }) => {
      console.log('[main-window] focus changed', { focused });

      if (focused) {
        // 検索欄にフォーカスを設定
        setTimeout(() => {
          inputRef.current?.focus();
        }, 100);

        // 初回フォーカス時のみ英字入力モードに切り替え
        // macOSの自動復元を待ってから実行（150ms遅延）
        if (shouldForceIME.current) {
          shouldForceIME.current = false;
          setTimeout(() => {
            invoke('force_english_input_wrapper').catch((error) => {
              console.error('Failed to switch to English input:', error);
            });
          }, 150);
        }

        // 更新チェックを実行
        invoke<UpdateInfo>('check_update', { force: false })
          .then((info) => {
            console.log('Update check result:', info);
            if (info.has_update) {
              setUpdateInfo(info);
            }
          })
          .catch((error) => {
            console.error('Failed to check for updates:', error);
          });
      } else {
        // ウィンドウが非表示またはフォーカスを失ったら検索欄をクリアし、フラグをリセット
        shouldForceIME.current = true;
        setSearchQuery('');
        setDisplayQuery('');
        setResults([]);
        setSelectedIndex(0);

        try {
          const [visible, pickerState] = await Promise.all([
            appWindow.isVisible(),
            invoke<WindowState | null>('get_window_state', {
              label: 'editor-picker',
            }).catch((error) => {
              console.error('Failed to get editor picker window state:', error);
              return null;
            }),
          ]);

          console.log('[main-window] blur state', { visible, pickerState });

          if (pickerState?.visible || pickerState?.focused) {
            console.log(
              'Main window lost focus but editor picker is visible/focused; keeping it open.',
            );
            return;
          }

          if (!visible) {
            console.log(
              'Main window hidden; requesting editor picker close if it exists.',
            );
            invoke('close_editor_picker_window').catch((error) => {
              console.error('Failed to close editor picker window:', error);
            });
          } else {
            console.log(
              'Main window lost focus but is still visible; keeping editor picker window open.',
            );
          }
        } catch (error) {
          console.error(
            'Error while handling main window focus change:',
            error,
          );
        }
      }
    });

    return () => {
      unlisten.then((fn) => fn());
    };
  }, []);

  // ターミナルで開く
  const handleOpenInTerminal = useCallback(async (item: DirectoryItem) => {
    try {
      console.log('handleOpenInTerminal called with:', {
        path: item.path,
        terminal: defaultTerminal.current,
      });
      await invoke('open_in_terminal', {
        path: item.path,
        terminalType: defaultTerminal.current,
      });
      // ウィンドウを非表示
      await invoke('hide_window');
      setSearchQuery('');
      setDisplayQuery('');
    } catch (error) {
      console.error('Failed to open in terminal:', error);
    }
  }, []);

  // エディタ選択ウィンドウを開く
  const handleOpenEditorPickerWindow = useCallback(
    async (item: DirectoryItem) => {
      try {
        console.log(
          'Opening editor picker window for:',
          item.path,
          'editor:',
          item.editor,
        );
        await invoke('open_editor_picker_window', {
          directoryPath: item.path,
          currentEditor: item.editor || null,
        });
        // 検索バーを非表示
        await invoke('hide_window');
      } catch (error) {
        console.error('Failed to open editor picker window:', error);
      }
    },
    [],
  );

  // アプリ/ディレクトリ起動
  const handleLaunch = useCallback(
    async (item: SearchResult) => {
      try {
        // 履歴に記録
        if (searchQuery.trim()) {
          const newHistory: SelectionHistory = {
            keyword: searchQuery.trim(),
            selectedPath: item.path,
            timestamp: Date.now(),
          };

          // 新しい履歴を追加し、最大50件に制限
          const updatedHistory = [newHistory, ...selectionHistory].slice(
            0,
            MAX_HISTORY_COUNT,
          );
          setSelectionHistory(updatedHistory);
          saveHistory(updatedHistory);

          console.log('履歴に記録:', {
            keyword: searchQuery.trim(),
            path: item.path,
            name: item.name,
          });
        }

        if (isAppItem(item)) {
          await invoke('launch_app', { path: item.path });
        } else {
          await invoke('open_directory', {
            path: item.path,
            editor: item.editor,
          });
        }
        await invoke('hide_window');
        setSearchQuery('');
        setDisplayQuery('');
      } catch (error) {
        console.error('Launch error:', error);
      }
    },
    [searchQuery, selectionHistory],
  );

  const handleAppMouseDown = useCallback(
    (e: React.MouseEvent<HTMLDivElement>) => {
      if (e.button !== 0) {
        return;
      }

      const target = e.target as HTMLElement;
      const isExcluded =
        target.closest('[data-tauri-drag-region-exclude]') ||
        target.closest('.drag-exclude');

      console.log('Drag attempt', {
        tag: target.tagName,
        className: target.className,
        excluded: !!isExcluded,
        dataset: target.dataset,
      });

      if (!isExcluded) {
        appWindowRef.current.startDragging().catch((error) => {
          console.error('Failed to start window drag:', error);
        });
      }
    },
    [],
  );

  // キーボードナビゲーション
  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      console.log('handleKeyDown:', {
        key: e.key,
        isComposing,
        selectedIndex,
        resultsLength: results.length,
      });

      // Escapeキーは常に動作（ウィンドウを閉じる）
      if (e.key === 'Escape') {
        e.preventDefault();
        invoke('hide_window');
        return;
      }

      // IME入力中はナビゲーションを無効化
      if (isComposing) {
        console.log('IME composing, skipping navigation');
        return;
      }

      if (e.key === 'ArrowDown') {
        e.preventDefault();
        setSelectedIndex((prev) => Math.min(prev + 1, results.length - 1));
      } else if (e.key === 'ArrowUp') {
        e.preventDefault();
        setSelectedIndex((prev) => Math.max(prev - 1, 0));
      } else if (e.key === 'ArrowRight' && results[selectedIndex]) {
        e.preventDefault();
        // ディレクトリの場合、デフォルトターミナルで開く
        const item = results[selectedIndex];
        console.log(
          'ArrowRight pressed, item:',
          item,
          'isAppItem:',
          isAppItem(item),
        );
        if (!isAppItem(item)) {
          handleOpenInTerminal(item);
        }
      } else if (e.key === 'ArrowLeft') {
        e.preventDefault();
        console.log(
          'ArrowLeft detected! selectedIndex:',
          selectedIndex,
          'results:',
          results,
        );
        // ディレクトリの場合、エディタ選択ウィンドウを開く
        if (results[selectedIndex]) {
          const item = results[selectedIndex];
          console.log(
            'ArrowLeft pressed, item:',
            item,
            'isAppItem:',
            isAppItem(item),
          );
          if (!isAppItem(item)) {
            console.log('Opening editor picker window...');
            handleOpenEditorPickerWindow(item);
          } else {
            console.log('Item is an app, not opening editor picker');
          }
        } else {
          console.log('No item selected');
        }
      } else if (e.key === 'Enter') {
        e.preventDefault();
        // 計算結果がある場合はクリップボードにコピー
        if (calculationResult) {
          navigator.clipboard
            .writeText(String(calculationResult.result))
            .then(() => {
              console.log('Copied to clipboard:', calculationResult.result);
              // コピー後にウィンドウを閉じる
              invoke('hide_window');
              setSearchQuery('');
              setDisplayQuery('');
            })
            .catch((error) => {
              console.error('Failed to copy to clipboard:', error);
            });
        } else if (results[selectedIndex]) {
          handleLaunch(results[selectedIndex]);
        }
      }
    },
    [
      results,
      selectedIndex,
      isComposing,
      calculationResult,
      handleOpenInTerminal,
      handleLaunch,
      handleOpenEditorPickerWindow,
    ],
  );

  return (
    <div
      className="app-container"
      data-tauri-drag-region
      onMouseDown={handleAppMouseDown}
    >
      <div className="drag-bar" />
      <div className="search-box">
        <div className="search-box-content">
          <div className="app-logo">
            <img
              src="/app-icon.png"
              alt="Ignitero Launcher"
              draggable={false}
            />
          </div>
          <Space.Compact
            style={{ flex: 1 }}
            className="drag-exclude"
            data-tauri-drag-region-exclude
          >
            <Input
              ref={inputRef}
              size="large"
              placeholder="Search apps and directories"
              prefix={<SearchOutlined />}
              value={searchQuery}
              className="drag-exclude"
              data-tauri-drag-region-exclude
              onChange={(e) => {
                const value = e.target.value;
                setSearchQuery(value);
                setDisplayQuery(value);
              }}
              onKeyDown={(e) => {
                handleKeyDown(e);
              }}
              autoFocus
              autoComplete="off"
              autoCorrect="off"
              autoCapitalize="off"
              spellCheck={false}
            />
            <Tooltip title="キャッシュを更新">
              <Button
                className="icon-button-no-hover drag-exclude"
                data-tauri-drag-region-exclude
                size="large"
                icon={<ReloadOutlined />}
                onClick={() => {
                  invoke('refresh_cache').catch((error) => {
                    console.error('Failed to refresh cache:', error);
                  });
                }}
              />
            </Tooltip>
            <Tooltip title="設定">
              <Button
                className="icon-button-no-hover drag-exclude"
                data-tauri-drag-region-exclude
                size="large"
                icon={<SettingOutlined />}
                onClick={() => {
                  invoke('open_settings_window').catch((error) => {
                    console.error('Failed to open settings window:', error);
                  });
                }}
              />
            </Tooltip>
          </Space.Compact>
        </div>
      </div>

      {calculationResult && (
        <div
          className="calculation-result drag-exclude"
          data-tauri-drag-region-exclude
        >
          <div className="calculation-result-content">
            <Space>
              <CalculatorOutlined
                style={{ fontSize: '24px', color: '#1890ff' }}
              />
              <Text strong style={{ fontSize: '24px' }}>
                = {calculationResult.formatted}
              </Text>
            </Space>
            <Text
              type="secondary"
              style={{ fontSize: '12px', marginTop: '4px' }}
            >
              Enter でクリップボードにコピー
            </Text>
          </div>
        </div>
      )}

      {updateInfo && updateInfo.has_update && (
        <Alert
          className="drag-exclude"
          data-tauri-drag-region-exclude
          message={`v${updateInfo.latest_version} がリリースされています`}
          type="info"
          showIcon
          closable
          onClose={() => {
            // 通知を却下したことを記録
            if (updateInfo.latest_version) {
              invoke('dismiss_update', {
                version: updateInfo.latest_version,
              }).catch((error) => {
                console.error('Failed to dismiss update:', error);
              });
            }
            setUpdateInfo(null);
          }}
          onClick={() => {
            if (updateInfo.html_url) {
              open(updateInfo.html_url).catch((error) => {
                console.error('Failed to open URL:', error);
              });
            }
          }}
          style={{
            margin: '8px 16px 0 16px',
            cursor: updateInfo.html_url ? 'pointer' : 'default',
          }}
        />
      )}

      <div
        className="results-container drag-exclude"
        data-tauri-drag-region-exclude
      >
        <List
          dataSource={results}
          renderItem={(item, index) => {
            const isDirectory = !isAppItem(item);
            const isSelected = index === selectedIndex;

            return (
              <div
                ref={(el) => {
                  itemRefs.current[index] = el;
                }}
              >
                <List.Item
                  className={`result-item ${isSelected ? 'selected' : ''}`}
                  onClick={() => handleLaunch(item)}
                  onMouseEnter={() => setSelectedIndex(index)}
                  style={{ position: 'relative' }}
                >
                  <Space style={{ flex: 1 }}>
                    <ItemIcon item={item} />
                    <div style={{ flex: 1 }}>
                      <Text strong>{item.name}</Text>
                      <br />
                      <Text type="secondary" style={{ fontSize: '12px' }}>
                        {item.path}
                      </Text>
                      {isDirectory && item.editor && (
                        <>
                          <br />
                          <Text
                            type="secondary"
                            style={{
                              fontSize: '11px',
                              fontStyle: 'italic',
                            }}
                          >
                            {item.editor}で開く
                          </Text>
                        </>
                      )}
                    </div>
                  </Space>
                  {isDirectory && isSelected && (
                    <Button
                      icon={<MoreOutlined />}
                      size="small"
                      type="text"
                      onClick={(e) => {
                        e.stopPropagation();
                        handleOpenEditorPickerWindow(item);
                      }}
                      style={{
                        position: 'absolute',
                        right: 8,
                        top: '50%',
                        transform: 'translateY(-50%)',
                      }}
                    />
                  )}
                </List.Item>
              </div>
            );
          }}
        />
      </div>
    </div>
  );
}

export default App;
