import { describe, it, expect } from 'vitest';
import type {
  AppItem,
  DirectoryItem,
  OpenMode,
  TerminalType,
  RegisteredDirectory,
  Settings,
} from './types';

describe('Type definitions', () => {
  it('should create AppItem correctly', () => {
    const app: AppItem = {
      name: 'Safari',
      path: '/Applications/Safari.app',
      icon_path: '/path/to/icon.png',
    };

    expect(app.name).toBe('Safari');
    expect(app.path).toBe('/Applications/Safari.app');
    expect(app.icon_path).toBe('/path/to/icon.png');
  });

  it('should create DirectoryItem correctly', () => {
    const dir: DirectoryItem = {
      name: 'Projects',
      path: '/Users/test/Projects',
      editor: 'cursor',
    };

    expect(dir.name).toBe('Projects');
    expect(dir.path).toBe('/Users/test/Projects');
    expect(dir.editor).toBe('cursor');
  });

  it('should support OpenMode types', () => {
    const modes: OpenMode[] = ['none', 'finder', 'editor'];
    expect(modes).toHaveLength(3);
  });

  it('should support TerminalType types', () => {
    const terminals: TerminalType[] = ['terminal', 'iterm2', 'warp'];
    expect(terminals).toHaveLength(3);
  });

  it('should create RegisteredDirectory correctly', () => {
    const registeredDir: RegisteredDirectory = {
      path: '/Users/test/Projects',
      parent_open_mode: 'editor',
      parent_editor: 'cursor',
      parent_search_keyword: 'proj',
      subdirs_open_mode: 'finder',
      subdirs_editor: undefined,
      scan_for_apps: false,
    };

    expect(registeredDir.parent_open_mode).toBe('editor');
    expect(registeredDir.parent_search_keyword).toBe('proj');
    expect(registeredDir.scan_for_apps).toBe(false);
  });

  it('should create Settings correctly', () => {
    const settings: Settings = {
      registered_directories: [],
      cache_update: {
        update_on_startup: true,
        auto_update_enabled: false,
        auto_update_interval_hours: 24,
      },
      default_terminal: 'terminal',
    };

    expect(settings.registered_directories).toEqual([]);
    expect(settings.cache_update.update_on_startup).toBe(true);
    expect(settings.default_terminal).toBe('terminal');
  });
});
