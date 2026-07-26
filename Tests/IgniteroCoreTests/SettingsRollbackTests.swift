import Foundation
import Testing

@testable import IgniteroCore

@Suite("設定保存失敗時のロールバック")
@MainActor
struct SettingsRollbackTests {
  private func makeManagerWithBlockedConfigDirectory() throws -> (
    manager: SettingsManager, rootDirectory: URL
  ) {
    let rootDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ignitero-settings-rollback-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: rootDirectory, withIntermediateDirectories: true)

    let blockedConfigDirectory = rootDirectory.appendingPathComponent("config")
    try Data("設定ディレクトリを妨げるファイル".utf8).write(to: blockedConfigDirectory)

    return (
      SettingsManager(configDirectory: blockedConfigDirectory),
      rootDirectory
    )
  }

  @Test("共通更新処理は保存失敗時に変更前の設定を復元する")
  func updateSettingsRestoresPreviousValueOnSaveFailure() throws {
    let fixture = try makeManagerWithBlockedConfigDirectory()
    defer { try? FileManager.default.removeItem(at: fixture.rootDirectory) }

    do {
      try fixture.manager.updateSettings { $0.defaultTerminal = .ghostty }
      Issue.record("設定保存エラーが送出されませんでした")
    } catch {
      #expect(fixture.manager.settings.defaultTerminal == .terminal)
    }
  }

  @Test("ディレクトリ追加は保存失敗時に配列を復元する")
  func addDirectoryRestoresPreviousArrayOnSaveFailure() throws {
    let fixture = try makeManagerWithBlockedConfigDirectory()
    defer { try? FileManager.default.removeItem(at: fixture.rootDirectory) }
    let previousPaths = fixture.manager.settings.registeredDirectories.map(\.path)
    let directory = RegisteredDirectory(
      path: "/Users/test/project",
      parentOpenMode: .editor,
      parentEditor: nil,
      parentSearchKeyword: nil,
      subdirsOpenMode: .editor,
      subdirsEditor: nil,
      scanForApps: false
    )

    do {
      try fixture.manager.addDirectory(directory)
      Issue.record("設定保存エラーが送出されませんでした")
    } catch {
      #expect(fixture.manager.settings.registeredDirectories.map(\.path) == previousPaths)
    }
  }

  @Test("ビューモデルは保存失敗時に値を復元し変更を通知しない")
  func viewModelRestoresValueAndSkipsNotificationOnSaveFailure() throws {
    let fixture = try makeManagerWithBlockedConfigDirectory()
    defer { try? FileManager.default.removeItem(at: fixture.rootDirectory) }
    let viewModel = SettingsViewModel(settingsManager: fixture.manager)
    var changes: [SettingsChange] = []
    viewModel.onSettingsChanged = { changes.append($0) }

    do {
      try viewModel.setDefaultTerminal(.ghostty)
      Issue.record("設定保存エラーが送出されませんでした")
    } catch {
      #expect(viewModel.settings.defaultTerminal == .terminal)
      #expect(changes.isEmpty)
    }
  }
}
