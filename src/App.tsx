import React, { useState, useEffect, useCallback, useRef } from 'react';
import { Input, List, Typography, Space, Button, Tooltip } from 'antd';
import {
  AppstoreOutlined,
  FolderFilled,
  SearchOutlined,
  SettingOutlined,
  ReloadOutlined,
} from '@ant-design/icons';
import { invoke, convertFileSrc } from '@tauri-apps/api/core';
import { getCurrentWindow, LogicalSize } from '@tauri-apps/api/window';
import { listen } from '@tauri-apps/api/event';
import type { AppItem, DirectoryItem } from './types';
import { toRomaji } from 'wanakana';
import './App.css';

const { Text } = Typography;

type SearchResult = AppItem | DirectoryItem;

function isAppItem(item: SearchResult): item is AppItem {
  return 'icon_path' in item;
}

// 文字列を検索用に正規化（全角→半角、小文字化）
function normalizeForSearch(str: string): string {
  return str
    .replace(/[Ａ-Ｚａ-ｚ０-９]/g, (s) => {
      return String.fromCharCode(s.charCodeAt(0) - 0xfee0);
    })
    .toLowerCase();
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
  const [isComposing, setIsComposing] = useState(false);
  const [selectionHistory, setSelectionHistory] = useState<SelectionHistory[]>(
    () => loadHistory(),
  );
  const inputRef = React.useRef<any>(null);
  const shouldForceIME = React.useRef(true);
  const compBuffer = React.useRef(''); // IME未確定文字列のバッファ
  const compositionBaseRef = React.useRef(''); // IME開始前の検索クエリ
  const itemRefs = useRef<(HTMLDivElement | null)[]>([]); // リスト項目のref配列
  const defaultTerminal = useRef<'terminal' | 'iterm2' | 'warp'>('terminal'); // デフォルトターミナル

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

  // 検索処理
  const performSearch = useCallback(
    async (
      romajiQuery: string,
      kanaQuery: string,
      composing: boolean = false,
    ) => {
      console.log('performSearch called:', {
        romajiQuery,
        kanaQuery,
        composing,
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
        // サイズ変更後に中央配置を維持
        await appWindow.center();
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

    const unlisten = appWindow.onFocusChanged(({ payload: focused }) => {
      if (focused) {
        // 初回フォーカス時のみ英字入力モードに切り替え
        if (shouldForceIME.current) {
          shouldForceIME.current = false;
          invoke('force_english_input_wrapper').catch((error) => {
            console.error('Failed to switch to English input:', error);
          });
        }

        // 検索欄にフォーカスを設定
        setTimeout(() => {
          inputRef.current?.focus();
        }, 100);
      } else {
        // ウィンドウが非表示またはフォーカスを失ったら検索欄をクリアし、フラグをリセット
        shouldForceIME.current = true;
        setSearchQuery('');
        setDisplayQuery('');
        setResults([]);
        setSelectedIndex(0);
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
        terminal_type: defaultTerminal.current,
      });
      // ウィンドウを非表示
      await invoke('hide_window');
      setSearchQuery('');
      setDisplayQuery('');
    } catch (error) {
      console.error('Failed to open in terminal:', error);
    }
  }, []);

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
        // ディレクトリの場合、ターミナルで開く
        const item = results[selectedIndex];
        console.log(
          'ArrowRight pressed, item:',
          item,
          'isAppItem:',
          isAppItem(item),
        );
        if (!isAppItem(item)) {
          console.log(
            'Opening in terminal:',
            item.path,
            'terminal:',
            defaultTerminal.current,
          );
          handleOpenInTerminal(item);
        }
      } else if (e.key === 'Enter' && results[selectedIndex]) {
        e.preventDefault();
        handleLaunch(results[selectedIndex]);
      }
    },
    [results, selectedIndex, isComposing, handleOpenInTerminal, handleLaunch],
  );

  return (
    <div className="app-container">
      <div className="search-box">
        <div className="search-box-content">
          <div className="app-logo">
            <img src="/app-icon.png" alt="Ignitero Launcher" />
          </div>
          <Space.Compact style={{ flex: 1 }}>
            <Input
              ref={inputRef}
              size="large"
              placeholder="Search apps and directories"
              prefix={<SearchOutlined />}
              value={displayQuery}
              onChange={(e) => {
                const value = e.target.value;
                setDisplayQuery(value);
                // かな文字をローマ字に変換して検索クエリを更新
                const romajiValue = normalizeForSearch(toRomaji(value));
                const finalQuery = isComposing
                  ? compositionBaseRef.current + romajiValue
                  : romajiValue;
                console.log('onChange:', {
                  value,
                  romajiValue,
                  isComposing,
                  compositionBase: compositionBaseRef.current,
                  finalQuery,
                });
                setSearchQuery(finalQuery);
              }}
              onKeyDown={(e) => {
                handleKeyDown(e);
              }}
              onCompositionStart={() => {
                compositionBaseRef.current = searchQuery;
                setIsComposing(true);
              }}
              onCompositionUpdate={(e) => {
                const currentVisible = e.currentTarget.value;
                setDisplayQuery(currentVisible);
                const romajiPart = normalizeForSearch(toRomaji(currentVisible));
                setSearchQuery(compositionBaseRef.current + romajiPart);
              }}
              onCompositionEnd={(e) => {
                const finalVisible = e.currentTarget.value;
                const romajiPart = normalizeForSearch(toRomaji(finalVisible));
                setSearchQuery(compositionBaseRef.current + romajiPart);
                // 日本語入力を許可するため、displayQueryはクリアしない
                compBuffer.current = '';
                setIsComposing(false);
              }}
              autoFocus
              autoComplete="off"
              autoCorrect="off"
              autoCapitalize="off"
              spellCheck={false}
            />
            <Tooltip title="キャッシュを更新">
              <Button
                size="large"
                icon={<ReloadOutlined />}
                onClick={() => {
                  invoke('refresh_cache').catch((error) => {
                    console.error('Failed to refresh cache:', error);
                  });
                }}
                className="icon-button-no-hover"
              />
            </Tooltip>
            <Tooltip title="設定">
              <Button
                size="large"
                icon={<SettingOutlined />}
                onClick={() => {
                  invoke('open_settings_window').catch((error) => {
                    console.error('Failed to open settings window:', error);
                  });
                }}
                className="icon-button-no-hover"
              />
            </Tooltip>
          </Space.Compact>
        </div>
      </div>

      <div className="results-container">
        <List
          dataSource={results}
          renderItem={(item, index) => (
            <div ref={(el) => (itemRefs.current[index] = el)}>
              <List.Item
                className={`result-item ${index === selectedIndex ? 'selected' : ''}`}
                onClick={() => handleLaunch(item)}
                onMouseEnter={() => setSelectedIndex(index)}
              >
                <Space>
                  <ItemIcon item={item} />
                  <div>
                    <Text strong>{item.name}</Text>
                    <br />
                    <Text type="secondary" style={{ fontSize: '12px' }}>
                      {item.path}
                    </Text>
                    {!isAppItem(item) && item.editor && (
                      <>
                        <br />
                        <Text
                          type="secondary"
                          style={{ fontSize: '11px', fontStyle: 'italic' }}
                        >
                          {item.editor}で開く
                        </Text>
                      </>
                    )}
                  </div>
                </Space>
              </List.Item>
            </div>
          )}
        />
      </div>
    </div>
  );
}

export default App;
