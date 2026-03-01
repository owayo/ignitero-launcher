import KeyboardShortcuts
import SwiftUI

// MARK: - SettingsView

/// 設定画面のメインビュー。
///
/// macOS 標準の `TabView` を使用し、4つのタブで設定を提供する:
/// - 全般: バージョン表示、デフォルトターミナル選択、キャッシュ更新設定
/// - ディレクトリ: 登録ディレクトリの追加・編集・削除
/// - コマンド: カスタムコマンドの追加・編集・削除
/// - 除外アプリ: スキャン済みアプリの除外切替
public struct SettingsView: View {

  @Bindable var viewModel: SettingsViewModel

  public init(viewModel: SettingsViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    TabView(selection: $viewModel.selectedTab) {
      Tab("全般", systemImage: "gearshape", value: SettingsTab.general) {
        GeneralSettingsTab(viewModel: viewModel)
      }
      Tab("ディレクトリ", systemImage: "folder", value: SettingsTab.directories) {
        DirectoriesSettingsTab(viewModel: viewModel)
      }
      Tab("コマンド", systemImage: "terminal", value: SettingsTab.commands) {
        CommandsSettingsTab(viewModel: viewModel)
      }
      Tab("除外アプリ", systemImage: "xmark.app", value: SettingsTab.excludedApps) {
        ExcludedAppsSettingsTab(viewModel: viewModel)
      }
    }
    .frame(minWidth: 520, minHeight: 400)
  }
}

// MARK: - GeneralSettingsTab

/// 全般タブ: バージョン表示、デフォルトターミナル選択、キャッシュ更新設定。
struct GeneralSettingsTab: View {

  @Bindable var viewModel: SettingsViewModel
  @State private var errorMessage: String?

  var body: some View {
    Form {
      Section("バージョン") {
        LabeledContent("Ignitero Launcher") {
          Text("v\(viewModel.version)")
            .foregroundStyle(.secondary)
        }
      }

      Section("起動") {
        Toggle("ログイン時に開く", isOn: launchAtLoginBinding)
      }

      Section("ショートカット") {
        KeyboardShortcuts.Recorder("ランチャー表示", name: .toggleLauncher)
        Button("デフォルトに戻す") {
          KeyboardShortcuts.reset(.toggleLauncher)
        }
      }

      Section("デフォルトエディタ") {
        if viewModel.installedEditors.isEmpty {
          Text("インストール済みエディタが見つかりません")
            .foregroundStyle(.secondary)
        } else {
          ForEach(viewModel.installedEditors) { editor in
            EditorTerminalRow(
              name: editor.name,
              iconPath: editor.iconPath,
              isSelected: viewModel.settings.defaultEditor == editor.id
            ) {
              do {
                try viewModel.setDefaultEditor(editor.id)
                errorMessage = nil
              } catch {
                errorMessage = "エディタ設定の保存に失敗しました"
              }
            }
          }
        }
      }

      Section("デフォルトターミナル") {
        if viewModel.installedTerminals.isEmpty {
          Text("インストール済みターミナルが見つかりません")
            .foregroundStyle(.secondary)
        } else {
          ForEach(viewModel.installedTerminals) { terminal in
            EditorTerminalRow(
              name: terminal.name,
              iconPath: terminal.iconPath,
              isSelected: viewModel.settings.defaultTerminal == terminal.id
            ) {
              do {
                try viewModel.setDefaultTerminal(terminal.id)
                errorMessage = nil
              } catch {
                errorMessage = "ターミナル設定の保存に失敗しました"
              }
            }
          }
          if viewModel.settings.defaultTerminal == .cmux {
            Text(
              "cmux の Settings → Automation → Socket Control Mode を「Automation mode」に設定してください"
            )
            .font(.caption)
            .foregroundStyle(.red)
          }
        }
      }

      Section("キャッシュ更新") {
        Toggle("起動時にキャッシュを更新", isOn: cacheUpdateOnStartupBinding)
        Toggle("自動更新を有効化", isOn: cacheAutoUpdateBinding)

        if viewModel.settings.cacheUpdate.autoUpdateEnabled {
          Stepper(
            "更新間隔: \(viewModel.settings.cacheUpdate.autoUpdateIntervalHours) 時間",
            value: cacheIntervalBinding,
            in: 1...24
          )
        }
      }

      if let errorMessage {
        Section {
          Text(errorMessage)
            .foregroundStyle(.red)
            .font(.caption)
        }
      }
    }
    .formStyle(.grouped)
    .padding()
  }

