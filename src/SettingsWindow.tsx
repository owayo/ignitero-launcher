import React, { useState, useEffect } from 'react';
import {
  Alert,
  Button,
  Checkbox,
  Divider,
  Form,
  Input,
  InputNumber,
  List,
  message,
  Modal,
  Radio,
  Select,
  Space,
  Tabs,
  Typography,
} from 'antd';
import {
  AppstoreOutlined,
  CloudSyncOutlined,
  CodeOutlined,
  DeleteOutlined,
  EditOutlined,
  FolderAddOutlined,
  FolderOpenOutlined,
  PlusOutlined,
  ReloadOutlined,
  SettingOutlined,
} from '@ant-design/icons';
import { convertFileSrc, invoke } from '@tauri-apps/api/core';
import { open } from '@tauri-apps/plugin-dialog';
import { emit } from '@tauri-apps/api/event';
import type {
  Settings,
  RegisteredDirectory,
  CustomCommand,
  AppItem,
} from './types';
import packageJson from '../package.json';
import './Settings.css';

const { Title, Text } = Typography;
const { Option } = Select;

interface UpdateInfo {
  has_update: boolean;
  current_version: string;
  latest_version: string | null;
  html_url: string | null;
}

const SettingsWindow: React.FC = () => {
  const [form] = Form.useForm();
  const [settings, setSettings] = useState<Settings | null>(null);
  const [addDirModalVisible, setAddDirModalVisible] = useState(false);
  const [addDirForm] = Form.useForm();
  const [selectedPath, setSelectedPath] = useState<string>('');
  const [availableEditors, setAvailableEditors] = useState<string[]>([]);
  const [availableTerminals, setAvailableTerminals] = useState<string[]>([]);
  const [editingDirectory, setEditingDirectory] =
    useState<RegisteredDirectory | null>(null);
  const [addCmdModalVisible, setAddCmdModalVisible] = useState(false);
  const [addCmdForm] = Form.useForm();
  const [editingCommand, setEditingCommand] = useState<CustomCommand | null>(
    null,
  );
  const [editorIcons, setEditorIcons] = useState<Map<string, string>>(
    new Map(),
  );
  const [terminalIcons, setTerminalIcons] = useState<Map<string, string>>(
    new Map(),
  );
  const [updateInfo, setUpdateInfo] = useState<UpdateInfo | null>(null);
  const [checkingUpdate, setCheckingUpdate] = useState(false);
  const [updateError, setUpdateError] = useState<string | null>(null);
  const [refreshingCache, setRefreshingCache] = useState(false);
  const [allApps, setAllApps] = useState<AppItem[]>([]);
  const [appSearchQuery, setAppSearchQuery] = useState<string>('');

  // インストール済みエディタを取得
  const loadAvailableEditors = async () => {
    try {
      const editors = await invoke<string[]>('get_available_editors');
      setAvailableEditors(editors);
      // エディタアイコンを読み込み
      await loadEditorIcons(editors);
    } catch (error) {
      console.error('Failed to load available editors:', error);
    }
  };

  // エディタアイコンを読み込み
  const loadEditorIcons = async (editors: string[]) => {
    const icons = new Map<string, string>();
    for (const editor of editors) {
      try {
        const iconPath = await invoke<string | null>('get_editor_icon_path', {
          editor,
        });
        if (iconPath) {
          icons.set(editor, convertFileSrc(iconPath));
        }
      } catch (error) {
        console.error(`Failed to load icon for ${editor}:`, error);
      }
    }
    setEditorIcons(icons);
  };

  // インストール済みターミナルを取得
  const loadAvailableTerminals = async () => {
    try {
      const terminals = await invoke<string[]>('get_available_terminals');
      setAvailableTerminals(terminals);
      // ターミナルアイコンを読み込み
      await loadTerminalIcons(terminals);
    } catch (error) {
      console.error('Failed to load available terminals:', error);
    }
  };

  // ターミナルアイコンを読み込み
  const loadTerminalIcons = async (terminals: string[]) => {
    const icons = new Map<string, string>();
    for (const terminal of terminals) {
      try {
        const iconPath = await invoke<string | null>('get_terminal_icon_path', {
          terminal,
        });
        if (iconPath) {
          icons.set(terminal, convertFileSrc(iconPath));
        }
      } catch (error) {
        console.error(`Failed to load icon for ${terminal}:`, error);
      }
    }
    setTerminalIcons(icons);
  };

  // 全アプリを読み込み
  const loadAllApps = async () => {
    try {
      const apps = await invoke<AppItem[]>('get_all_apps');
      // 名前でソート
      apps.sort((a, b) => a.name.localeCompare(b.name));
      setAllApps(apps);
    } catch (error) {
      console.error('Failed to load all apps:', error);
    }
  };

  // アプリの除外状態を切り替え
  const handleToggleAppExclusion = async (
    appPath: string,
    excluded: boolean,
  ) => {
    if (!settings) return;

    try {
      const newExcludedApps = excluded
        ? [...settings.excluded_apps, appPath]
        : settings.excluded_apps.filter((path) => path !== appPath);

      const updatedSettings: Settings = {
        ...settings,
        excluded_apps: newExcludedApps,
      };

      await invoke('save_settings', { settings: updatedSettings });
      setSettings(updatedSettings);
      await emit('settings-changed');
    } catch (error) {
      console.error('Failed to toggle app exclusion:', error);
      message.error('除外設定の保存に失敗しました');
    }
  };

  // 設定を読み込み
  const loadSettings = async () => {
    try {
      const loadedSettings = await invoke<Settings>('get_settings');
      setSettings(loadedSettings);
      form.setFieldsValue({
        update_on_startup: loadedSettings.cache_update.update_on_startup,
        auto_update_enabled: loadedSettings.cache_update.auto_update_enabled,
        auto_update_interval_hours:
          loadedSettings.cache_update.auto_update_interval_hours,
        default_terminal: loadedSettings.default_terminal,
      });
    } catch (error) {
      console.error('Failed to load settings:', error);
    }
  };

  useEffect(() => {
    loadSettings();
    loadAvailableEditors();
    loadAvailableTerminals();
    loadAllApps();
  }, []);

  // バージョンを手動チェック
  const handleCheckUpdates = async () => {
    try {
      setCheckingUpdate(true);
      setUpdateError(null);
      const info = await invoke<UpdateInfo>('check_update', {
        force: true,
      });
      setUpdateInfo(info);
    } catch (error) {
      console.error('Failed to check for updates:', error);
      setUpdateError('更新の確認に失敗しました');
    } finally {
      setCheckingUpdate(false);
    }
  };

  // ディレクトリを追加（フォルダ選択）
  const handleAddDirectory = async () => {
    try {
      console.log('Opening folder picker...');
      const selected = await open({
        directory: true,
        multiple: false,
        defaultPath: '/',
      });

      console.log('Selected:', selected);

      if (selected && typeof selected === 'string') {
        console.log('Setting selected path:', selected);
        setSelectedPath(selected);
        // デフォルトのキーワードはディレクトリ名
        const defaultKeyword = selected.split('/').pop() || '';
        addDirForm.setFieldsValue({
          parent_open_mode: 'none',
          parent_editor: availableEditors[0] || '',
          parent_search_keyword: defaultKeyword,
          subdirs_open_mode: 'none',
          subdirs_editor: availableEditors[0] || '',
          scan_for_apps: false,
        });
        setAddDirModalVisible(true);
      } else {
        console.log('No folder selected or cancelled');
      }
    } catch (error) {
      console.error('Failed to open folder picker:', error);
      alert('フォルダ選択に失敗しました: ' + error);
    }
  };

  // ディレクトリ追加を確定
  const handleConfirmAddDirectory = async () => {
    try {
      const values = addDirForm.getFieldsValue();

      const newDir: RegisteredDirectory = {
        path: editingDirectory ? editingDirectory.path : selectedPath,
        parent_open_mode: values.parent_open_mode,
        parent_editor:
          values.parent_open_mode === 'editor'
            ? values.parent_editor
            : undefined,
        parent_search_keyword:
          values.parent_open_mode !== 'none'
            ? values.parent_search_keyword
            : undefined,
        subdirs_open_mode: values.subdirs_open_mode,
        subdirs_editor:
          values.subdirs_open_mode === 'editor'
            ? values.subdirs_editor
            : undefined,
        scan_for_apps: values.scan_for_apps,
      };

      // add_directoryは既に存在する場合は更新するため、削除不要
      await invoke('add_directory', { directory: newDir });
      setAddDirModalVisible(false);
      setEditingDirectory(null);
      loadSettings();
    } catch (error) {
      console.error('Failed to add directory:', error);
    }
  };

  // ディレクトリを編集
  const handleEditDirectory = (dir: RegisteredDirectory) => {
    setEditingDirectory(dir);
    setSelectedPath(dir.path);
    const defaultKeyword = dir.path.split('/').pop() || '';
    addDirForm.setFieldsValue({
      parent_open_mode: dir.parent_open_mode,
      parent_editor: dir.parent_editor || availableEditors[0] || '',
      parent_search_keyword: dir.parent_search_keyword || defaultKeyword,
      subdirs_open_mode: dir.subdirs_open_mode,
      subdirs_editor: dir.subdirs_editor || availableEditors[0] || '',
      scan_for_apps: dir.scan_for_apps,
    });
    setAddDirModalVisible(true);
  };

  // ディレクトリを削除
  const handleRemoveDirectory = async (path: string) => {
    try {
      await invoke('remove_directory', { path });
      loadSettings();
    } catch (error) {
      console.error('Failed to remove directory:', error);
    }
  };

  // コマンドを追加
  const handleAddCommand = () => {
    setEditingCommand(null);
    addCmdForm.resetFields();
    setAddCmdModalVisible(true);
  };

  // コマンド追加/編集を確定
  const handleConfirmAddCommand = async () => {
    try {
      const values = await addCmdForm.validateFields();
      const cmd: CustomCommand = {
        alias: values.alias,
        command: values.command,
        working_directory: values.working_directory || undefined,
      };
      await invoke('add_command', { command: cmd });
      setAddCmdModalVisible(false);
      setEditingCommand(null);
      loadSettings();
    } catch (error) {
      console.error('Failed to add command:', error);
    }
  };

  // コマンドを編集
  const handleEditCommand = (cmd: CustomCommand) => {
    setEditingCommand(cmd);
    addCmdForm.setFieldsValue({
      alias: cmd.alias,
      command: cmd.command,
      working_directory: cmd.working_directory || '',
    });
    setAddCmdModalVisible(true);
  };

  // コマンドを削除
  const handleRemoveCommand = async (alias: string) => {
    try {
      await invoke('remove_command', { alias });
      loadSettings();
    } catch (error) {
      console.error('Failed to remove command:', error);
    }
  };

  // キャッシュを手動更新
  const handleRefreshCache = async () => {
    try {
      setRefreshingCache(true);
      await invoke('refresh_cache');
      message.success('キャッシュを更新しました');
    } catch (error) {
      console.error('Failed to refresh cache:', error);
      message.error('キャッシュの更新に失敗しました');
    } finally {
      setRefreshingCache(false);
    }
  };

  // アイコンキャッシュを更新（クリア後に再生成）
  const handleRefreshIconCache = async () => {
    try {
      setRefreshingCache(true);
      // キャッシュをクリア
      await invoke<number>('clear_icon_cache');
      // 再スキャンしてアイコンを再生成
      await invoke('refresh_cache');
      message.success('アイコンキャッシュを更新しました');
    } catch (error) {
      console.error('Failed to refresh icon cache:', error);
      message.error('アイコンキャッシュの更新に失敗しました');
    } finally {
      setRefreshingCache(false);
    }
  };

  if (!settings) {
    return <div>読み込み中...</div>;
  }

  const installedTerminals = availableTerminals.filter(
    (terminal) => terminal === 'terminal' || terminalIcons.has(terminal),
  );

  return (
    <div className="settings-container">
      <div className="settings-layout settings-content">
        <Form
          form={form}
          layout="vertical"
          onValuesChange={async (_changedValues, allValues) => {
            // 設定が変更されたら即座に保存
            try {
              const updatedSettings: Settings = {
                ...settings,
                cache_update: {
                  update_on_startup: allValues.update_on_startup,
                  auto_update_enabled: allValues.auto_update_enabled,
                  auto_update_interval_hours:
                    allValues.auto_update_interval_hours,
                },
                default_terminal: allValues.default_terminal,
              };
              await invoke('save_settings', { settings: updatedSettings });
              setSettings(updatedSettings);
              // 設定変更イベントを発行
              await emit('settings-changed');
            } catch (error) {
              console.error('Failed to save settings:', error);
            }
          }}
        >
          <Tabs
            type="line"
            defaultActiveKey="general"
            style={{ marginTop: -8 }}
            items={[
              {
                key: 'general',
                label: (
                  <span>
                    <SettingOutlined />
                    <span style={{ marginLeft: 8 }}>全般</span>
                  </span>
                ),
                children: (
                  <div
                    style={{
                      display: 'flex',
                      flexDirection: 'column',
                      gap: 24,
                    }}
                  >
                    {/* バージョンチェック */}
                    <div>
                      <Title level={5} style={{ marginBottom: 12 }}>
                        バージョン
                      </Title>
                      <Space direction="vertical" style={{ width: '100%' }}>
                        <Space>
                          <Text>現在のバージョン:</Text>
                          <Text strong>v{packageJson.version}</Text>
                          {updateInfo && !updateInfo.has_update && (
                            <Text
                              type="success"
                              style={{
                                fontSize: 12,
                                background: '#f6ffed',
                                padding: '2px 8px',
                                borderRadius: 4,
                              }}
                            >
                              最新です
                            </Text>
                          )}
                        </Space>
                        <Button
                          type="primary"
                          icon={<CloudSyncOutlined />}
                          loading={checkingUpdate}
                          onClick={handleCheckUpdates}
                        >
                          更新を確認
                        </Button>
                        {updateError && (
                          <Text type="danger">{updateError}</Text>
                        )}
                        {updateInfo?.has_update && (
                          <Alert
                            type="info"
                            showIcon
                            message={`最新版 v${updateInfo.latest_version} が利用可能です`}
                            description={
                              updateInfo.html_url ? (
                                <a
                                  href={updateInfo.html_url}
                                  target="_blank"
                                  rel="noreferrer"
                                >
                                  ダウンロードページを開く
                                </a>
                              ) : null
                            }
                          />
                        )}
                      </Space>
                    </div>

                    <Divider style={{ margin: 0 }} />

                    {/* デフォルトターミナル */}
                    <div>
                      <Title level={5} style={{ marginBottom: 12 }}>
                        デフォルトターミナル
                      </Title>
                      <Text
                        type="secondary"
                        style={{ display: 'block', marginBottom: 12 }}
                      >
                        ディレクトリを選択して→キーを押したとき、またはコマンドを実行するときに使用するターミナル
                      </Text>
                      <Form.Item name="default_terminal" style={{ margin: 0 }}>
                        <Radio.Group style={{ width: '100%' }}>
                          {installedTerminals.map((terminal) => {
                            const label =
                              terminal === 'terminal'
                                ? 'macOSデフォルトターミナル'
                                : terminal === 'iterm2'
                                  ? 'iTerm2'
                                  : 'Warp';
                            return (
                              <Radio
                                key={terminal}
                                value={terminal}
                                style={{ display: 'block', padding: '6px 0' }}
                              >
                                <Space align="center">
                                  {terminalIcons.get(terminal) && (
                                    <img
                                      src={terminalIcons.get(terminal)}
                                      alt={label}
                                      style={{
                                        width: 16,
                                        height: 16,
                                        verticalAlign: 'middle',
                                      }}
                                    />
                                  )}
                                  {label}
                                </Space>
                              </Radio>
                            );
                          })}
                          {installedTerminals.length === 0 && (
                            <Text type="secondary">
                              利用可能なターミナルが見つかりませんでした
                            </Text>
                          )}
                        </Radio.Group>
                      </Form.Item>
                    </div>

                    <Divider style={{ margin: 0 }} />

                    {/* キャッシュ更新 */}
                    <div>
                      <Title level={5} style={{ marginBottom: 12 }}>
                        キャッシュ更新
                      </Title>
                      <Space
                        direction="vertical"
                        size="middle"
                        style={{ width: '100%' }}
                      >
                        <Form.Item
                          name="update_on_startup"
                          valuePropName="checked"
                          style={{ margin: 0 }}
                        >
                          <Checkbox>起動時にキャッシュを更新する</Checkbox>
                        </Form.Item>

                        <Form.Item
                          name="auto_update_enabled"
                          valuePropName="checked"
                          style={{ margin: 0 }}
                        >
                          <Checkbox>自動更新を有効にする</Checkbox>
                        </Form.Item>

                        <Form.Item noStyle shouldUpdate>
                          {() => {
                            const autoUpdateEnabled = form.getFieldValue(
                              'auto_update_enabled',
                            );
                            return (
                              autoUpdateEnabled && (
                                <Form.Item
                                  name="auto_update_interval_hours"
                                  label="自動更新間隔（時間）"
                                  style={{ margin: 0, marginLeft: 24 }}
                                >
                                  <InputNumber
                                    min={1}
                                    max={24}
                                    style={{ width: 80 }}
                                  />
                                </Form.Item>
                              )
                            );
                          }}
                        </Form.Item>

                        <Space direction="vertical" size="small">
                          <Button
                            type="primary"
                            icon={<ReloadOutlined />}
                            onClick={handleRefreshCache}
                            loading={refreshingCache}
                          >
                            今すぐキャッシュを更新
                          </Button>
                          <Button
                            type="primary"
                            icon={<ReloadOutlined />}
                            onClick={handleRefreshIconCache}
                            loading={refreshingCache}
                          >
                            アイコンキャッシュを更新
                          </Button>
                          <Text type="secondary">
                            アプリのアイコンが変わった場合はアイコンキャッシュを更新してください
                          </Text>
                        </Space>
                      </Space>
                    </div>
                  </div>
                ),
              },
              {
                key: 'directories',
                label: (
                  <span>
                    <FolderOpenOutlined />
                    <span style={{ marginLeft: 8 }}>ディレクトリ</span>
                  </span>
                ),
                children: (
                  <div
                    style={{
                      display: 'flex',
                      flexDirection: 'column',
                      gap: 12,
                    }}
                  >
                    <Button
                      type="primary"
                      icon={<FolderAddOutlined />}
                      onClick={handleAddDirectory}
                    >
                      ディレクトリを追加
                    </Button>

                    <List
                      dataSource={
                        settings?.registered_directories
                          ? [...settings.registered_directories].sort((a, b) =>
                              a.path.localeCompare(b.path),
                            )
                          : []
                      }
                      locale={{
                        emptyText: 'ディレクトリが登録されていません',
                      }}
                      renderItem={(dir) => (
                        <List.Item
                          actions={[
                            <Button
                              key="edit"
                              type="link"
                              icon={<EditOutlined />}
                              onClick={() => handleEditDirectory(dir)}
                            >
                              編集
                            </Button>,
                            <Button
                              key="delete"
                              type="link"
                              danger
                              icon={<DeleteOutlined />}
                              onClick={() => handleRemoveDirectory(dir.path)}
                            >
                              削除
                            </Button>,
                          ]}
                        >
                          <List.Item.Meta
                            title={dir.path}
                            description={
                              <Space direction="vertical" size={0}>
                                <Text type="secondary">
                                  このディレクトリ:{' '}
                                  {dir.parent_open_mode === 'none'
                                    ? '表示しない'
                                    : dir.parent_open_mode === 'finder'
                                      ? 'Finderで開く'
                                      : `${dir.parent_editor || 'エディタ'}で開く`}
                                </Text>
                                <Text type="secondary">
                                  配下のディレクトリ:{' '}
                                  {dir.subdirs_open_mode === 'none'
                                    ? '表示しない'
                                    : dir.subdirs_open_mode === 'finder'
                                      ? 'Finderで開く'
                                      : `${dir.subdirs_editor || 'エディタ'}で開く`}
                                </Text>
                                {dir.scan_for_apps && (
                                  <Text type="secondary">
                                    アプリスキャン: 有効
                                  </Text>
                                )}
                              </Space>
                            }
                          />
                        </List.Item>
                      )}
                    />
                  </div>
                ),
              },
              {
                key: 'commands',
                label: (
                  <span>
                    <CodeOutlined />
                    <span style={{ marginLeft: 8 }}>コマンド</span>
                  </span>
                ),
                children: (
                  <div
                    style={{
                      display: 'flex',
                      flexDirection: 'column',
                      gap: 12,
                    }}
                  >
                    <Button
                      type="primary"
                      icon={<PlusOutlined />}
                      onClick={handleAddCommand}
                    >
                      コマンドを追加
                    </Button>

                    <List
                      dataSource={
                        settings?.custom_commands
                          ? [...settings.custom_commands].sort((a, b) =>
                              a.alias.localeCompare(b.alias),
                            )
                          : []
                      }
                      locale={{ emptyText: 'コマンドが登録されていません' }}
                      renderItem={(cmd) => (
                        <List.Item
                          actions={[
                            <Button
                              key="edit"
                              type="link"
                              icon={<EditOutlined />}
                              onClick={() => handleEditCommand(cmd)}
                            >
                              編集
                            </Button>,
                            <Button
                              key="delete"
                              type="link"
                              danger
                              icon={<DeleteOutlined />}
                              onClick={() => handleRemoveCommand(cmd.alias)}
                            >
                              削除
                            </Button>,
                          ]}
                        >
                          <List.Item.Meta
                            title={cmd.alias}
                            description={
                              <div>
                                <Text
                                  code
                                  style={{
                                    wordBreak: 'break-all',
                                    whiteSpace: 'pre-wrap',
                                  }}
                                >
                                  {cmd.command}
                                </Text>
                                {cmd.working_directory && (
                                  <div style={{ marginTop: 4 }}>
                                    <Text
                                      type="secondary"
                                      style={{ fontSize: 12 }}
                                    >
                                      <FolderOpenOutlined
                                        style={{ marginRight: 4 }}
                                      />
                                      {cmd.working_directory}
                                    </Text>
                                  </div>
                                )}
                              </div>
                            }
                          />
                        </List.Item>
                      )}
                    />
                  </div>
                ),
              },
              {
                key: 'excluded-apps',
                label: (
                  <span>
                    <AppstoreOutlined />
                    <span style={{ marginLeft: 8 }}>除外アプリ</span>
                  </span>
                ),
                children: (
                  <div
                    style={{
                      display: 'flex',
                      flexDirection: 'column',
                      gap: 12,
                    }}
                  >
                    <Text type="secondary">
                      チェックを付けたアプリは検索結果から除外されます
                    </Text>

                    <Input
                      placeholder="アプリ名で絞り込み..."
                      value={appSearchQuery}
                      onChange={(e) => setAppSearchQuery(e.target.value)}
                      allowClear
                      style={{ marginBottom: 8 }}
                    />

                    <div
                      style={{
                        maxHeight: 400,
                        overflowY: 'auto',
                        border: '1px solid #d9d9d9',
                        borderRadius: 6,
                      }}
                    >
                      <List
                        size="small"
                        dataSource={allApps.filter((app) =>
                          appSearchQuery
                            ? app.name
                                .toLowerCase()
                                .includes(appSearchQuery.toLowerCase()) ||
                              app.path
                                .toLowerCase()
                                .includes(appSearchQuery.toLowerCase())
                            : true,
                        )}
                        locale={{ emptyText: 'アプリが見つかりません' }}
                        renderItem={(app) => {
                          const isExcluded =
                            settings?.excluded_apps?.includes(app.path) ??
                            false;
                          return (
                            <List.Item
                              style={{
                                padding: '8px 12px',
                                background: isExcluded
                                  ? 'rgba(255, 77, 79, 0.1)'
                                  : 'transparent',
                              }}
                            >
                              <Checkbox
                                checked={isExcluded}
                                onChange={(e) =>
                                  handleToggleAppExclusion(
                                    app.path,
                                    e.target.checked,
                                  )
                                }
                                style={{ marginRight: 12 }}
                              />
                              <div
                                style={{
                                  display: 'flex',
                                  alignItems: 'center',
                                  flex: 1,
                                  minWidth: 0,
                                }}
                              >
                                {app.icon_path && (
                                  <img
                                    src={convertFileSrc(app.icon_path)}
                                    alt=""
                                    style={{
                                      width: 24,
                                      height: 24,
                                      marginRight: 8,
                                      flexShrink: 0,
                                    }}
                                  />
                                )}
                                <div
                                  style={{
                                    minWidth: 0,
                                    flex: 1,
                                  }}
                                >
                                  <Text
                                    strong
                                    style={{
                                      display: 'block',
                                      textDecoration: isExcluded
                                        ? 'line-through'
                                        : 'none',
                                      color: isExcluded ? '#999' : 'inherit',
                                    }}
                                  >
                                    {app.name}
                                  </Text>
                                  <Text
                                    type="secondary"
                                    style={{
                                      fontSize: 11,
                                      display: 'block',
                                      overflow: 'hidden',
                                      textOverflow: 'ellipsis',
                                      whiteSpace: 'nowrap',
                                    }}
                                  >
                                    {app.path}
                                  </Text>
                                </div>
                              </div>
                            </List.Item>
                          );
                        }}
                      />
                    </div>

                    {settings?.excluded_apps &&
                      settings.excluded_apps.length > 0 && (
                        <Text type="secondary">
                          {settings.excluded_apps.length} 件のアプリを除外中
                        </Text>
                      )}
                  </div>
                ),
              },
            ]}
          />
        </Form>
      </div>

      {/* ディレクトリ追加/編集モーダル */}
      <Modal
        title={editingDirectory ? 'ディレクトリを編集' : 'ディレクトリを追加'}
        open={addDirModalVisible}
        onCancel={() => {
          setAddDirModalVisible(false);
          setEditingDirectory(null);
        }}
        onOk={handleConfirmAddDirectory}
        okText={editingDirectory ? '更新' : '追加'}
        cancelText="キャンセル"
      >
        <Form form={addDirForm} layout="vertical">
          <Form.Item label="パス">
            <Text>{selectedPath}</Text>
          </Form.Item>

          <Divider />

          <Title level={5}>このディレクトリ自身</Title>
          <Form.Item name="parent_open_mode" label="開き方">
            <Radio.Group>
              <Space direction="vertical">
                <Radio value="none">検索に表示しない</Radio>
                <Radio value="finder">Finderで開く</Radio>
                <Radio value="editor">エディタで開く</Radio>
              </Space>
            </Radio.Group>
          </Form.Item>

          <Form.Item noStyle shouldUpdate>
            {() => {
              const parentOpenMode =
                addDirForm.getFieldValue('parent_open_mode');
              return (
                <>
                  {parentOpenMode !== 'none' && (
                    <Form.Item
                      name="parent_search_keyword"
                      label="検索キーワード"
                      tooltip="このキーワードで検索できます（空欄の場合はディレクトリ名）"
                    >
                      <Input placeholder="ディレクトリ名" />
                    </Form.Item>
                  )}
                  {parentOpenMode === 'editor' && (
                    <Form.Item
                      name="parent_editor"
                      label="エディタ"
                      rules={[
                        {
                          required: true,
                          message: 'エディタを選択してください',
                        },
                      ]}
                    >
                      <Select placeholder="エディタを選択">
                        {availableEditors.includes('antigravity') && (
                          <Option value="antigravity">
                            <Space align="center">
                              {editorIcons.get('antigravity') && (
                                <img
                                  src={editorIcons.get('antigravity')}
                                  alt="Antigravity"
                                  style={{
                                    width: 16,
                                    height: 16,
                                    verticalAlign: 'middle',
                                  }}
                                />
                              )}
                              Antigravity
                            </Space>
                          </Option>
                        )}
                        {availableEditors.includes('cursor') && (
                          <Option value="cursor">
                            <Space align="center">
                              {editorIcons.get('cursor') && (
                                <img
                                  src={editorIcons.get('cursor')}
                                  alt="Cursor"
                                  style={{
                                    width: 16,
                                    height: 16,
                                    verticalAlign: 'middle',
                                  }}
                                />
                              )}
                              Cursor
                            </Space>
                          </Option>
                        )}
                        {availableEditors.includes('code') && (
                          <Option value="code">
                            <Space align="center">
                              {editorIcons.get('code') && (
                                <img
                                  src={editorIcons.get('code')}
                                  alt="VS Code"
                                  style={{
                                    width: 16,
                                    height: 16,
                                    verticalAlign: 'middle',
                                  }}
                                />
                              )}
                              VS Code
                            </Space>
                          </Option>
                        )}
                        {availableEditors.includes('windsurf') && (
                          <Option value="windsurf">
                            <Space align="center">
                              {editorIcons.get('windsurf') && (
                                <img
                                  src={editorIcons.get('windsurf')}
                                  alt="Windsurf"
                                  style={{
                                    width: 16,
                                    height: 16,
                                    verticalAlign: 'middle',
                                  }}
                                />
                              )}
                              Windsurf
                            </Space>
                          </Option>
                        )}
                      </Select>
                    </Form.Item>
                  )}
                </>
              );
            }}
          </Form.Item>

          <Divider />

          <Title level={5}>配下のディレクトリ</Title>
          <Form.Item name="subdirs_open_mode" label="開き方">
            <Radio.Group>
              <Space direction="vertical">
                <Radio value="none">検索に表示しない</Radio>
                <Radio value="finder">Finderで開く</Radio>
                <Radio value="editor">エディタで開く</Radio>
              </Space>
            </Radio.Group>
          </Form.Item>

          <Form.Item noStyle shouldUpdate>
            {() => {
              const subdirsOpenMode =
                addDirForm.getFieldValue('subdirs_open_mode');
              return (
                subdirsOpenMode === 'editor' && (
                  <Form.Item
                    name="subdirs_editor"
                    label="エディタ"
                    rules={[
                      { required: true, message: 'エディタを選択してください' },
                    ]}
                  >
                    <Select placeholder="エディタを選択">
                      {availableEditors.includes('antigravity') && (
                        <Option value="antigravity">
                          <Space align="center">
                            {editorIcons.get('antigravity') && (
                              <img
                                src={editorIcons.get('antigravity')}
                                alt="Antigravity"
                                style={{
                                  width: 16,
                                  height: 16,
                                  verticalAlign: 'middle',
                                }}
                              />
                            )}
                            Antigravity
                          </Space>
                        </Option>
                      )}
                      {availableEditors.includes('cursor') && (
                        <Option value="cursor">
                          <Space align="center">
                            {editorIcons.get('cursor') && (
                              <img
                                src={editorIcons.get('cursor')}
                                alt="Cursor"
                                style={{
                                  width: 16,
                                  height: 16,
                                  verticalAlign: 'middle',
                                }}
                              />
                            )}
                            Cursor
                          </Space>
                        </Option>
                      )}
                      {availableEditors.includes('code') && (
                        <Option value="code">
                          <Space align="center">
                            {editorIcons.get('code') && (
                              <img
                                src={editorIcons.get('code')}
                                alt="VS Code"
                                style={{
                                  width: 16,
                                  height: 16,
                                  verticalAlign: 'middle',
                                }}
                              />
                            )}
                            VS Code
                          </Space>
                        </Option>
                      )}
                      {availableEditors.includes('windsurf') && (
                        <Option value="windsurf">
                          <Space align="center">
                            {editorIcons.get('windsurf') && (
                              <img
                                src={editorIcons.get('windsurf')}
                                alt="Windsurf"
                                style={{
                                  width: 16,
                                  height: 16,
                                  verticalAlign: 'middle',
                                }}
                              />
                            )}
                            Windsurf
                          </Space>
                        </Option>
                      )}
                    </Select>
                  </Form.Item>
                )
              );
            }}
          </Form.Item>

          <Divider />

          <Form.Item name="scan_for_apps" valuePropName="checked">
            <Checkbox>
              このディレクトリ配下の.appファイルもスキャンする
            </Checkbox>
          </Form.Item>
        </Form>
      </Modal>

      {/* コマンド追加/編集モーダル */}
      <Modal
        title={editingCommand ? 'コマンドを編集' : 'コマンドを追加'}
        open={addCmdModalVisible}
        onCancel={() => {
          setAddCmdModalVisible(false);
          setEditingCommand(null);
        }}
        onOk={handleConfirmAddCommand}
        okText={editingCommand ? '更新' : '追加'}
        cancelText="キャンセル"
      >
        <Form form={addCmdForm} layout="vertical">
          <Form.Item
            name="alias"
            label="エイリアス（検索キーワード）"
            rules={[
              { required: true, message: 'エイリアスを入力してください' },
            ]}
          >
            <Input placeholder="例: deploy, build, test" />
          </Form.Item>

          <Form.Item
            name="command"
            label="実行するコマンド"
            rules={[{ required: true, message: 'コマンドを入力してください' }]}
          >
            <Input.TextArea
              placeholder="例: npm run deploy"
              autoSize={{ minRows: 2, maxRows: 6 }}
            />
          </Form.Item>

          <Form.Item
            name="working_directory"
            label="実行ディレクトリ（省略可）"
          >
            <Space.Compact style={{ width: '100%' }}>
              <Form.Item name="working_directory" noStyle>
                <Input
                  placeholder="例: ~/project または /Users/name/project"
                  style={{ flex: 1 }}
                />
              </Form.Item>
              <Button
                icon={<FolderOpenOutlined />}
                onClick={async () => {
                  try {
                    const selected = await open({
                      directory: true,
                      multiple: false,
                      defaultPath:
                        addCmdForm.getFieldValue('working_directory') || '/',
                    });
                    if (selected && typeof selected === 'string') {
                      addCmdForm.setFieldValue('working_directory', selected);
                    }
                  } catch (error) {
                    console.error('Failed to open folder picker:', error);
                  }
                }}
              >
                選択
              </Button>
            </Space.Compact>
          </Form.Item>

          <Text type="secondary">
            コマンドは設定されたデフォルトターミナルで実行されます。
            実行ディレクトリを指定すると、そのディレクトリでコマンドが実行されます。
          </Text>
        </Form>
      </Modal>
    </div>
  );
};

export default SettingsWindow;
