import AppKit
import Foundation
import SwiftUI

// MARK: - RadialPickerMode

/// ラジアルピッカーの動作モード。
public enum RadialPickerMode: Sendable {
  /// エディタ選択モード（Windsurf/Cursor/VS Code/Antigravity/Zed）
  case editor
  /// ターミナル選択モード（Terminal/iTerm2/Ghostty/Warp）
  case terminal
}

// MARK: - RadialPickerItem

/// ラジアルピッカーに表示する個別アイテム。
public struct RadialPickerItem: Identifiable, Sendable {
  /// 一意な識別子（EditorType.rawValue または TerminalType.rawValue）
  public let id: String
  /// 表示名
  public let name: String
  /// ショートカットキー（エディタモードのみ、ターミナルモードでは nil）
  public let shortcutKey: String?
  /// インストール済みかどうか（未インストールの場合はグレーアウト表示）
  public let installed: Bool
  /// アプリアイコンのパス
  public let iconPath: String?

  public init(
    id: String,
    name: String,
    shortcutKey: String?,
    installed: Bool,
    iconPath: String?
  ) {
    self.id = id
    self.name = name
    self.shortcutKey = shortcutKey
    self.installed = installed
    self.iconPath = iconPath
  }
}

// MARK: - RadialPickerPosition

/// 円上のアイテム位置を表す構造体。
public struct RadialPickerPosition: Sendable {
  /// X 座標
  public let x: Double
  /// Y 座標
  public let y: Double
  /// 角度（ラジアン、-pi/2 が上方向）
  public let angle: Double

  public init(x: Double, y: Double, angle: Double) {
    self.x = x
    self.y = y
    self.angle = angle
  }
}

// MARK: - RadialPickerGeometry

/// N 個のアイテムを円上に均等配置するジオメトリ計算ユーティリティ。
public enum RadialPickerGeometry {

  /// 指定された数のアイテムを円上に均等配置した位置を計算する。
  ///
  /// 最初のアイテムは円の上端（角度 -pi/2）に配置され、
  /// 時計回りに等間隔で配置される。
  ///
  /// - Parameters:
  ///   - count: アイテム数
  ///   - radius: 円の半径
  ///   - center: 円の中心座標 (x, y)
  /// - Returns: 各アイテムの位置情報の配列
  public static func positions(
    count: Int,
    radius: Double,
    center: (Double, Double)
  ) -> [RadialPickerPosition] {
    guard count > 0 else { return [] }

    let angleStep = 2.0 * .pi / Double(count)
    // 上端から開始（-pi/2）
    let startAngle = -.pi / 2.0

    return (0..<count).map { index in
      let angle = startAngle + angleStep * Double(index)
      let x = center.0 + radius * cos(angle)
      let y = center.1 + radius * sin(angle)
      return RadialPickerPosition(x: x, y: y, angle: angle)
    }
  }
}

// MARK: - RadialPickerItemFactory

/// EditorInfo / TerminalInfo から RadialPickerItem を生成するファクトリ。
public enum RadialPickerItemFactory {

  /// エディタタイプに対応するショートカットキーを返す（MainActor 非依存）。
  private static func shortcutKey(for editor: EditorType) -> String {
    switch editor {
    case .windsurf: "w"
    case .cursor: "c"
    case .vscode: "v"
    case .antigravity: "a"
    case .zed: "z"
    }
  }

  /// EditorInfo 配列から RadialPickerItem 配列を生成する。
  ///
  /// 各エディタにはショートカットキーが付与される（w/c/v/a/z）。
  ///
  /// - Parameter editors: エディタ情報の配列
  /// - Returns: ラジアルピッカーアイテムの配列
  public static func editorItems(from editors: [EditorInfo]) -> [RadialPickerItem] {
    editors.map { editor in
      RadialPickerItem(
        id: editor.id.rawValue,
        name: editor.name,
        shortcutKey: shortcutKey(for: editor.id),
        installed: editor.installed,
        iconPath: editor.iconPath
      )
    }
  }

  /// TerminalInfo 配列から RadialPickerItem 配列を生成する。
  ///
  /// ターミナルにはショートカットキーは付与されない。
  ///
  /// - Parameter terminals: ターミナル情報の配列
  /// - Returns: ラジアルピッカーアイテムの配列
  public static func terminalItems(from terminals: [TerminalInfo]) -> [RadialPickerItem] {
    terminals.map { terminal in
      RadialPickerItem(
        id: terminal.id.rawValue,
        name: terminal.name,
        shortcutKey: nil,
        installed: terminal.installed,
        iconPath: terminal.iconPath
      )
    }
  }
}

