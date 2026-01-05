import { CodeOutlined } from '@ant-design/icons';
import { convertFileSrc, invoke } from '@tauri-apps/api/core';
import type React from 'react';
import { useCallback, useEffect, useState } from 'react';
import type { EditorInfo } from './types';
import './index.css';

export const EditorPickerWindow: React.FC = () => {
  const [editors, setEditors] = useState<EditorInfo[]>([]);
  const [selectedIndex, setSelectedIndex] = useState(0);
  const [editorIcons, setEditorIcons] = useState<Map<string, string>>(
    new Map(),
  );
  const [directoryPath, setDirectoryPath] = useState<string>('');

  // URLのクエリパラメータからディレクトリパスと現在のエディタを取得
  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const path = params.get('path');
    const editor = params.get('editor');
    console.log('Getting parameters from URL:', { path, editor });
    if (path) {
      setDirectoryPath(decodeURIComponent(path));
      console.log('Directory path set to:', decodeURIComponent(path));
    }
    if (editor) {
      const decodedEditor = decodeURIComponent(editor);
      console.log('Current editor from URL:', decodedEditor);
      // エディタ一覧が読み込まれた後に初期選択を設定
      setCurrentEditorId(decodedEditor);
    }
  }, []);

  const [currentEditorId, setCurrentEditorId] = useState<string | null>(null);

  // エディタ一覧が読み込まれたら、現在のエディタを選択
  useEffect(() => {
    if (editors.length > 0 && currentEditorId) {
      const index = editors.findIndex((e) => e.id === currentEditorId);
      if (index !== -1) {
        console.log('Setting initial selection to:', editors[index].name);
        setSelectedIndex(index);
      }
    }
  }, [editors, currentEditorId]);

  // エディタ一覧を取得
  useEffect(() => {
    const fetchEditors = async () => {
      try {
        const editorList = await invoke<EditorInfo[]>('get_editor_list');
        setEditors(editorList);

        // アイコンを取得
        const iconMap = new Map<string, string>();
        await Promise.all(
          editorList.map(async (editor) => {
            try {
              const iconPath = await invoke<string | null>(
                'get_editor_icon_path',
                { editor: editor.id },
              );
              if (iconPath) {
                iconMap.set(editor.id, iconPath);
              }
            } catch (error) {
              console.error(`Failed to get icon for ${editor.id}:`, error);
            }
          }),
        );

        setEditorIcons(iconMap);
      } catch (error) {
        console.error('Failed to fetch editors:', error);
      }
    };

    fetchEditors();
  }, []);

  // handleClose を useCallback でラップ
  const handleClose = useCallback(async () => {
    try {
      await invoke('close_editor_picker_window');
    } catch (error) {
      console.error('Failed to close picker window:', error);
    }
  }, []);

  // handleSelectEditor を useCallback でラップ
  const handleSelectEditor = useCallback(
    async (editorId: string) => {
      try {
        console.log('handleSelectEditor called:', {
          editorId,
          directoryPath,
        });

        if (!directoryPath) {
          console.error('No directory path set');
          return;
        }

        await invoke('open_directory', {
          path: directoryPath,
          editor: editorId,
        });

        console.log('open_directory succeeded, hiding main window');
        await invoke('hide_window');

        console.log('Closing editor picker window');
        await handleClose();
      } catch (error) {
        console.error('Failed to open with editor:', error);
      }
    },
    [directoryPath, handleClose],
  );

  // キーボード操作
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      // 頭文字キーでエディタを直接選択
      const key = e.key.toLowerCase();
      const editorShortcuts: { [key: string]: string } = {
        w: 'windsurf',
        c: 'cursor',
        v: 'code',
        a: 'antigravity',
      };

      if (editorShortcuts[key]) {
        e.preventDefault();
        const editorId = editorShortcuts[key];
        const editor = editors.find((e) => e.id === editorId);
        if (editor && directoryPath) {
          console.log(
            `Shortcut key '${key}' pressed, opening with ${editor.name}`,
          );
          handleSelectEditor(editor.id);
        }
        return;
      }

      if (e.key === 'ArrowUp') {
        e.preventDefault();
        setSelectedIndex((prev) =>
          prev === 0 ? editors.length - 1 : prev - 1,
        );
      } else if (e.key === 'ArrowDown') {
        e.preventDefault();
        setSelectedIndex((prev) =>
          prev === editors.length - 1 ? 0 : prev + 1,
        );
      } else if (e.key === 'ArrowLeft') {
        e.preventDefault();
        setSelectedIndex((prev) =>
          prev === 0 ? editors.length - 1 : prev - 1,
        );
      } else if (e.key === 'ArrowRight') {
        e.preventDefault();
        setSelectedIndex((prev) =>
          prev === editors.length - 1 ? 0 : prev + 1,
        );
      } else if (e.key === 'Enter') {
        e.preventDefault();
        const selected = editors[selectedIndex];
        if (selected && directoryPath) {
          handleSelectEditor(selected.id);
        }
      } else if (e.key === 'Escape') {
        e.preventDefault();
        handleClose();
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [editors, selectedIndex, directoryPath, handleClose, handleSelectEditor]);

  if (editors.length === 0) {
    return null;
  }

  const radius = 120;
  const centerX = 200;
  const centerY = 130; // SVG内での円の中心Y座標（上に移動）
  const iconSize = 48;
  const pathTop = 15; // パス表示の上端位置
  const pathHeight = 36; // パス表示の高さ（padding込み）
  const gapBetweenPathAndCircle = 10; // パスと円の間隔
  const svgTop = pathTop + pathHeight + gapBetweenPathAndCircle; // SVGの開始位置（61px）

  // 各エディタの角度を計算
  const angleStep = (2 * Math.PI) / editors.length;

  return (
    <div
      style={{
        width: '100%',
        height: '100%',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        background: 'transparent',
      }}
      onClick={handleClose}
    >
      <div
        style={{
          position: 'relative',
          width: 400,
          height: 450,
        }}
        onClick={(e) => e.stopPropagation()}
      >
        {/* パス表示 */}
        <div
          style={{
            position: 'absolute',
            top: pathTop,
            left: '50%',
            transform: 'translateX(-50%)',
            background: 'white',
            padding: '10px 16px',
            borderRadius: 10,
            boxShadow: '0 4px 12px rgba(0, 0, 0, 0.1)',
            fontSize: 14,
            color: '#1f1f1f',
            maxWidth: '85%',
            overflow: 'hidden',
            textOverflow: 'ellipsis',
            whiteSpace: 'nowrap',
            border: '1px solid #e0e0e0',
            fontWeight: '500',
          }}
        >
          {directoryPath}
        </div>
        <svg
          width="400"
          height="400"
          style={{ position: 'absolute', top: svgTop, left: 0 }}
        >
          <defs>
            {/* 背景円のグラデーション */}
            <radialGradient id="circleGradient" cx="50%" cy="50%" r="65%">
              <stop offset="0%" stopColor="rgba(255, 250, 245, 0.92)" />
              <stop offset="60%" stopColor="rgba(255, 250, 245, 0.92)" />
              <stop offset="100%" stopColor="rgba(255, 180, 130, 0.55)" />
            </radialGradient>

            {/* 選択セクションのグラデーション */}
            <linearGradient
              id="selectionGradient"
              x1="0%"
              x2="100%"
              y1="0%"
              y2="0%"
            >
              <stop offset="0%" stopColor="rgba(255, 120, 71, 0.35)" />
              <stop offset="100%" stopColor="rgba(255, 179, 71, 0.28)" />
            </linearGradient>
          </defs>

          {/* 背景円 */}
          <circle
            cx={centerX}
            cy={centerY}
            r={radius}
            fill="url(#circleGradient)"
            stroke="rgba(255, 120, 71, 0.9)"
            strokeWidth="3"
            opacity="0.98"
          />

          {/* 各エディタのセクション */}
          {editors.map((editor, index) => {
            const startAngle = index * angleStep - Math.PI / 2;
            const endAngle = (index + 1) * angleStep - Math.PI / 2;
            const isSelected = index === selectedIndex;

            // 扇形のパスを計算
            const x1 = centerX + radius * Math.cos(startAngle);
            const y1 = centerY + radius * Math.sin(startAngle);
            const x2 = centerX + radius * Math.cos(endAngle);
            const y2 = centerY + radius * Math.sin(endAngle);

            const largeArcFlag = angleStep > Math.PI ? 1 : 0;

            const pathData = `
              M ${centerX} ${centerY}
              L ${x1} ${y1}
              A ${radius} ${radius} 0 ${largeArcFlag} 1 ${x2} ${y2}
              Z
            `;

            return (
              <g key={editor.id}>
                {/* セクション */}
                <path
                  d={pathData}
                  fill={isSelected ? 'url(#selectionGradient)' : 'transparent'}
                  fillOpacity={isSelected ? 1 : 0}
                  stroke="rgba(255, 120, 71, 0.35)"
                  strokeWidth="1.25"
                  style={{
                    cursor: 'pointer',
                    transition: 'all 0.2s',
                  }}
                  onClick={() => handleSelectEditor(editor.id)}
                  onMouseEnter={() => setSelectedIndex(index)}
                />

                {/* 境界線 */}
                {index < editors.length && (
                  <line
                    x1={centerX}
                    y1={centerY}
                    x2={x1}
                    y2={y1}
                    stroke="rgba(255, 120, 71, 0.3)"
                    strokeWidth="1.5"
                  />
                )}
              </g>
            );
          })}

          {/* 中央の円 */}
          <circle
            cx={centerX}
            cy={centerY}
            r={60}
            fill="rgba(255, 255, 255, 0.95)"
            stroke="rgba(255, 120, 71, 0.9)"
            strokeWidth="3"
          />
        </svg>

        {/* 中央のキーボードアイコン */}
        <div
          style={{
            position: 'absolute',
            left: centerX,
            top: svgTop + centerY,
            transform: 'translate(-50%, -50%)',
            display: 'grid',
            gridTemplateColumns: 'repeat(3, 24px)',
            gridTemplateRows: 'repeat(2, 24px)',
            gap: 2,
            pointerEvents: 'none',
          }}
        >
          {/* 空白 */}
          <div />
          {/* ↑ */}
          <div
            style={{
              background: 'white',
              border: '1px solid #d0d0d0',
              borderRadius: 4,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              fontSize: 16,
              color: '#666',
              boxShadow:
                '0 2px 4px rgba(0, 0, 0, 0.1), inset 0 -2px 2px rgba(0, 0, 0, 0.05)',
            }}
          >
            ↑
          </div>
          {/* 空白 */}
          <div />
          {/* ← */}
          <div
            style={{
              background: 'white',
              border: '1px solid #d0d0d0',
              borderRadius: 4,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              fontSize: 16,
              color: '#666',
              boxShadow:
                '0 2px 4px rgba(0, 0, 0, 0.1), inset 0 -2px 2px rgba(0, 0, 0, 0.05)',
            }}
          >
            ←
          </div>
          {/* ↓ */}
          <div
            style={{
              background: 'white',
              border: '1px solid #d0d0d0',
              borderRadius: 4,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              fontSize: 16,
              color: '#666',
              boxShadow:
                '0 2px 4px rgba(0, 0, 0, 0.1), inset 0 -2px 2px rgba(0, 0, 0, 0.05)',
            }}
          >
            ↓
          </div>
          {/* → */}
          <div
            style={{
              background: 'white',
              border: '1px solid #d0d0d0',
              borderRadius: 4,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              fontSize: 16,
              color: '#666',
              boxShadow:
                '0 2px 4px rgba(0, 0, 0, 0.1), inset 0 -2px 2px rgba(0, 0, 0, 0.05)',
            }}
          >
            →
          </div>
          {/* 空白 */}
          <div />
        </div>

        {/* エディタアイコンとラベル */}
        {editors.map((editor, index) => {
          const angle = index * angleStep + angleStep / 2 - Math.PI / 2;
          const distance = radius * 0.7;
          const x = centerX + distance * Math.cos(angle);
          const y = centerY + distance * Math.sin(angle) + svgTop;
          const isSelected = index === selectedIndex;
          const iconPath = editorIcons.get(editor.id);

          return (
            <div
              key={editor.id}
              style={{
                position: 'absolute',
                left: x - iconSize / 2,
                top: y - iconSize / 2,
                width: iconSize,
                height: iconSize,
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                cursor: 'pointer',
                transition: 'transform 0.2s',
                transform: isSelected ? 'scale(1.3)' : 'scale(1)',
              }}
              onClick={() => handleSelectEditor(editor.id)}
              onMouseEnter={() => setSelectedIndex(index)}
            >
              {iconPath ? (
                <img
                  src={convertFileSrc(iconPath)}
                  alt={editor.name}
                  style={{
                    width: iconSize,
                    height: iconSize,
                    borderRadius: 8,
                    border: isSelected
                      ? '3px solid rgba(255, 120, 71, 0.95)'
                      : 'none',
                    boxShadow: isSelected
                      ? '0 6px 14px rgba(255, 120, 71, 0.28)'
                      : '0 2px 8px rgba(0, 0, 0, 0.15)',
                  }}
                />
              ) : (
                <div
                  style={{
                    width: iconSize,
                    height: iconSize,
                    borderRadius: 8,
                    border: isSelected
                      ? '3px solid rgba(255, 120, 71, 0.95)'
                      : '1px solid #ccc',
                    background: 'white',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    fontSize: 24,
                    boxShadow: isSelected
                      ? '0 6px 14px rgba(255, 120, 71, 0.28)'
                      : '0 2px 8px rgba(0, 0, 0, 0.15)',
                  }}
                >
                  <CodeOutlined />
                </div>
              )}
              <div
                style={{
                  marginTop: 6,
                  fontSize: 12,
                  fontWeight: isSelected ? 'bold' : 'normal',
                  color: isSelected ? '#c24410' : '#333',
                  textAlign: 'center',
                  background: 'white',
                  padding: '3px 8px',
                  borderRadius: 6,
                  boxShadow: isSelected
                    ? '0 2px 8px rgba(24, 144, 255, 0.3)'
                    : '0 1px 4px rgba(0, 0, 0, 0.1)',
                  whiteSpace: 'nowrap',
                }}
              >
                {editor.name}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
};
