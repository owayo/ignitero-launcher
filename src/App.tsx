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
  ArrowLeftOutlined,
  ArrowRightOutlined,
  CodeOutlined,
  FolderFilled,
  SearchOutlined,
  SettingOutlined,
  ReloadOutlined,
  CalculatorOutlined,
} from '@ant-design/icons';
import { invoke, convertFileSrc } from '@tauri-apps/api/core';
import { getCurrentWindow, LogicalSize } from '@tauri-apps/api/window';
import { listen } from '@tauri-apps/api/event';
import { open } from '@tauri-apps/plugin-shell';
import type { AppItem, DirectoryItem, WindowState, CommandItem } from './types';
import { evaluateExpression } from './calculator';
import './App.css';

const { Text } = Typography;

interface UpdateInfo {
  has_update: boolean;
  current_version: string;
  latest_version: string | null;
  html_url: string | null;
}

type SearchResult = AppItem | DirectoryItem | CommandItem;

function isAppItem(item: SearchResult): item is AppItem {
  return 'icon_path' in item;
}

function isCommandItem(item: SearchResult): item is CommandItem {
  return 'command' in item && 'alias' in item && !('path' in item);
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

// 履歴マッチング結果の型定義
interface HistoryMatch {
  frequency: number;
  matchType: 'exact' | 'prefix' | 'none';
}

// キーワードに対する選択履歴のマッチングスコアを計算
const calculateHistoryMatch = (
  currentKeyword: string,
  path: string,
  history: SelectionHistory[],
): HistoryMatch => {
  const normalizedCurrent = currentKeyword.toLowerCase().trim();

  // 完全一致の履歴をカウント
  const exactMatches = history.filter(
    (h) =>
      h.keyword.toLowerCase() === normalizedCurrent && h.selectedPath === path,
  );

  if (exactMatches.length > 0) {
    return { frequency: exactMatches.length, matchType: 'exact' };
  }

  // 前方一致の履歴をカウント（currentKeyword が履歴キーワードの前方部分）
  const prefixMatches = history.filter(
    (h) =>
      h.keyword.toLowerCase().startsWith(normalizedCurrent) &&
      h.selectedPath === path,
  );

  if (prefixMatches.length > 0) {
    return { frequency: prefixMatches.length, matchType: 'prefix' };
  }

  return { frequency: 0, matchType: 'none' };
};

// エディタアイコンキャッシュ（アプリ全体で共有）
const editorIconCache = new Map<string, string>();

// アイコンコンポーネント
const ItemIcon: React.FC<{ item: SearchResult; isSelected?: boolean }> = ({
  item,
  isSelected = false,
}) => {
  const iconStyle = {
    transition: 'transform 140ms ease, filter 160ms ease',
    transform: isSelected ? 'scale(1.25)' : 'scale(1)',
    filter: isSelected
      ? 'drop-shadow(0 2px 6px rgba(255, 120, 71, 0.18))'
      : 'none',
  };
  const [hasError, setHasError] = React.useState(false);
  const [editorIconPath, setEditorIconPath] = React.useState<string | null>(
    null,
  );

  // DirectoryItemかつeditorが設定されている場合のみeditorを取得
  const editorForDep =
    !isAppItem(item) && !isCommandItem(item) ? item.editor : undefined;

  // エディタアイコンのPNGパスを取得
  useEffect(() => {
    if (!isAppItem(item) && !isCommandItem(item) && item.editor) {
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
  }, [editorForDep]); // DirectoryItemの場合のみeditorを依存に

  // コマンドアイテムの場合は専用アイコンを表示
  if (isCommandItem(item)) {
    return (
      <CodeOutlined
        style={{ fontSize: '32px', color: '#f7a500', ...iconStyle }}
      />
    );
  }

  if (isAppItem(item)) {
    if (item.icon_path && !hasError) {
      const iconUrl = convertFileSrc(item.icon_path);
      console.log('Loading icon:', item.icon_path, '→', iconUrl);
      return (
        <img
          src={iconUrl}
          alt=""
          style={{ width: 32, height: 32, borderRadius: 4, ...iconStyle }}
          onError={() => {
            console.error('Failed to load icon:', item.icon_path, '→', iconUrl);
            setHasError(true);
          }}
        />
      );
    }
    return <AppstoreOutlined style={{ fontSize: '32px', ...iconStyle }} />;
  } else {
    // ディレクトリアイコン
    // エディタが設定されている場合、フォルダアイコンの中央にエディタアイコンを重ねる
    if (item.editor && editorIconPath) {
      const editorIconUrl = convertFileSrc(editorIconPath);

      return (
        <div
          style={{ position: 'relative', width: 32, height: 32, ...iconStyle }}
        >
          <FolderFilled
            style={{
              fontSize: '32px',
              color: '#5EB3F4',
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
    return (
      <FolderFilled
        style={{ fontSize: '32px', color: '#5EB3F4', ...iconStyle }}
      />
    );
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
          romajiCmdResults,
          kanaAppResults,
          kanaDirResults,
          kanaCmdResults,
        ] = await Promise.all([
          romajiQuery.trim()
            ? invoke<AppItem[]>('search_apps', { query: romajiQuery })
            : Promise.resolve([]),
          romajiQuery.trim()
            ? invoke<DirectoryItem[]>('search_directories', {
                query: romajiQuery,
              })
            : Promise.resolve([]),
          romajiQuery.trim()
            ? invoke<CommandItem[]>('search_commands', { query: romajiQuery })
            : Promise.resolve([]),
          kanaQuery.trim()
            ? invoke<AppItem[]>('search_apps', { query: kanaQuery })
            : Promise.resolve([]),
          kanaQuery.trim()
            ? invoke<DirectoryItem[]>('search_directories', {
                query: kanaQuery,
              })
            : Promise.resolve([]),
          kanaQuery.trim()
            ? invoke<CommandItem[]>('search_commands', { query: kanaQuery })
            : Promise.resolve([]),
        ]);

        console.log('Search results:', {
          romajiApps: romajiAppResults.length,
          romajiDirs: romajiDirResults.length,
          romajiCmds: romajiCmdResults.length,
          kanaApps: kanaAppResults.length,
          kanaDirs: kanaDirResults.length,
          kanaCmds: kanaCmdResults.length,
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

        const cmdMap = new Map<string, CommandItem>();
        [...romajiCmdResults, ...kanaCmdResults].forEach((cmd) => {
          cmdMap.set(cmd.alias, cmd);
        });

        const allResults: SearchResult[] = [
          ...Array.from(appMap.values()),
          ...Array.from(dirMap.values()),
          ...Array.from(cmdMap.values()),
        ];

        // 履歴に基づいて結果をソート（コマンドはpathがないのでaliasを使用）
        const sortedResults = allResults.sort((a, b) => {
          const keyA = isCommandItem(a) ? a.alias : a.path;
          const keyB = isCommandItem(b) ? b.alias : b.path;

          const matchA = calculateHistoryMatch(
            romajiQuery,
            keyA,
            selectionHistory,
          );
          const matchB = calculateHistoryMatch(
            romajiQuery,
            keyB,
            selectionHistory,
          );

          // 1. マッチタイプで優先度を決定（exact > prefix > none）
          const typeOrder = { exact: 2, prefix: 1, none: 0 };
          const typeCompare =
            typeOrder[matchB.matchType] - typeOrder[matchA.matchType];
          if (typeCompare !== 0) return typeCompare;

          // 2. 同じマッチタイプ内では頻度順
          return matchB.frequency - matchA.frequency;
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
  }, [
    selectedIndex,
    results.map((r) => (isCommandItem(r) ? r.alias : r.path)).join(','),
  ]);

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

  // アプリ/ディレクトリ/コマンド起動
  const handleLaunch = useCallback(
    async (item: SearchResult) => {
      try {
        // 履歴に記録（コマンドの場合はaliasを使用）
        if (searchQuery.trim()) {
          const selectedKey = isCommandItem(item) ? item.alias : item.path;
          const newHistory: SelectionHistory = {
            keyword: searchQuery.trim(),
            selectedPath: selectedKey,
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
            selectedKey,
            name: isCommandItem(item) ? item.alias : item.name,
          });
        }

        if (isCommandItem(item)) {
          // コマンドを実行
          await invoke('execute_command', {
            command: item.command,
            workingDirectory: item.working_directory,
          });
        } else if (isAppItem(item)) {
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
        // ディレクトリの場合、デフォルトターミナルで開く（コマンドは対象外）
        const item = results[selectedIndex];
        console.log(
          'ArrowRight pressed, item:',
          item,
          'isAppItem:',
          isAppItem(item),
          'isCommandItem:',
          isCommandItem(item),
        );
        if (!isAppItem(item) && !isCommandItem(item)) {
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
        // ディレクトリの場合、エディタ選択ウィンドウを開く（コマンドは対象外）
        if (results[selectedIndex]) {
          const item = results[selectedIndex];
          console.log(
            'ArrowLeft pressed, item:',
            item,
            'isAppItem:',
            isAppItem(item),
            'isCommandItem:',
            isCommandItem(item),
          );
          if (!isAppItem(item) && !isCommandItem(item)) {
            console.log('Opening editor picker window...');
            handleOpenEditorPickerWindow(item);
          } else {
            console.log('Item is an app or command, not opening editor picker');
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
                style={{ fontSize: '24px', color: '#e4572e' }}
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
            const isCommand = isCommandItem(item);
            const isDirectory = !isAppItem(item) && !isCommand;
            const isSelected = index === selectedIndex;

            // 表示名とサブテキストを決定
            const displayName = isCommand ? item.alias : item.name;
            const subText = isCommand ? item.command : item.path;

            return (
              <div
                ref={(el) => {
                  itemRefs.current[index] = el;
                }}
              >
                <List.Item
                  className={`result-item ${isSelected ? 'selected' : ''}`}
                  style={{ position: 'relative' }}
                >
                  <Space style={{ flex: 1 }}>
                    <ItemIcon item={item} isSelected={isSelected} />
                    <div style={{ flex: 1 }}>
                      <Text
                        strong
                        style={{
                          fontSize: isSelected ? 17 : 14,
                          fontWeight: isSelected ? 600 : 500,
                          transition:
                            'font-size 140ms ease, font-weight 140ms ease',
                        }}
                      >
                        {displayName}
                      </Text>
                      <br />
                      <Text
                        type="secondary"
                        style={{
                          fontSize: '12px',
                          ...(isCommand && {
                            fontFamily: 'monospace',
                            wordBreak: 'break-all',
                          }),
                        }}
                      >
                        {subText}
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
                      {isCommand && item.working_directory && (
                        <>
                          <br />
                          <Text
                            type="secondary"
                            style={{
                              fontSize: '11px',
                              display: 'flex',
                              alignItems: 'center',
                              gap: '4px',
                            }}
                          >
                            <FolderFilled style={{ fontSize: '11px' }} />
                            {item.working_directory}
                          </Text>
                        </>
                      )}
                    </div>
                  </Space>
                  {isDirectory && isSelected && (
                    <div
                      style={{
                        position: 'absolute',
                        right: 8,
                        top: '50%',
                        transform: 'translateY(-50%)',
                        display: 'flex',
                        alignItems: 'center',
                        gap: 8,
                      }}
                    >
                      <div
                        style={{
                          display: 'flex',
                          alignItems: 'center',
                          gap: 4,
                          padding: '2px 8px',
                          borderRadius: 4,
                          border: '1px solid rgba(255, 120, 71, 0.4)',
                          background: 'rgba(255, 255, 255, 0.8)',
                          fontSize: 11,
                          color: 'rgba(60, 60, 70, 0.8)',
                        }}
                      >
                        <ArrowLeftOutlined style={{ fontSize: 10 }} />
                        <span>エディタ選択</span>
                      </div>
                      <div
                        style={{
                          display: 'flex',
                          alignItems: 'center',
                          gap: 4,
                          padding: '2px 8px',
                          borderRadius: 4,
                          border: '1px solid rgba(255, 120, 71, 0.4)',
                          background: 'rgba(255, 255, 255, 0.8)',
                          fontSize: 11,
                          color: 'rgba(60, 60, 70, 0.8)',
                        }}
                      >
                        <ArrowRightOutlined style={{ fontSize: 10 }} />
                        <span>ターミナル</span>
                      </div>
                    </div>
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