// MARK: - RadialPickerView

/// ラジアル（円形）ピッカー SwiftUI ビュー。
///
/// Canvas と Path を使用してアイテムを円形に配置し、
/// ハイライト・グレーアウト・ショートカットキーラベルを描画する。
public struct RadialPickerView: View {

  // MARK: - Configuration

  /// 表示するアイテム一覧
  public let items: [RadialPickerItem]
  /// ピッカーモード
  public let mode: RadialPickerMode
  /// 現在ハイライトされているインデックス
  public var highlightedIndex: Int?
  /// 円の半径
  public let radius: Double
  /// ビュー全体のサイズ
  public let size: Double

  // MARK: - Computed

  private var center: (Double, Double) {
    (size / 2, size / 2)
  }

  private var positions: [RadialPickerPosition] {
    RadialPickerGeometry.positions(count: items.count, radius: radius, center: center)
  }

  // MARK: - Constants

  private let itemRadius: Double = 34
  private let iconSize: Double = 48
  private let shortcutKeyFontSize: Double = 10

  // MARK: - Initialization

  public init(
    items: [RadialPickerItem],
    mode: RadialPickerMode,
    highlightedIndex: Int? = nil,
    radius: Double = 100,
    size: Double = 320
  ) {
    self.items = items
    self.mode = mode
    self.highlightedIndex = highlightedIndex
    self.radius = radius
    self.size = size
  }

  // MARK: - Body

  public var body: some View {
    Canvas { context, canvasSize in
      // 各アイテムを描画
      for (index, item) in items.enumerated() {
        guard index < positions.count else { continue }
        let position = positions[index]
        let isHighlighted = highlightedIndex == index
        drawItem(
          context: context,
          item: item,
          position: CGPoint(x: position.x, y: position.y),
          isHighlighted: isHighlighted
        )
      }
    }
    .frame(width: size, height: size)
  }

  // MARK: - Drawing Helpers