  // MARK: - Bindings

  private var launchAtLoginBinding: Binding<Bool> {
    Binding(
      get: { viewModel.launchAtLogin },
      set: { newValue in
        do {
          try viewModel.setLaunchAtLogin(newValue)
          errorMessage = nil
        } catch {
          errorMessage = "ログイン項目の設定に失敗しました"
        }
      }
    )
  }

  private var cacheUpdateOnStartupBinding: Binding<Bool> {
    Binding(
      get: { viewModel.settings.cacheUpdate.updateOnStartup },
      set: { newValue in
        var cache = viewModel.settings.cacheUpdate
        cache.updateOnStartup = newValue
        do {
          try viewModel.setCacheUpdateSettings(cache)
          errorMessage = nil
        } catch {
          errorMessage = "キャッシュ設定の保存に失敗しました: \(error.localizedDescription)"
        }
      }
    )
  }

  private var cacheAutoUpdateBinding: Binding<Bool> {
    Binding(
      get: { viewModel.settings.cacheUpdate.autoUpdateEnabled },
      set: { newValue in
        var cache = viewModel.settings.cacheUpdate
        cache.autoUpdateEnabled = newValue
        do {
          try viewModel.setCacheUpdateSettings(cache)
          errorMessage = nil
        } catch {
          errorMessage = "キャッシュ設定の保存に失敗しました: \(error.localizedDescription)"
        }
      }
    )
  }

  private var cacheIntervalBinding: Binding<Int> {
    Binding(
      get: { viewModel.settings.cacheUpdate.autoUpdateIntervalHours },
      set: { newValue in
        var cache = viewModel.settings.cacheUpdate
        cache.autoUpdateIntervalHours = newValue
        do {
          try viewModel.setCacheUpdateSettings(cache)
          errorMessage = nil
        } catch {
          errorMessage = "キャッシュ設定の保存に失敗しました: \(error.localizedDescription)"
        }
      }
    )
  }
}

// MARK: - DirectoriesSettingsTab

/// ディレクトリタブ: 登録ディレクトリの追加・編集・削除。
struct DirectoriesSettingsTab: View {

  @Bindable var viewModel: SettingsViewModel
  @State private var errorMessage: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      List {
        if viewModel.settings.registeredDirectories.isEmpty {
          Text("登録されたディレクトリはありません")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 20)
        } else {
          ForEach(
            Array(viewModel.settings.registeredDirectories.enumerated()),
            id: \.offset
          ) { index, directory in
            DirectoryRow(
              directory: directory,
              onUpdate: { updated in
                do {
                  try viewModel.updateDirectory(at: index, updated)
                  errorMessage = nil
                } catch {
                  errorMessage = "ディレクトリの更新に失敗しました"
                }
              },
              onDelete: {
                do {
                  try viewModel.removeDirectory(at: index)
                  errorMessage = nil
                } catch {
                  errorMessage = "ディレクトリの削除に失敗しました"
                }
              }
            )
          }
        }
      }

      Divider()

      HStack {
        Button {
          addDirectory()
        } label: {
          Label("ディレクトリを追加", systemImage: "plus")
        }

        Spacer()

        if let errorMessage {
          Text(errorMessage)
            .foregroundStyle(.red)
            .font(.caption)
        }
      }
      .padding(12)
    }
  }

  private func addDirectory() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.message = "登録するディレクトリを選択してください"

    guard panel.runModal() == .OK, let url = panel.url else { return }

    do {
      try viewModel.addDirectory(
        path: url.path,
        parentOpenMode: .editor,
        subdirsOpenMode: .editor,
        scanForApps: false
      )
      errorMessage = nil
    } catch {
      errorMessage = "ディレクトリの追加に失敗しました"
    }
  }
}

