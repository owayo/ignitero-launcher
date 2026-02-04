import { CodeOutlined } from '@ant-design/icons';
import { convertFileSrc, invoke } from '@tauri-apps/api/core';
import type React from 'react';
import { useCallback, useEffect, useState } from 'react';
import type { EditorInfo, TerminalType } from './types';
import './index.css';

export const TerminalPickerWindow: React.FC = () => {
  const [terminals, setTerminals] = useState<EditorInfo[]>([]);
  const [selectedIndex, setSelectedIndex] = useState(0);
  const [terminalIcons, setTerminalIcons] = useState<Map<string, string>>(
    new Map(),
  );
  const [directoryPath, setDirectoryPath] = useState<string>('');

  // URLのクエリパラメータからディレクトリパスを取得
  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const path = params.get('path');
    if (path) {
      setDirectoryPath(decodeURIComponent(path));
    }
  }, []);

  // ターミナル一覧を取得
  useEffect(() => {
    const fetchTerminals = async () => {
      try {
        const terminalList = await invoke<EditorInfo[]>('get_terminal_list');
        setTerminals(terminalList);

        // アイコンを取得
        const iconMap = new Map<string, string>();
        await Promise.all(
          terminalList.map(async (terminal) => {
            try {
              const iconPath = await invoke<string | null>(
                'get_terminal_icon_path',
                { terminal: terminal.id },
              );
              if (iconPath) {
                iconMap.set(terminal.id, iconPath);
              }
            } catch (error) {
              console.error(`Failed to get icon for ${terminal.id}:`, error);
            }
          }),
        );

        setTerminalIcons(iconMap);
      } catch (error) {
        console.error('Failed to fetch terminals:', error);
      }
    };

    fetchTerminals();
  }, []);

  // handleClose を useCallback でラップ
  const handleClose = useCallback(async () => {
    try {
      await invoke('close_terminal_picker_window');
    } catch (error) {
      console.error('Failed to close picker window:', error);
    }
  }, []);

  // handleSelectTerminal を useCallback でラップ
  const handleSelectTerminal = useCallback(
    async (terminalId: string) => {
      try {
        if (!directoryPath) {
          console.error('No directory path set');
          return;
        }

        await invoke('open_in_terminal', {
          path: directoryPath,
          terminalType: terminalId as TerminalType,
        });

        await invoke('hide_window');
        await handleClose();
      } catch (error) {
        console.error('Failed to open with terminal:', error);
      }
    },
    [directoryPath, handleClose],
  );

  // キーボード操作
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'ArrowUp') {
        e.preventDefault();
        setSelectedIndex((prev) =>
          prev === 0 ? terminals.length - 1 : prev - 1,
        );
      } else if (e.key === 'ArrowDown') {
        e.preventDefault();
        setSelectedIndex((prev) =>
          prev === terminals.length - 1 ? 0 : prev + 1,
        );
      } else if (e.key === 'ArrowLeft') {
        e.preventDefault();
        setSelectedIndex((prev) =>
          prev === 0 ? terminals.length - 1 : prev - 1,
        );
      } else if (e.key === 'ArrowRight') {
        e.preventDefault();
        setSelectedIndex((prev) =>
          prev === terminals.length - 1 ? 0 : prev + 1,
        );
      } else if (e.key === 'Enter') {
        e.preventDefault();
        const selected = terminals[selectedIndex];
        if (selected && directoryPath) {
          handleSelectTerminal(selected.id);
        }
      } else if (e.key === 'Escape') {
        e.preventDefault();
        handleClose();
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [
    terminals,
    selectedIndex,
    directoryPath,
    handleClose,
    handleSelectTerminal,
  ]);

  if (terminals.length === 0) {
    return null;
  }

  const radius = 120;
  const centerX = 200;
  const centerY = 130;
  const iconSize = 48;
  const pathTop = 15;
  const pathHeight = 36;
  const gapBetweenPathAndCircle = 10;
  const svgTop = pathTop + pathHeight + gapBetweenPathAndCircle;

  // 各ターミナルの角度を計算
  const angleStep = (2 * Math.PI) / terminals.length;

  return (
    // biome-ignore lint/a11y/noStaticElementInteractions: overlay backdrop dismiss pattern
    // biome-ignore lint/a11y/useKeyWithClickEvents: keyboard handled via global keydown listener
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
      {/* biome-ignore lint/a11y/noStaticElementInteractions: container stops event propagation */}
      {/* biome-ignore lint/a11y/useKeyWithClickEvents: keyboard handled via global keydown listener */}
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
          role="img"
          aria-label="ターミナル選択"
        >
          <title>ターミナル選択</title>
          <defs>
            {/* 背景円のグラデーション - ターミナル用にブルー系 */}
            <radialGradient id="circleGradient" cx="50%" cy="50%" r="65%">
              <stop offset="0%" stopColor="rgba(245, 250, 255, 0.92)" />
              <stop offset="60%" stopColor="rgba(245, 250, 255, 0.92)" />
              <stop offset="100%" stopColor="rgba(130, 180, 255, 0.55)" />
            </radialGradient>

            {/* 選択セクションのグラデーション */}
            <linearGradient
              id="selectionGradient"
              x1="0%"
              x2="100%"
              y1="0%"
              y2="0%"
            >
              <stop offset="0%" stopColor="rgba(71, 120, 255, 0.35)" />
              <stop offset="100%" stopColor="rgba(71, 179, 255, 0.28)" />
            </linearGradient>
          </defs>

          {/* 背景円 */}
          <circle
            cx={centerX}
            cy={centerY}
            r={radius}
            fill="url(#circleGradient)"
            stroke="rgba(71, 120, 255, 0.9)"
            strokeWidth="3"
            opacity="0.98"
          />

          {/* 各ターミナルのセクション */}
          {terminals.map((terminal, index) => {
            const startAngle = index * angleStep - Math.PI / 2;
            const endAngle = (index + 1) * angleStep - Math.PI / 2;
            const isSelected = index === selectedIndex;

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
              <g key={terminal.id}>
                {/* biome-ignore lint/a11y/noStaticElementInteractions: SVG path sector in circular picker */}
                <path
                  d={pathData}
                  fill={isSelected ? 'url(#selectionGradient)' : 'transparent'}
                  fillOpacity={isSelected ? 1 : 0}
                  stroke="rgba(71, 120, 255, 0.35)"
                  strokeWidth="1.25"
                  style={{
                    cursor: 'pointer',
                    transition: 'all 0.2s',
                  }}
                  onClick={() => handleSelectTerminal(terminal.id)}
                  onMouseEnter={() => setSelectedIndex(index)}
                />
                {index < terminals.length && (
                  <line
                    x1={centerX}
                    y1={centerY}
                    x2={x1}
                    y2={y1}
                    stroke="rgba(71, 120, 255, 0.3)"
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
            stroke="rgba(71, 120, 255, 0.9)"
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
          <div />
        </div>

        {/* ターミナルアイコンとラベル */}
        {terminals.map((terminal, index) => {
          const angle = index * angleStep + angleStep / 2 - Math.PI / 2;
          const distance = radius * 0.7;
          const x = centerX + distance * Math.cos(angle);
          const y = centerY + distance * Math.sin(angle) + svgTop;
          const isSelected = index === selectedIndex;
          const iconPath = terminalIcons.get(terminal.id);

          return (
            // biome-ignore lint/a11y/useKeyWithClickEvents: keyboard handled via global keydown listener
            // biome-ignore lint/a11y/noStaticElementInteractions: absolutely positioned circular picker item
            <div
              key={terminal.id}
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
              onClick={() => handleSelectTerminal(terminal.id)}
              onMouseEnter={() => setSelectedIndex(index)}
            >
              {iconPath ? (
                <img
                  src={convertFileSrc(iconPath)}
                  alt={terminal.name}
                  style={{
                    width: iconSize,
                    height: iconSize,
                    borderRadius: 8,
                    border: isSelected
                      ? '3px solid rgba(71, 120, 255, 0.95)'
                      : 'none',
                    boxShadow: isSelected
                      ? '0 6px 14px rgba(71, 120, 255, 0.28)'
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
                      ? '3px solid rgba(71, 120, 255, 0.95)'
                      : '1px solid #ccc',
                    background: 'white',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    fontSize: 24,
                    boxShadow: isSelected
                      ? '0 6px 14px rgba(71, 120, 255, 0.28)'
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
                  color: isSelected ? '#1044c2' : '#333',
                  textAlign: 'center',
                  background: 'white',
                  padding: '3px 8px',
                  borderRadius: 6,
                  boxShadow: isSelected
                    ? '0 2px 8px rgba(71, 120, 255, 0.3)'
                    : '0 1px 4px rgba(0, 0, 0, 0.1)',
                  whiteSpace: 'nowrap',
                }}
              >
                {terminal.name}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
};
