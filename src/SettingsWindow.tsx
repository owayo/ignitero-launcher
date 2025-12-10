import React, { useState, useEffect } from 'react';
import {
  Alert,
  Button,
  Card,
  Checkbox,
  Descriptions,
  Divider,
  Form,
  Input,
  InputNumber,
  List,
  Modal,
  Radio,
  Select,
  Space,
  Switch,
  Tabs,
  Typography,
} from 'antd';
import {
  CloudSyncOutlined,
  DeleteOutlined,
  EditOutlined,
  FolderAddOutlined,
  PlusOutlined,
  ReloadOutlined,
} from '@ant-design/icons';
import { convertFileSrc, invoke } from '@tauri-apps/api/core';
import { open } from '@tauri-apps/plugin-dialog';
import { emit } from '@tauri-apps/api/event';
import type { Settings, RegisteredDirectory, CustomCommand } from './types';
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
  const [loading, setLoading] = useState(false);
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
      };
      await invoke('add_command', { cmd });
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
      setLoading(true);
      await invoke('refresh_cache');
      alert('キャッシュを更新しました');
    } catch (error) {
      console.error('Failed to refresh cache:', error);
      alert('キャッシュの更新に失敗しました');
    } finally {
      setLoading(false);
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
      <div className="settings-header">
        <Title level={3}>設定</Title>
      </div>

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
          <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
            <div
              style={{
                display: 'grid',
                gap: 16,
                gridTemplateColumns: 'repeat(auto-fit, minmax(320px, 1fr))',
                alignItems: 'start',
              }}
            >
              <Card
                title="バージョンチェック"
                bodyStyle={{
                  display: 'flex',
                  flexDirection: 'column',
                  gap: 12,
                }}
              >
                <Descriptions size="small" column={1}>
                  <Descriptions.Item label="現在のバージョン">
                    v{packageJson.version}
                  </Descriptions.Item>
                </Descriptions>
                <Space>
                  <Button
                    type="primary"
                    icon={<CloudSyncOutlined />}
                    loading={checkingUpdate}
                    onClick={handleCheckUpdates}
                  >
                    更新を確認
                  </Button>
                  {updateInfo && !updateInfo.has_update && (
                    <Text type="secondary">最新バージョンです</Text>
                  )}
                </Space>
                {updateError && <Text type="danger">{updateError}</Text>}
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
              </Card>

              <Card
                title="デフォルトターミナル"
                bodyStyle={{ paddingBottom: 0 }}
              >
                <Form.Item
                  name="default_terminal"
                  label="検索結果でディレクトリを選択して→キーを押したときに開くターミナル"
                >
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
              </Card>
            </div>

            <Card title="キャッシュ更新" bodyStyle={{ paddingBottom: 0 }}>
              <Form.Item
                name="update_on_startup"
                label="起動時に更新"
                valuePropName="checked"
              >
                <Switch />
              </Form.Item>

              <Form.Item
                name="auto_update_enabled"
                label="自動更新を有効化"
                valuePropName="checked"
              >
                <Switch />
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
                      >
                        <InputNumber min={1} max={24} />
                      </Form.Item>
                    )
                  );
                }}
              </Form.Item>

              <Button
                icon={<ReloadOutlined />}
                onClick={handleRefreshCache}
                loading={loading}
                style={{ width: '100%', marginTop: 8, marginBottom: 4 }}
              >
                今すぐキャッシュを更新
              </Button>
            </Card>

            <Card bodyStyle={{ padding: 0 }}>
              <Tabs
                defaultActiveKey="directories"
                items={[
                  {
                    key: 'directories',
                    label: 'ディレクトリ',
                    children: (
                      <div
                        style={{
                          display: 'flex',
                          flexDirection: 'column',
                          gap: 12,
                          padding: '12px 16px',
                        }}
                      >
                        <Button
                          icon={<FolderAddOutlined />}
                          onClick={handleAddDirectory}
                          style={{ width: '100%' }}
                        >
                          ディレクトリを追加
                        </Button>

                        <List
                          dataSource={
                            settings?.registered_directories
                              ? [...settings.registered_directories].sort(
                                  (a, b) => a.path.localeCompare(b.path),
                                )
                              : []
                          }
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
                                  onClick={() =>
                                    handleRemoveDirectory(dir.path)
                                  }
                                >
                                  削除
                                </Button>,
                              ]}
                            >
                              <List.Item.Meta
                                title={dir.path}
                                description={
                                  <Space direction="vertical" size={0}>
                                    <Text>
                                      このディレクトリ自身:{' '}
                                      {dir.parent_open_mode === 'none'
                                        ? '表示しない'
                                        : dir.parent_open_mode === 'finder'
                                          ? 'Finderで開く'
                                          : `${dir.parent_editor || 'エディタ'}で開く`}
                                    </Text>
                                    <Text>
                                      配下のディレクトリ:{' '}
                                      {dir.subdirs_open_mode === 'none'
                                        ? '表示しない'
                                        : dir.subdirs_open_mode === 'finder'
                                          ? 'Finderで開く'
                                          : `${dir.subdirs_editor || 'エディタ'}で開く`}
                                    </Text>
                                    <Text>
                                      アプリスキャン:{' '}
                                      {dir.scan_for_apps ? 'はい' : 'いいえ'}
                                    </Text>
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
                    label: 'コマンド',
                    children: (
                      <div
                        style={{
                          display: 'flex',
                          flexDirection: 'column',
                          gap: 12,
                          padding: '12px 16px',
                        }}
                      >
                        <Button
                          icon={<PlusOutlined />}
                          onClick={handleAddCommand}
                          style={{ width: '100%' }}
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
                                  <Text
                                    code
                                    style={{
                                      wordBreak: 'break-all',
                                      whiteSpace: 'pre-wrap',
                                    }}
                                  >
                                    {cmd.command}
                                  </Text>
                                }
                              />
                            </List.Item>
                          )}
                        />
                      </div>
                    ),
                  },
                ]}
              />
            </Card>
          </div>
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
              placeholder="例: cd ~/project && npm run deploy"
              autoSize={{ minRows: 2, maxRows: 6 }}
            />
          </Form.Item>

          <Text type="secondary">
            コマンドは設定されたデフォルトターミナルで実行されます。
          </Text>
        </Form>
      </Modal>
    </div>
  );
};

export default SettingsWindow;
