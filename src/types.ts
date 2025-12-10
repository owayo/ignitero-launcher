export interface AppItem {
  name: string;
  path: string;
  icon_path?: string;
}

export interface DirectoryItem {
  name: string;
  path: string;
  editor?: string;
}

export interface CustomCommand {
  alias: string;
  command: string;
}

export interface CommandItem {
  alias: string;
  command: string;
}

export interface WindowPosition {
  x: number;
  y: number;
}

export interface EditorInfo {
  id: string;
  name: string;
  app_name: string;
  installed: boolean;
}

export interface WindowState {
  label: string;
  visible: boolean;
  focused: boolean;
}

export type OpenMode = 'none' | 'finder' | 'editor';
export type TerminalType = 'terminal' | 'iterm2' | 'warp';

export interface RegisteredDirectory {
  path: string;

  // 親ディレクトリ自身の開き方
  parent_open_mode: OpenMode;
  parent_editor?: string;
  parent_search_keyword?: string; // 検索キーワード（未指定時はディレクトリ名）

  // サブディレクトリの開き方
  subdirs_open_mode: OpenMode;
  subdirs_editor?: string;

  // .appファイルのスキャン
  scan_for_apps: boolean;
}

export interface CacheUpdateSettings {
  update_on_startup: boolean;
  auto_update_enabled: boolean;
  auto_update_interval_hours: number;
}

export interface Settings {
  registered_directories: RegisteredDirectory[];
  custom_commands: CustomCommand[];
  cache_update: CacheUpdateSettings;
  default_terminal: TerminalType;
  main_window_position?: WindowPosition | null;
}
