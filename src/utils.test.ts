import { beforeEach, describe, expect, it } from 'vitest';
import type { AppItem, CommandItem, DirectoryItem } from './types';

// ユーティリティ関数を再定義（App.tsxから抽出）
type SearchResult = AppItem | DirectoryItem | CommandItem;

function isAppItem(item: SearchResult): item is AppItem {
  return 'icon_path' in item;
}

function isCommandItem(item: SearchResult): item is CommandItem {
  return 'command' in item && 'alias' in item && !('path' in item);
}

interface SelectionHistory {
  keyword: string;
  selectedPath: string;
  timestamp: number;
}

function calculateFrequency(
  keyword: string,
  path: string,
  history: SelectionHistory[],
): number {
  return history.filter(
    (h) =>
      h.keyword.toLowerCase() === keyword.toLowerCase() &&
      h.selectedPath === path,
  ).length;
}

describe('Utility Functions', () => {
  describe('isAppItem', () => {
    it('should return true for AppItem', () => {
      const appItem: AppItem = {
        name: 'Safari',
        path: '/Applications/Safari.app',
        icon_path: undefined,
      };

      expect(isAppItem(appItem)).toBe(true);
    });

    it('should return false for DirectoryItem', () => {
      const dirItem: DirectoryItem = {
        name: 'Projects',
        path: '/Users/test/Projects',
        editor: undefined,
      };

      expect(isAppItem(dirItem)).toBe(false);
    });

    it('should handle item with icon_path', () => {
      const appItem: AppItem = {
        name: 'Safari',
        path: '/Applications/Safari.app',
        icon_path: '/path/to/icon.png',
      };

      expect(isAppItem(appItem)).toBe(true);
    });

    it('should return false for CommandItem', () => {
      const cmdItem: CommandItem = {
        alias: 'dev',
        command: 'pnpm dev',
      };

      expect(isAppItem(cmdItem)).toBe(false);
    });
  });

  describe('isCommandItem', () => {
    it('should return true for CommandItem', () => {
      const cmdItem: CommandItem = {
        alias: 'dev',
        command: 'pnpm dev',
      };

      expect(isCommandItem(cmdItem)).toBe(true);
    });

    it('should return true for CommandItem with working_directory', () => {
      const cmdItem: CommandItem = {
        alias: 'build',
        command: 'pnpm build',
        working_directory: '/Users/test/project',
      };

      expect(isCommandItem(cmdItem)).toBe(true);
    });

    it('should return false for AppItem', () => {
      const appItem: AppItem = {
        name: 'Safari',
        path: '/Applications/Safari.app',
        icon_path: undefined,
      };

      expect(isCommandItem(appItem)).toBe(false);
    });

    it('should return false for DirectoryItem', () => {
      const dirItem: DirectoryItem = {
        name: 'Projects',
        path: '/Users/test/Projects',
        editor: undefined,
      };

      expect(isCommandItem(dirItem)).toBe(false);
    });

    it('should return false for item with path property even if it has command and alias', () => {
      // This tests the !('path' in item) condition
      const mixedItem = {
        alias: 'test',
        command: 'test command',
        path: '/some/path',
      };

      expect(isCommandItem(mixedItem as SearchResult)).toBe(false);
    });

    it('should return false for item with only command property', () => {
      const partialItem = {
        command: 'test command',
      };

      expect(isCommandItem(partialItem as SearchResult)).toBe(false);
    });

    it('should return false for item with only alias property', () => {
      const partialItem = {
        alias: 'test',
      };

      expect(isCommandItem(partialItem as SearchResult)).toBe(false);
    });
  });

  describe('calculateFrequency', () => {
    const history: SelectionHistory[] = [
      {
        keyword: 'saf',
        selectedPath: '/Applications/Safari.app',
        timestamp: 1000,
      },
      {
        keyword: 'saf',
        selectedPath: '/Applications/Safari.app',
        timestamp: 2000,
      },
      {
        keyword: 'mail',
        selectedPath: '/Applications/Mail.app',
        timestamp: 3000,
      },
      {
        keyword: 'SAF',
        selectedPath: '/Applications/Safari.app',
        timestamp: 4000,
      },
    ];

    it('should calculate frequency correctly', () => {
      const freq = calculateFrequency(
        'saf',
        '/Applications/Safari.app',
        history,
      );
      expect(freq).toBe(3); // 'saf' x2 + 'SAF' x1
    });

    it('should be case insensitive for keywords', () => {
      const freq1 = calculateFrequency(
        'saf',
        '/Applications/Safari.app',
        history,
      );
      const freq2 = calculateFrequency(
        'SAF',
        '/Applications/Safari.app',
        history,
      );
      expect(freq1).toBe(freq2);
    });

    it('should return 0 for unknown path', () => {
      const freq = calculateFrequency(
        'saf',
        '/Applications/Unknown.app',
        history,
      );
      expect(freq).toBe(0);
    });

    it('should return 0 for unknown keyword', () => {
      const freq = calculateFrequency(
        'xyz',
        '/Applications/Safari.app',
        history,
      );
      expect(freq).toBe(0);
    });

    it('should handle empty history', () => {
      const freq = calculateFrequency('saf', '/Applications/Safari.app', []);
      expect(freq).toBe(0);
    });

    it('should count exact path matches only', () => {
      const freq = calculateFrequency(
        'mail',
        '/Applications/Mail.app',
        history,
      );
      expect(freq).toBe(1);
    });
  });

  describe('LocalStorage operations', () => {
    const HISTORY_STORAGE_KEY = 'ignitero_selection_history';

    beforeEach(() => {
      localStorage.clear();
    });

    it('should save and load history', () => {
      const history: SelectionHistory[] = [
        {
          keyword: 'saf',
          selectedPath: '/Applications/Safari.app',
          timestamp: 1000,
        },
      ];

      localStorage.setItem(HISTORY_STORAGE_KEY, JSON.stringify(history));

      const loaded = localStorage.getItem(HISTORY_STORAGE_KEY);
      expect(loaded).not.toBeNull();

      const parsed = JSON.parse(loaded!);
      expect(parsed).toHaveLength(1);
      expect(parsed[0].keyword).toBe('saf');
    });

    it('should handle empty history', () => {
      const loaded = localStorage.getItem(HISTORY_STORAGE_KEY);
      expect(loaded).toBeNull();
    });

    it('should handle corrupted data', () => {
      localStorage.setItem(HISTORY_STORAGE_KEY, 'invalid json');

      expect(() => {
        const loaded = localStorage.getItem(HISTORY_STORAGE_KEY);
        if (loaded) {
          JSON.parse(loaded);
        }
      }).toThrow();
    });
  });

  describe('History management', () => {
    it('should limit history size', () => {
      const MAX_HISTORY_COUNT = 50;
      const history: SelectionHistory[] = [];

      // 100個の履歴を追加
      for (let i = 0; i < 100; i++) {
        history.push({
          keyword: `keyword${i}`,
          selectedPath: `/path${i}`,
          timestamp: i,
        });
      }

      // 最新50件のみを保持
      const limited = history.slice(-MAX_HISTORY_COUNT);

      expect(limited).toHaveLength(50);
      expect(limited[0].timestamp).toBe(50);
      expect(limited[49].timestamp).toBe(99);
    });

    it('should add new history entry', () => {
      const history: SelectionHistory[] = [
        {
          keyword: 'saf',
          selectedPath: '/Applications/Safari.app',
          timestamp: 1000,
        },
      ];

      const newEntry: SelectionHistory = {
        keyword: 'mail',
        selectedPath: '/Applications/Mail.app',
        timestamp: 2000,
      };

      const updated = [...history, newEntry];

      expect(updated).toHaveLength(2);
      expect(updated[1].keyword).toBe('mail');
    });
  });

  describe('Search result sorting', () => {
    it('should sort by frequency', () => {
      const history: SelectionHistory[] = [
        { keyword: 'a', selectedPath: '/path1', timestamp: 1 },
        { keyword: 'a', selectedPath: '/path1', timestamp: 2 },
        { keyword: 'a', selectedPath: '/path2', timestamp: 3 },
      ];

      const results = [
        {
          path: '/path1',
          frequency: calculateFrequency('a', '/path1', history),
        },
        {
          path: '/path2',
          frequency: calculateFrequency('a', '/path2', history),
        },
      ];

      const sorted = results.sort((a, b) => b.frequency - a.frequency);

      expect(sorted[0].path).toBe('/path1');
      expect(sorted[0].frequency).toBe(2);
      expect(sorted[1].path).toBe('/path2');
      expect(sorted[1].frequency).toBe(1);
    });
  });
});
