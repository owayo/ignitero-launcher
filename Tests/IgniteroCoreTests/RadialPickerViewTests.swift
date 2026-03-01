import Foundation
import Testing

@testable import IgniteroCore

// MARK: - RadialPickerMode Tests

@Suite("RadialPickerMode")
struct RadialPickerModeTests {

  @Test func editorModeExists() {
    let mode = RadialPickerMode.editor
    #expect(mode == .editor)
  }

  @Test func terminalModeExists() {
    let mode = RadialPickerMode.terminal
    #expect(mode == .terminal)
  }
}

// MARK: - RadialPickerItem Tests

@Suite("RadialPickerItem")
struct RadialPickerItemTests {

  @Test func itemStoresAllProperties() {
    let item = RadialPickerItem(
      id: "windsurf",
      name: "Windsurf",
      shortcutKey: "w",
      installed: true,
      iconPath: "/Applications/Windsurf.app"
    )
    #expect(item.id == "windsurf")
    #expect(item.name == "Windsurf")
    #expect(item.shortcutKey == "w")
    #expect(item.installed == true)
    #expect(item.iconPath == "/Applications/Windsurf.app")
  }

  @Test func itemWithoutShortcutKey() {
    let item = RadialPickerItem(
      id: "terminal",
      name: "Terminal",
      shortcutKey: nil,
      installed: true,
      iconPath: nil
    )
    #expect(item.shortcutKey == nil)
  }

  @Test func itemWithoutIconPath() {
    let item = RadialPickerItem(
      id: "zed",
      name: "Zed",
      shortcutKey: "z",
      installed: false,
      iconPath: nil
    )
    #expect(item.iconPath == nil)
    #expect(item.installed == false)
  }

  @Test func itemConformsToIdentifiable() {
    let item = RadialPickerItem(
      id: "test",
      name: "Test",
      shortcutKey: nil,
      installed: true,
      iconPath: nil
    )
    // Identifiable requires `id` property
    let _: String = item.id
    #expect(item.id == "test")
  }
}

// MARK: - RadialPickerGeometry Tests

@Suite("RadialPickerGeometry Positions for 4 Items")
struct RadialPickerGeometry4ItemTests {

  @Test func fourItemsProducesFourPositions() {
    let positions = RadialPickerGeometry.positions(count: 4, radius: 100, center: (150, 150))
    #expect(positions.count == 4)
  }

  @Test func fourItemsFirstItemIsAtTop() {
    let positions = RadialPickerGeometry.positions(count: 4, radius: 100, center: (150, 150))
    // First item at top: angle = -pi/2, x = center, y = center - radius
    let first = positions[0]
    #expect(abs(first.x - 150) < 0.01)
    #expect(abs(first.y - 50) < 0.01)
    #expect(abs(first.angle - (-.pi / 2)) < 0.01)
  }

  @Test func fourItemsSecondItemIsAtRight() {
    let positions = RadialPickerGeometry.positions(count: 4, radius: 100, center: (150, 150))
    // Second item at right: angle = 0, x = center + radius, y = center
    let second = positions[1]
    #expect(abs(second.x - 250) < 0.01)
    #expect(abs(second.y - 150) < 0.01)
    #expect(abs(second.angle - 0) < 0.01)
  }

  @Test func fourItemsThirdItemIsAtBottom() {
    let positions = RadialPickerGeometry.positions(count: 4, radius: 100, center: (150, 150))
    // Third item at bottom: angle = pi/2, x = center, y = center + radius
    let third = positions[2]
    #expect(abs(third.x - 150) < 0.01)
    #expect(abs(third.y - 250) < 0.01)
    #expect(abs(third.angle - (.pi / 2)) < 0.01)
  }

