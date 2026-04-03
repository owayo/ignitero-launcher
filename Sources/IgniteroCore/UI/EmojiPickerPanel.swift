import AppKit
import EmojiKit
import SwiftUI

// MARK: - EmojiPickerContentView

/// Emoji ピッカーのコンテンツビュー。
///
/// EmojiKit の `EmojiGridScrollView` を利用し、カテゴリ別絵文字グリッド・検索・肌の色選択を提供する。
/// 検索には emojibase ベースの日本語キーワード辞書を併用し、
/// 「いいね」→ 👍 のようなキーワード検索をサポートする。
/// 全カテゴリの定義（タブバー表示順）
private let allCategories: [EmojiCategory] = .standardGrid

// MARK: - CategoryTabButton

/// カテゴリタブの個別ボタン。型推論の負荷を軽減するため独立 View として切り出す。
private struct CategoryTabButton: View {
  let cat: EmojiCategory
  let isActive: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: cat.symbolIconName)
        .font(.system(size: 15))
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .foregroundStyle(isActive ? .primary : .secondary)
        .background(isActive ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.clear))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    .buttonStyle(.plain)
    .help(cat.localizedName)
  }
}

// MARK: - EmojiPickerContentView

private struct EmojiPickerContentView: View {

  @State private var query = ""
  @State private var category: EmojiCategory?
  @State private var selection: Emoji.GridSelection?
  @State private var searchCategories: [EmojiCategory]?
  @State private var scrollProxy: ScrollViewProxy?

  let keywordSearch: EmojiKeywordSearch
  var onSelect: ((String) -> Void)?

  private var isSearching: Bool {
    !query.trimmingCharacters(in: .whitespaces).isEmpty
  }

  var body: some View {
    VStack(spacing: 0) {
      // 検索フィールド
      searchField

      // カテゴリタブバー（検索中は非表示）
      if !isSearching {
        categoryTabBar
      }

      Divider()

      // Emoji グリッド
      emojiGrid
    }
    .background(.clear)
  }

  // MARK: - Search Field