// MARK: - DirectoryRow

/// ディレクトリ一覧の各行。
struct DirectoryRow: View {

  let directory: RegisteredDirectory
  let onUpdate: (RegisteredDirectory) -> Void
  let onDelete: () -> Void

  @State private var isEditing = false

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Image(systemName: "folder.fill")
          .foregroundStyle(.blue)
        Text(directory.path)
          .lineLimit(1)
          .truncationMode(.middle)
        Spacer()
        HStack(spacing: 20) {
          Button {
            isEditing.toggle()
          } label: {
            Image(systemName: "pencil")
          }
          .buttonStyle(.borderless)
          .foregroundStyle(.secondary)

          Button(role: .destructive) {
            onDelete()
          } label: {
            Image(systemName: "trash")
          }
          .buttonStyle(.borderless)
        }
      }

      if isEditing {
        DirectoryEditForm(
          directory: directory,
          onSave: { updated in
            onUpdate(updated)
            isEditing = false
          })
      } else {
        HStack(spacing: 12) {
          Label(directory.parentOpenMode.displayName, systemImage: "arrow.up.doc")
            .font(.caption)
            .foregroundStyle(.secondary)
          Label(directory.subdirsOpenMode.displayName, systemImage: "arrow.down.doc")
            .font(.caption)
            .foregroundStyle(.secondary)
          if directory.scanForApps {
            Label("アプリスキャン", systemImage: "app.badge.checkmark")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
    .padding(.vertical, 4)
  }
}

// MARK: - DirectoryEditForm

/// ディレクトリ設定の編集フォーム。
struct DirectoryEditForm: View {

  @State private var editedDirectory: RegisteredDirectory
  let onSave: (RegisteredDirectory) -> Void

  init(directory: RegisteredDirectory, onSave: @escaping (RegisteredDirectory) -> Void) {
    self._editedDirectory = State(initialValue: directory)
    self.onSave = onSave
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Picker("親ディレクトリ", selection: $editedDirectory.parentOpenMode) {
        ForEach(OpenMode.allCases, id: \.self) { mode in
          Text(mode.displayName).tag(mode)
        }
      }
      .pickerStyle(.segmented)

      Picker("サブディレクトリ", selection: $editedDirectory.subdirsOpenMode) {
        ForEach(OpenMode.allCases, id: \.self) { mode in
          Text(mode.displayName).tag(mode)
        }
      }
      .pickerStyle(.segmented)

      Toggle("アプリをスキャン", isOn: $editedDirectory.scanForApps)

      HStack {
        Spacer()
        Button("保存") {
          onSave(editedDirectory)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
      }
    }
    .padding(.leading, 24)
    .padding(.vertical, 4)
  }
}

// MARK: - CommandsSettingsTab

/// コマンドタブ: カスタムコマンドの追加・編集・削除。
struct CommandsSettingsTab: View {

  @Bindable var viewModel: SettingsViewModel
  @State private var errorMessage: String?
  @State private var isAddingCommand = false
  @State private var newAlias = ""
  @State private var newCommand = ""
  @State private var newWorkingDirectory = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      List {
        if viewModel.settings.customCommands.isEmpty && !isAddingCommand {
          Text("カスタムコマンドはありません")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 20)
        }

        ForEach(
          Array(viewModel.settings.customCommands.enumerated()),
          id: \.offset
        ) { index, command in
          CommandRow(
            command: command,
            onUpdate: { updated in
              do {
                try viewModel.updateCommand(at: index, updated)
                errorMessage = nil
              } catch {
                errorMessage = "コマンドの更新に失敗しました"
              }
            },
            onDelete: {
              do {
                try viewModel.removeCommand(at: index)
                errorMessage = nil
              } catch {
                errorMessage = "コマンドの削除に失敗しました"
              }
            }
          )
        }

        if isAddingCommand {
          VStack(alignment: .leading, spacing: 8) {
            TextField("エイリアス", text: $newAlias)
            TextField("コマンド", text: $newCommand)
            TextField("作業ディレクトリ（任意）", text: $newWorkingDirectory)

            HStack {
              Spacer()
              Button("キャンセル") {
                resetNewCommandForm()
              }
              .controlSize(.small)

              Button("追加") {
                addCommand()
              }
              .buttonStyle(.borderedProminent)
              .controlSize(.small)
              .disabled(newAlias.isEmpty || newCommand.isEmpty)
            }
          }
          .padding(.vertical, 4)
        }
      }

      Divider()

      HStack {
        Button {
          isAddingCommand = true
        } label: {
          Label("コマンドを追加", systemImage: "plus")
        }
        .disabled(isAddingCommand)

        Spacer()

        if let errorMessage {
          Text(errorMessage)
            .foregroundStyle(.red)
            .font(.caption)
        }
      }
      .padding(12)
    }
  }

  private func addCommand() {
    do {
      try viewModel.addCommand(
        alias: newAlias,
        command: newCommand,
        workingDirectory: newWorkingDirectory.isEmpty ? nil : newWorkingDirectory
      )
      resetNewCommandForm()
      errorMessage = nil
    } catch {
      errorMessage = "コマンドの追加に失敗しました"
    }
  }

  private func resetNewCommandForm() {
    isAddingCommand = false
    newAlias = ""
    newCommand = ""
    newWorkingDirectory = ""
  }
}