  @Test func fourItemsFourthItemIsAtLeft() {
    let positions = RadialPickerGeometry.positions(count: 4, radius: 100, center: (150, 150))
    // Fourth item at left: angle = pi, x = center - radius, y = center
    let fourth = positions[3]
    #expect(abs(fourth.x - 50) < 0.01)
    #expect(abs(fourth.y - 150) < 0.01)
    // angle should be pi (or -pi, they are equivalent)
    #expect(abs(abs(fourth.angle) - .pi) < 0.01)
  }
}

@Suite("RadialPickerGeometry Positions for 5 Items")
struct RadialPickerGeometry5ItemTests {

  @Test func fiveItemsProducesFivePositions() {
    let positions = RadialPickerGeometry.positions(count: 5, radius: 100, center: (150, 150))
    #expect(positions.count == 5)
  }

  @Test func fiveItemsFirstItemIsAtTop() {
    let positions = RadialPickerGeometry.positions(count: 5, radius: 100, center: (150, 150))
    let first = positions[0]
    #expect(abs(first.x - 150) < 0.01)
    #expect(abs(first.y - 50) < 0.01)
  }

  @Test func fiveItemsAreEvenlySpaced() {
    let positions = RadialPickerGeometry.positions(count: 5, radius: 100, center: (150, 150))
    // Angle step should be 2*pi/5 = 1.2566...
    let expectedStep = 2.0 * .pi / 5.0
    for i in 0..<4 {
      let angleDiff = positions[i + 1].angle - positions[i].angle
      #expect(abs(angleDiff - expectedStep) < 0.01)
    }
  }

  @Test func fiveItemsAllAtCorrectRadius() {
    let radius: Double = 100
    let center: (Double, Double) = (150, 150)
    let positions = RadialPickerGeometry.positions(count: 5, radius: radius, center: center)
    for pos in positions {
      let dx = pos.x - center.0
      let dy = pos.y - center.1
      let dist = (dx * dx + dy * dy).squareRoot()
      #expect(abs(dist - radius) < 0.01)
    }
  }
}

@Suite("RadialPickerGeometry Edge Cases")
struct RadialPickerGeometryEdgeCaseTests {

  @Test func zeroItemsProducesEmptyArray() {
    let positions = RadialPickerGeometry.positions(count: 0, radius: 100, center: (150, 150))
    #expect(positions.isEmpty)
  }

  @Test func oneItemIsAtTop() {
    let positions = RadialPickerGeometry.positions(count: 1, radius: 100, center: (150, 150))
    #expect(positions.count == 1)
    #expect(abs(positions[0].x - 150) < 0.01)
    #expect(abs(positions[0].y - 50) < 0.01)
  }

  @Test func differentRadiusScalesPositions() {
    let positions = RadialPickerGeometry.positions(count: 4, radius: 50, center: (100, 100))
    let first = positions[0]
    // First item at top: y = center - radius = 100 - 50 = 50
    #expect(abs(first.x - 100) < 0.01)
    #expect(abs(first.y - 50) < 0.01)
  }

  @Test func differentCenterOffsetsPositions() {
    let positions = RadialPickerGeometry.positions(count: 4, radius: 100, center: (200, 300))
    let first = positions[0]
    #expect(abs(first.x - 200) < 0.01)
    #expect(abs(first.y - 200) < 0.01)
  }
}

// MARK: - RadialPickerItemFactory Tests

@Suite("RadialPickerItemFactory Editor Items")
struct RadialPickerItemFactoryEditorTests {

  @Test func editorItemsProduces5Items() {
    let editors: [EditorInfo] = EditorType.allCases.map { type in
      EditorInfo(id: type, name: type.rawValue, appName: "\(type.rawValue).app", installed: true)
    }
    let items = RadialPickerItemFactory.editorItems(from: editors)
    #expect(items.count == 5)
  }