  private var searchField: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
        .font(.system(size: 13))
      TextField("絵文字を検索", text: $query)
        .textFieldStyle(.plain)
        .font(.system(size: 14))
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(.ultraThinMaterial)
  }

  // MARK: - Category Tab Bar

  private var categoryTabBar: some View {
    HStack(spacing: 2) {
      ForEach(Array(allCategories.enumerated()), id: \.offset) { _, cat in
        CategoryTabButton(
          cat: cat,
          isActive: category?.id == cat.id,
          action: { scrollToCategory(cat) }
        )
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(.ultraThinMaterial)
  }

  // MARK: - Emoji Grid

  /// EmojiKit の `EmojiGridScrollView` を使わず、`EmojiGrid` を直接配置し
  /// 自前の `ScrollViewReader` でカテゴリスクロールを制御する。
  ///
  /// `EmojiGridScrollView` 経由だと内部の `isInternalChange` ガードや
  /// SwiftUI の `onChange` 合体により、タブタップ時にスクロールが発火しない問題がある。
  private var emojiGrid: some View {
    GeometryReader { geo in
      ScrollViewReader { proxy in
        ScrollView(.vertical) {
          EmojiGrid(
            axis: .vertical,
            categories: searchCategories ?? allCategories,
            category: $category,
            selection: $selection,
            geometryProxy: geo,
            scrollViewProxy: proxy,
            action: { emoji in
              onSelect?(emoji.char)
            },
            sectionTitle: { $0.view },
            gridItem: { $0.view }
          )
        }
        .onAppear { scrollProxy = proxy }
      }
    }
    .emojiGridStyle(EmojiGridStyle(fontSize: 45))
    .onChange(of: query) {
      updateSearchResults()
    }
  }

  // MARK: - Navigation

  /// カテゴリタブをタップした際に `ScrollViewProxy` を使って直接スクロールする。
  ///
  /// EmojiKit の `category` binding 経由ではなく、`scrollTo` を直接呼ぶことで
  /// `isInternalChange` ガードや `onChange` 合体の問題を回避する。
  private func scrollToCategory(_ cat: EmojiCategory) {
    withAnimation(.easeInOut(duration: 0.25)) {
      scrollProxy?.scrollTo(cat.id, anchor: .top)
    }
    category = cat
  }

  // MARK: - Search

  private func updateSearchResults() {
    let q = query.trimmingCharacters(in: .whitespaces)
    guard !q.isEmpty else {
      searchCategories = nil
      return
    }

    let matched = keywordSearch.search(query: q, in: Emoji.all)
    if matched.isEmpty {
      searchCategories = []
    } else {
      searchCategories = [
        .custom(id: "search", name: "検索結果", emojis: matched, iconName: "magnifyingglass")
      ]
    }
  }
}

// MARK: - EmojiPickerPanel

/// Emoji ピッカーのフローティングパネル。
///
/// EmojiKit を利用して全カテゴリの絵文字を表示し、
/// 検索・肌の色バリエーション選択をサポートする。
/// 選択された絵文字はクリップボードにコピーされる。
@MainActor
public final class EmojiPickerPanel: NSPanel {

  // MARK: - Callbacks

  /// パネルが閉じた時のコールバック
  public var onDismiss: (() -> Void)?

  // MARK: - Dependencies

  private let keywordSearch = EmojiKeywordSearch()

  // MARK: - Initialization

  public init() {
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 380, height: 480),
      styleMask: [.titled, .closable, .fullSizeContentView],
      backing: .buffered,
      defer: true
    )
    configurePanel()
  }

  // MARK: - Key / Main Overrides

  override public var canBecomeKey: Bool { true }
  override public var canBecomeMain: Bool { false }

  // MARK: - Key Event Handling

  override public func keyDown(with event: NSEvent) {
    if event.keyCode == 53 {  // Escape
      dismissPanel()
      return
    }
    super.keyDown(with: event)
  }

  // MARK: - Show / Dismiss

  /// パネルを表示する。
  ///
  /// - Parameter onSelect: 絵文字が選択された際のコールバック
  public func show(onSelect: @escaping (String) -> Void) {
    let view = EmojiPickerContentView(
      keywordSearch: keywordSearch,
      onSelect: { [weak self] emoji in
        onSelect(emoji)
        self?.dismissPanel()
      }
    )
    // NSVisualEffectView でぼかし背景を設定
    let visualEffect = NSVisualEffectView()
    visualEffect.material = .hudWindow
    visualEffect.blendingMode = .behindWindow
    visualEffect.state = .active
    visualEffect.wantsLayer = true
    visualEffect.layer?.cornerRadius = 12

    let hostingView = SafeHostingView(rootView: view)
    hostingView.translatesAutoresizingMaskIntoConstraints = false
    visualEffect.addSubview(hostingView)
    NSLayoutConstraint.activate([
      hostingView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
      hostingView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
      hostingView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
      hostingView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
    ])

    contentView = visualEffect

    // カーソルがあるスクリーンの中央に配置
    let mouseLocation = NSEvent.mouseLocation
    let screen =
      NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
      ?? NSScreen.main
    let vis = screen?.visibleFrame ?? .zero
    let x = vis.midX - frame.width / 2
    let y = vis.midY - frame.height / 2
    setFrameOrigin(NSPoint(x: x, y: y))

    NSApp.activate(ignoringOtherApps: true)
    makeKeyAndOrderFront(nil)

    // パネルがキーウィンドウになった後に検索欄にフォーカスを当てる
    DispatchQueue.main.async {
      self.focusSearchField()
    }
  }

  /// パネルを非表示にする。
  public func dismissPanel() {
    orderOut(nil)
    onDismiss?()
  }

  // MARK: - Private

  /// ビュー階層から NSTextField を探して first responder にする。
  private func focusSearchField() {
    guard let hostingView = contentView else { return }
    if let textField = findTextField(in: hostingView) {
      makeFirstResponder(textField)
    }
  }

  /// ビュー階層を再帰的に探索し、最初の NSTextField を返す。
  private func findTextField(in view: NSView) -> NSTextField? {
    if let tf = view as? NSTextField, tf.isEditable {
      return tf
    }
    for subview in view.subviews {
      if let found = findTextField(in: subview) {
        return found
      }
    }
    return nil
  }

  private func configurePanel() {
    isFloatingPanel = true
    level = NSWindow.Level(NSWindow.Level.statusBar.rawValue + 1)
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    hidesOnDeactivate = false
    titlebarAppearsTransparent = true
    titleVisibility = .hidden
    isMovableByWindowBackground = true
    backgroundColor = .clear
    isOpaque = false
    title = "Emoji"
  }
}