// MARK: - CommandRow

/// コマンド一覧の各行。
struct CommandRow: View {

  let command: CustomCommand
  let onUpdate: (CustomCommand) -> Void
  let onDelete: () -> Void

  @State private var isEditing = false
  @State private var editedAlias: String
  @State private var editedCommand: String
  @State private var editedWorkingDirectory: String

  init(
    command: CustomCommand,
    onUpdate: @escaping (CustomCommand) -> Void,
    onDelete: @escaping () -> Void
  ) {
    self.command = command
    self.onUpdate = onUpdate
    self.onDelete = onDelete
    self._editedAlias = State(initialValue: command.alias)
    self._editedCommand = State(initialValue: command.command)
    self._editedWorkingDirectory = State(initialValue: command.workingDirectory ?? "")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Image(systemName: "terminal")
          .foregroundStyle(.green)
        Text(command.alias)
          .fontWeight(.medium)
        Text(command.command)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        Spacer()
        HStack(spacing: 20) {
          Button {
            isEditing.toggle()
          } label: {
            Image(systemName: "pencil")
          }
          .buttonStyle(.borderless)
          .foregroundStyle(.secondary)

          Button(role: .destructive) {
            onDelete()
          } label: {
            Image(systemName: "trash")
          }
          .buttonStyle(.borderless)
        }
      }

      if isEditing {
        VStack(alignment: .leading, spacing: 8) {
          TextField("エイリアス", text: $editedAlias)
          TextField("コマンド", text: $editedCommand)
          TextField("作業ディレクトリ（任意）", text: $editedWorkingDirectory)

          HStack {
            Spacer()
            Button("キャンセル") {
              isEditing = false
              editedAlias = command.alias
              editedCommand = command.command
              editedWorkingDirectory = command.workingDirectory ?? ""
            }
            .controlSize(.small)

            Button("保存") {
              let updated = CustomCommand(
                alias: editedAlias,
                command: editedCommand,
                workingDirectory: editedWorkingDirectory.isEmpty ? nil : editedWorkingDirectory
              )
              onUpdate(updated)
              isEditing = false
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(editedAlias.isEmpty || editedCommand.isEmpty)
          }
        }
        .padding(.leading, 24)
        .padding(.vertical, 4)
      } else if let workDir = command.workingDirectory {
        Label(workDir, systemImage: "folder")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 4)
  }
}

// MARK: - ExcludedAppsSettingsTab

/// 除外アプリタブ: スキャン済みアプリの除外切替。
struct ExcludedAppsSettingsTab: View {

  @Bindable var viewModel: SettingsViewModel
  @State private var searchText = ""
  @State private var errorMessage: String?