  @Test func editorItemsHaveCorrectShortcutKeys() {
    let editors: [EditorInfo] = [
      EditorInfo(id: .windsurf, name: "Windsurf", appName: "Windsurf.app", installed: true),
      EditorInfo(id: .cursor, name: "Cursor", appName: "Cursor.app", installed: true),
      EditorInfo(id: .vscode, name: "VS Code", appName: "VS Code.app", installed: true),
      EditorInfo(
        id: .antigravity, name: "Antigravity", appName: "Antigravity.app", installed: true),
      EditorInfo(id: .zed, name: "Zed", appName: "Zed.app", installed: true),
    ]
    let items = RadialPickerItemFactory.editorItems(from: editors)
    #expect(items[0].shortcutKey == "w")
    #expect(items[1].shortcutKey == "c")
    #expect(items[2].shortcutKey == "v")
    #expect(items[3].shortcutKey == "a")
    #expect(items[4].shortcutKey == "z")
  }

  @Test func editorItemsPreserveInstalledState() {
    let editors: [EditorInfo] = [
      EditorInfo(id: .windsurf, name: "Windsurf", appName: "Windsurf.app", installed: true),
      EditorInfo(id: .cursor, name: "Cursor", appName: "Cursor.app", installed: false),
    ]
    let items = RadialPickerItemFactory.editorItems(from: editors)
    #expect(items[0].installed == true)
    #expect(items[1].installed == false)
  }

  @Test func editorItemsPreserveIconPath() {
    let editors: [EditorInfo] = [
      EditorInfo(
        id: .windsurf, name: "Windsurf", appName: "Windsurf.app",
        installed: true, iconPath: "/path/to/icon")
    ]
    let items = RadialPickerItemFactory.editorItems(from: editors)
    #expect(items[0].iconPath == "/path/to/icon")
  }

  @Test func editorItemsNilIconPathWhenMissing() {
    let editors: [EditorInfo] = [
      EditorInfo(id: .vscode, name: "VS Code", appName: "VS Code.app", installed: true)
    ]
    let items = RadialPickerItemFactory.editorItems(from: editors)
    #expect(items[0].iconPath == nil)
  }

  @Test func editorItemsPreserveName() {
    let editors: [EditorInfo] = [
      EditorInfo(id: .windsurf, name: "Windsurf", appName: "Windsurf.app", installed: true)
    ]
    let items = RadialPickerItemFactory.editorItems(from: editors)
    #expect(items[0].name == "Windsurf")
  }

  @Test func editorItemsUseEditorTypeRawValueAsId() {
    let editors: [EditorInfo] = [
      EditorInfo(id: .cursor, name: "Cursor", appName: "Cursor.app", installed: true)
    ]
    let items = RadialPickerItemFactory.editorItems(from: editors)
    #expect(items[0].id == "cursor")
  }
}

@Suite("RadialPickerItemFactory Terminal Items")
struct RadialPickerItemFactoryTerminalTests {

  @Test func terminalItemsProduces5Items() {
    let terminals: [TerminalInfo] = TerminalType.allCases.map { type in
      TerminalInfo(id: type, name: type.rawValue, appName: "\(type.rawValue).app", installed: true)
    }
    let items = RadialPickerItemFactory.terminalItems(from: terminals)
    #expect(items.count == 5)
  }

  @Test func terminalItemsHaveNoShortcutKeys() {
    let terminals: [TerminalInfo] = [
      TerminalInfo(id: .terminal, name: "Terminal", appName: "Terminal.app", installed: true),
      TerminalInfo(id: .iterm2, name: "iTerm2", appName: "iTerm.app", installed: true),
    ]
    let items = RadialPickerItemFactory.terminalItems(from: terminals)
    for item in items {
      #expect(item.shortcutKey == nil)
    }
  }

  @Test func terminalItemsPreserveInstalledState() {
    let terminals: [TerminalInfo] = [
      TerminalInfo(id: .terminal, name: "Terminal", appName: "Terminal.app", installed: true),
      TerminalInfo(id: .ghostty, name: "Ghostty", appName: "Ghostty.app", installed: false),
    ]
    let items = RadialPickerItemFactory.terminalItems(from: terminals)
    #expect(items[0].installed == true)
    #expect(items[1].installed == false)
  }

