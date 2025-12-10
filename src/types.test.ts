import { describe, it, expect } from 'vitest';
import type {
  AppItem,
  DirectoryItem,
  CustomCommand,
  CommandItem,
  EditorInfo,
  WindowState,
  WindowPosition,
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

  // CustomCommand 型のテスト
  it('should create CustomCommand correctly', () => {
    const cmd: CustomCommand = {
      alias: 'dev',
      command: 'pnpm dev',
    };

    expect(cmd.alias).toBe('dev');
    expect(cmd.command).toBe('pnpm dev');
    expect(cmd.working_directory).toBeUndefined();
  });

  it('should create CustomCommand with working_directory', () => {
    const cmd: CustomCommand = {
      alias: 'build',
      command: 'pnpm build',
      working_directory: '/Users/test/project',
    };

    expect(cmd.alias).toBe('build');
    expect(cmd.command).toBe('pnpm build');
    expect(cmd.working_directory).toBe('/Users/test/project');
  });

  // CommandItem 型のテスト
  it('should create CommandItem correctly', () => {
    const item: CommandItem = {
      alias: 'test',
      command: 'pnpm test',
    };

    expect(item.alias).toBe('test');
    expect(item.command).toBe('pnpm test');
    expect(item.working_directory).toBeUndefined();
  });

  it('should create CommandItem with working_directory', () => {
    const item: CommandItem = {
      alias: 'lint',
      command: 'pnpm lint',
      working_directory: '/Users/test/project',
    };

    expect(item.alias).toBe('lint');
    expect(item.command).toBe('pnpm lint');
    expect(item.working_directory).toBe('/Users/test/project');
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
      custom_commands: [],
      cache_update: {
        update_on_startup: true,
        auto_update_enabled: false,
        auto_update_interval_hours: 24,
      },
      default_terminal: 'terminal',
    };

    expect(settings.registered_directories).toEqual([]);
    expect(settings.custom_commands).toEqual([]);
    expect(settings.cache_update.update_on_startup).toBe(true);
    expect(settings.default_terminal).toBe('terminal');
  });

  it('should optionally keep window position in settings', () => {
    const mainWindowPosition: WindowPosition = { x: 120, y: 260 };
    const settings: Settings = {
      registered_directories: [],
      custom_commands: [],
      cache_update: {
        update_on_startup: true,
        auto_update_enabled: false,
        auto_update_interval_hours: 24,
      },
      default_terminal: 'terminal',
      main_window_position: mainWindowPosition,
    };

    expect(settings.main_window_position?.x).toBe(120);
    expect(settings.main_window_position?.y).toBe(260);
  });

  // 新機能のテスト: EditorInfo型
  it('should create EditorInfo correctly', () => {
    const editor: EditorInfo = {
      id: 'cursor',
      name: 'Cursor',
      app_name: 'Cursor',
      installed: true,
    };

    expect(editor.id).toBe('cursor');
    expect(editor.name).toBe('Cursor');
    expect(editor.app_name).toBe('Cursor');
    expect(editor.installed).toBe(true);
  });

  it('should create EditorInfo with not installed status', () => {
    const editor: EditorInfo = {
      id: 'windsurf',
      name: 'Windsurf',
      app_name: 'Windsurf',
      installed: false,
    };

    expect(editor.installed).toBe(false);
  });

  it('should create EditorInfo for all supported editors', () => {
    const editors: EditorInfo[] = [
      {
        id: 'windsurf',
        name: 'Windsurf',
        app_name: 'Windsurf',
        installed: true,
      },
      {
        id: 'cursor',
        name: 'Cursor',
        app_name: 'Cursor',
        installed: true,
      },
      {
        id: 'code',
        name: 'VS Code',
        app_name: 'Visual Studio Code',
        installed: false,
      },
      {
        id: 'antigravity',
        name: 'Antigravity',
        app_name: 'Antigravity',
        installed: false,
      },
    ];

    expect(editors).toHaveLength(4);
    expect(editors.every((e) => e.id && e.name && e.app_name)).toBe(true);
  });

  // 新機能のテスト: WindowState型
  it('should create WindowState correctly', () => {
    const windowState: WindowState = {
      label: 'main',
      visible: true,
      focused: true,
    };

    expect(windowState.label).toBe('main');
    expect(windowState.visible).toBe(true);
    expect(windowState.focused).toBe(true);
  });

  it('should create WindowState with invisible state', () => {
    const windowState: WindowState = {
      label: 'settings',
      visible: false,
      focused: false,
    };

    expect(windowState.visible).toBe(false);
    expect(windowState.focused).toBe(false);
  });

  // 統合テスト: エディタとターミナルの組み合わせ
  it('should support all terminal types with directory items', () => {
    const terminals: TerminalType[] = ['terminal', 'iterm2', 'warp'];

    terminals.forEach((terminal) => {
      const settings: Settings = {
        registered_directories: [],
        custom_commands: [],
        cache_update: {
          update_on_startup: true,
          auto_update_enabled: false,
          auto_update_interval_hours: 24,
        },
        default_terminal: terminal,
      };

      expect(settings.default_terminal).toBe(terminal);
    });
  });

  it('should support all editor types in RegisteredDirectory', () => {
    const editorIds = ['windsurf', 'cursor', 'code', 'antigravity'];

    editorIds.forEach((editorId) => {
      const registeredDir: RegisteredDirectory = {
        path: '/test/path',
        parent_open_mode: 'editor',
        parent_editor: editorId,
        subdirs_open_mode: 'editor',
        subdirs_editor: editorId,
        scan_for_apps: false,
      };

      expect(registeredDir.parent_editor).toBe(editorId);
      expect(registeredDir.subdirs_editor).toBe(editorId);
    });
  });

  // カスタムコマンドを含むSettings
  it('should create Settings with custom commands', () => {
    const settings: Settings = {
      registered_directories: [],
      custom_commands: [
        {
          alias: 'dev',
          command: 'pnpm dev',
        },
        {
          alias: 'build',
          command: 'pnpm build',
          working_directory: '/Users/test/project',
        },
      ],
      cache_update: {
        update_on_startup: true,
        auto_update_enabled: false,
        auto_update_interval_hours: 24,
      },
      default_terminal: 'terminal',
    };

    expect(settings.custom_commands).toHaveLength(2);
    expect(settings.custom_commands[0].alias).toBe('dev');
    expect(settings.custom_commands[0].working_directory).toBeUndefined();
    expect(settings.custom_commands[1].alias).toBe('build');
    expect(settings.custom_commands[1].working_directory).toBe(
      '/Users/test/project',
    );
  });
});