  private var filteredApps: [AppItem] {
    if searchText.isEmpty {
      return viewModel.allApps
    }
    return viewModel.allApps.filter {
      $0.name.localizedCaseInsensitiveContains(searchText)
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)
        TextField("アプリを検索", text: $searchText)
          .textFieldStyle(.plain)
      }
      .padding(8)

      Divider()

      if viewModel.allApps.isEmpty {
        VStack {
          Spacer()
          Text("アプリが検出されていません")
            .foregroundStyle(.secondary)
          Spacer()
        }
        .frame(maxWidth: .infinity)
      } else {
        List(filteredApps) { app in
          ExcludedAppRow(app: app, viewModel: viewModel, onError: { errorMessage = $0 })
        }
      }

      if let errorMessage {
        Divider()
        Text(errorMessage)
          .foregroundStyle(.red)
          .font(.caption)
          .padding(8)
      }
    }
  }
}

// MARK: - ExcludedAppRow

/// 除外アプリ一覧の各行。目のアイコンで表示/非表示を切り替える。
struct ExcludedAppRow: View {

  let app: AppItem
  let viewModel: SettingsViewModel
  let onError: (String?) -> Void

  var body: some View {
    let isExcluded = viewModel.isAppExcluded(app.name)
    HStack(spacing: 12) {
      if let iconPath = app.iconPath,
        let nsImage = NSImage(contentsOfFile: iconPath)
      {
        Image(nsImage: nsImage)
          .resizable()
          .frame(width: 28, height: 28)
          .opacity(isExcluded ? 0.3 : 1.0)
      } else {
        Image(systemName: "app.fill")
          .resizable()
          .frame(width: 28, height: 28)
          .foregroundStyle(isExcluded ? .gray : .purple)
      }

      VStack(alignment: .leading, spacing: 2) {
        Text(app.name)
          .foregroundStyle(isExcluded ? .secondary : .primary)
        Text(app.path)
          .font(.caption)
          .foregroundStyle(.tertiary)
          .lineLimit(1)
          .truncationMode(.middle)
      }

      Spacer()

      Button {
        do {
          try viewModel.toggleExcludedApp(app.name)
          onError(nil)
        } catch {
          onError("除外設定の保存に失敗しました")
        }
      } label: {
        Image(systemName: isExcluded ? "eye.slash" : "eye")
          .foregroundStyle(isExcluded ? Color.secondary : Color.blue)
          .frame(width: 24)
      }
      .buttonStyle(.borderless)
      .help(isExcluded ? "ランチャーに表示する" : "ランチャーから除外する")
    }
  }
}

// MARK: - EditorTerminalRow

/// エディタ/ターミナル選択行（アイコン + 名前 + チェックマーク）。
struct EditorTerminalRow: View {

  let name: String
  let iconPath: String?
  let isSelected: Bool
  let onSelect: () -> Void

  var body: some View {
    Button(action: onSelect) {
      HStack(spacing: 10) {
        if let iconPath, let nsImage = NSImage(contentsOfFile: iconPath) {
          Image(nsImage: nsImage)
            .resizable()
            .frame(width: 24, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
          Image(systemName: "app.fill")
            .resizable()
            .frame(width: 24, height: 24)
            .foregroundStyle(.secondary)
        }

        Text(name)
          .foregroundStyle(.primary)

        Spacer()

        if isSelected {
          Image(systemName: "checkmark")
            .foregroundStyle(.blue)
            .fontWeight(.semibold)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Display Name Extensions

extension TerminalType {
  /// ターミナルタイプの表示名。
  var displayName: String {
    switch self {
    case .terminal: "ターミナル"
    case .iterm2: "iTerm2"
    case .ghostty: "Ghostty"
    case .warp: "Warp"
    case .cmux: "cmux"
    }
  }
}

extension OpenMode {
  /// オープンモードの表示名。
  var displayName: String {
    switch self {
    case .none: "なし"
    case .finder: "Finder"
    case .editor: "エディタ"
    }
  }
}