  @Test func terminalItemsPreserveIconPath() {
    let terminals: [TerminalInfo] = [
      TerminalInfo(
        id: .warp, name: "Warp", appName: "Warp.app",
        installed: true, iconPath: "/path/to/warp/icon")
    ]
    let items = RadialPickerItemFactory.terminalItems(from: terminals)
    #expect(items[0].iconPath == "/path/to/warp/icon")
  }

  @Test func terminalItemsUseTerminalTypeRawValueAsId() {
    let terminals: [TerminalInfo] = [
      TerminalInfo(id: .iterm2, name: "iTerm2", appName: "iTerm.app", installed: true)
    ]
    let items = RadialPickerItemFactory.terminalItems(from: terminals)
    #expect(items[0].id == "iterm2")
  }

  @Test func terminalItemsPreserveName() {
    let terminals: [TerminalInfo] = [
      TerminalInfo(id: .ghostty, name: "Ghostty", appName: "Ghostty.app", installed: true)
    ]
    let items = RadialPickerItemFactory.terminalItems(from: terminals)
    #expect(items[0].name == "Ghostty")
  }
}

// MARK: - Grayed Out State Tests

@Suite("RadialPickerItem Installed State")
struct RadialPickerItemInstalledStateTests {

  @Test func installedItemIsNotGrayedOut() {
    let item = RadialPickerItem(
      id: "windsurf",
      name: "Windsurf",
      shortcutKey: "w",
      installed: true,
      iconPath: "/path"
    )
    #expect(item.installed == true)
  }

  @Test func uninstalledItemIsGrayedOut() {
    let item = RadialPickerItem(
      id: "antigravity",
      name: "Antigravity",
      shortcutKey: "a",
      installed: false,
      iconPath: nil
    )
    #expect(item.installed == false)
  }

  @Test func mixedInstalledStateInEditorItems() {
    let editors: [EditorInfo] = [
      EditorInfo(id: .windsurf, name: "Windsurf", appName: "Windsurf.app", installed: true),
      EditorInfo(id: .cursor, name: "Cursor", appName: "Cursor.app", installed: false),
      EditorInfo(id: .vscode, name: "VS Code", appName: "VS Code.app", installed: true),
      EditorInfo(
        id: .antigravity, name: "Antigravity", appName: "Antigravity.app", installed: false),
      EditorInfo(id: .zed, name: "Zed", appName: "Zed.app", installed: true),
    ]
    let items = RadialPickerItemFactory.editorItems(from: editors)
    #expect(items[0].installed == true)  // windsurf
    #expect(items[1].installed == false)  // cursor
    #expect(items[2].installed == true)  // vscode
    #expect(items[3].installed == false)  // antigravity
    #expect(items[4].installed == true)  // zed
  }

  @Test func mixedInstalledStateInTerminalItems() {
    let terminals: [TerminalInfo] = [
      TerminalInfo(id: .terminal, name: "Terminal", appName: "Terminal.app", installed: true),
      TerminalInfo(id: .iterm2, name: "iTerm2", appName: "iTerm.app", installed: false),
      TerminalInfo(id: .ghostty, name: "Ghostty", appName: "Ghostty.app", installed: true),
      TerminalInfo(id: .warp, name: "Warp", appName: "Warp.app", installed: false),
    ]
    let items = RadialPickerItemFactory.terminalItems(from: terminals)
    #expect(items[0].installed == true)  // terminal
    #expect(items[1].installed == false)  // iterm2
    #expect(items[2].installed == true)  // ghostty
    #expect(items[3].installed == false)  // warp
  }
}

// MARK: - RadialPickerGeometry Position Struct Tests

@Suite("RadialPickerPosition")
struct RadialPickerPositionTests {

  @Test func positionStoresAllFields() {
    let pos = RadialPickerPosition(x: 100, y: 200, angle: 1.5)
    #expect(pos.x == 100)
    #expect(pos.y == 200)
    #expect(pos.angle == 1.5)
  }
}