  /// 個別アイテムを描画する。
  ///
  /// - アイコン画像（アイコンパスがある場合）
  /// - ハイライト状態（選択中のアイテムはアクセントカラー枠）
  /// - グレーアウト（未インストールの場合）
  /// - ショートカットキーラベル（エディタモードのみ）
  private func drawItem(
    context: GraphicsContext,
    item: RadialPickerItem,
    position: CGPoint,
    isHighlighted: Bool
  ) {
    let rect = CGRect(
      x: position.x - itemRadius,
      y: position.y - itemRadius,
      width: itemRadius * 2,
      height: itemRadius * 2
    )

    // アイテム背景円
    let circlePath = Circle().path(in: rect)

    if !item.installed {
      // 未インストール: グレーアウト
      context.fill(circlePath, with: .color(.gray.opacity(0.15)))
      context.stroke(circlePath, with: .color(.gray.opacity(0.3)), lineWidth: 1)
    } else if isHighlighted {
      // ハイライト: アクセントカラー
      context.fill(circlePath, with: .color(.accentColor.opacity(0.2)))
      context.stroke(circlePath, with: .color(.accentColor), lineWidth: 2.5)
    } else {
      // 通常: 半透明背景
      context.fill(circlePath, with: .color(.gray.opacity(0.1)))
      context.stroke(circlePath, with: .color(.gray.opacity(0.5)), lineWidth: 1)
    }

    // アプリアイコン描画
    if let iconPath = item.iconPath,
      let nsImage = NSImage(contentsOfFile: iconPath)
    {
      // Retina 対応: 論理サイズを明示してピクセル密度を活かす
      nsImage.size = NSSize(width: iconSize, height: iconSize)
      let image = Image(nsImage: nsImage)
        .interpolation(.high)
      let iconRect = CGRect(
        x: position.x - iconSize / 2,
        y: position.y - iconSize / 2,
        width: iconSize,
        height: iconSize
      )
      var iconContext = context
      if !item.installed {
        iconContext.opacity = 0.3
      }
      iconContext.draw(iconContext.resolve(image), in: iconRect)
    } else {
      // アイコンがない場合: 名前の頭文字を表示
      let initial = String(item.name.prefix(1))
      let font = Font.system(size: 16, weight: .semibold)
      let text = Text(initial)
        .font(font)
        .foregroundStyle(item.installed ? Color.primary : Color.gray.opacity(0.5))
      let resolvedText = context.resolve(text)
      let textSize = resolvedText.measure(in: CGSize(width: 100, height: 100))
      context.draw(
        resolvedText,
        at: CGPoint(x: position.x - textSize.width / 2, y: position.y - textSize.height / 2),
        anchor: .topLeading
      )
    }

    // 名前ラベル（アイテム円の下、ピル型白背景付き）
    let nameFont = Font.system(size: 12, weight: .medium)
    let nameColor: Color =
      isHighlighted
      ? Color(red: 0.76, green: 0.27, blue: 0.06)
      : (item.installed ? Color(red: 0.2, green: 0.2, blue: 0.22) : .gray.opacity(0.5))
    let nameText = Text(item.name)
      .font(nameFont)
      .foregroundStyle(nameColor)
    let resolvedName = context.resolve(nameText)
    let nameSize = resolvedName.measure(in: CGSize(width: 120, height: 30))
    let namePadH: Double = 8
    let namePadV: Double = 3
    let nameOffsetY = itemRadius + 10.0
    let nameBgRect = CGRect(
      x: position.x - nameSize.width / 2 - namePadH,
      y: position.y + nameOffsetY - namePadV,
      width: nameSize.width + namePadH * 2,
      height: nameSize.height + namePadV * 2
    )
    let nameBgPath = RoundedRectangle(cornerRadius: 6).path(in: nameBgRect)
    context.fill(nameBgPath, with: .color(.white.opacity(0.9)))
    if isHighlighted {
      context.stroke(
        nameBgPath, with: .color(Color(red: 1.0, green: 0.47, blue: 0.28).opacity(0.4)),
        lineWidth: 1)
    }
    context.draw(
      resolvedName,
      at: CGPoint(
        x: position.x - nameSize.width / 2,
        y: position.y + nameOffsetY
      ),
      anchor: .topLeading
    )

    // ショートカットキーラベル（エディタモードのみ）
    if mode == .editor, let shortcutKey = item.shortcutKey {
      let keyFont = Font.system(size: shortcutKeyFontSize, weight: .bold, design: .monospaced)
      let keyColor: Color = item.installed ? .secondary : .gray.opacity(0.3)
      let keyText = Text(shortcutKey.uppercased())
        .font(keyFont)
        .foregroundStyle(keyColor)
      let resolvedKey = context.resolve(keyText)
      let keySize = resolvedKey.measure(in: CGSize(width: 30, height: 20))
      // ショートカットキーをアイテム円の右上に配置
      context.draw(
        resolvedKey,
        at: CGPoint(
          x: position.x + itemRadius - keySize.width / 2,
          y: position.y - itemRadius - keySize.height / 2
        ),
        anchor: .topLeading
      )
    }
  }
}

// MARK: - Convenience Initializers

extension RadialPickerView {

  /// EditorPickerState から RadialPickerView を生成する。
  ///
  /// - Parameters:
  ///   - editorState: エディタピッカーの選択状態
  ///   - editors: エディタ情報の配列
  ///   - radius: 円の半径（デフォルト: 100）
  ///   - size: ビューサイズ（デフォルト: 320）
  @MainActor
  public init(
    editorState: EditorPickerState,
    editors: [EditorInfo],
    radius: Double = 100,
    size: Double = 320
  ) {
    self.init(
      items: RadialPickerItemFactory.editorItems(from: editors),
      mode: .editor,
      highlightedIndex: editorState.selectedIndex,
      radius: radius,
      size: size
    )
  }

  /// TerminalPickerState から RadialPickerView を生成する。
  ///
  /// - Parameters:
  ///   - terminalState: ターミナルピッカーの選択状態
  ///   - radius: 円の半径（デフォルト: 100）
  ///   - size: ビューサイズ（デフォルト: 320）
  public init(
    terminalState: TerminalPickerState,
    radius: Double = 100,
    size: Double = 320
  ) {
    self.init(
      items: RadialPickerItemFactory.terminalItems(from: terminalState.terminals),
      mode: .terminal,
      highlightedIndex: terminalState.highlightedIndex,
      radius: radius,
      size: size
    )
  }
}
