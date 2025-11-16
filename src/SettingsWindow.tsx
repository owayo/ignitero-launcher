import React, { useState, useEffect } from 'react';
import {
  Modal,
  Form,
  Button,
  List,
  Space,
  Switch,
  InputNumber,
  Select,
  Typography,
  Checkbox,
  Radio,
  Divider,
  Input,
} from 'antd';
import {
  FolderAddOutlined,
  DeleteOutlined,
  ReloadOutlined,
  EditOutlined,
} from '@ant-design/icons';
import { invoke } from '@tauri-apps/api/core';
import { open } from '@tauri-apps/plugin-dialog';
import { emit } from '@tauri-apps/api/event';
import type { Settings, RegisteredDirectory } from './types';
import './Settings.css';

const { Title, Text } = Typography;
const { Option } = Select;

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

  // インストール済みエディタを取得
  const loadAvailableEditors = async () => {
    try {
      const editors = await invoke<string[]>('get_available_editors');
      setAvailableEditors(editors);
    } catch (error) {
      console.error('Failed to load available editors:', error);
    }
  };

  // インストール済みターミナルを取得
  const loadAvailableTerminals = async () => {
    try {
      const terminals = await invoke<string[]>('get_available_terminals');
      setAvailableTerminals(terminals);
    } catch (error) {
      console.error('Failed to load available terminals:', error);
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
  }, []);

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

  return (
    <div className="settings-container">
      <div className="settings-header">
        <Title level={3}>設定</Title>
      </div>

      <div className="settings-layout">
        {/* キャッシュ更新設定 */}
        <div className="settings-panel">
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
            <Title level={5}>キャッシュ更新設定</Title>
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

            <Title level={5} style={{ marginTop: 24 }}>
              デフォルトターミナル
            </Title>
            <Form.Item
              name="default_terminal"
              label="検索結果でディレクトリを選択して→キーを押したときに開くターミナル"
            >
              <Select placeholder="ターミナルを選択">
                {availableTerminals.includes('terminal') && (
                  <Option value="terminal">macOSデフォルトターミナル</Option>
                )}
                {availableTerminals.includes('iterm2') && (
                  <Option value="iterm2">iTerm2</Option>
                )}
                {availableTerminals.includes('warp') && (
                  <Option value="warp">Warp</Option>
                )}
              </Select>
            </Form.Item>

            <Button
              icon={<ReloadOutlined />}
              onClick={handleRefreshCache}
              loading={loading}
              style={{ width: '100%', marginTop: 16 }}
            >
              今すぐキャッシュを更新
            </Button>
          </Form>
        </div>

        {/* 登録ディレクトリ */}
        <div className="settings-panel">
          <Title level={5}>登録ディレクトリ</Title>
          <Button
            icon={<FolderAddOutlined />}
            onClick={handleAddDirectory}
            style={{ marginBottom: 16, width: '100%' }}
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
                        アプリスキャン: {dir.scan_for_apps ? 'はい' : 'いいえ'}
                      </Text>
                    </Space>
                  }
                />
              </List.Item>
            )}
          />
        </div>
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
                        {availableEditors.includes('windsurf') && (
                          <Option value="windsurf">Windsurf</Option>
                        )}
                        {availableEditors.includes('cursor') && (
                          <Option value="cursor">Cursor</Option>
                        )}
                        {availableEditors.includes('code') && (
                          <Option value="code">VS Code</Option>
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
                      {availableEditors.includes('windsurf') && (
                        <Option value="windsurf">Windsurf</Option>
                      )}
                      {availableEditors.includes('cursor') && (
                        <Option value="cursor">Cursor</Option>
                      )}
                      {availableEditors.includes('code') && (
                        <Option value="code">VS Code</Option>
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
    </div>
  );
};

export default SettingsWindow;
