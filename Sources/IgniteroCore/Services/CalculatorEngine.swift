import Foundation

/// 算術式を評価する再帰下降パーサーベースの計算機エンジン
public struct CalculatorEngine: Sendable {
  public init() {}

  /// 算術式を評価して結果を返す。不正な式やゼロ除算の場合は nil を返す。
  public func evaluate(_ expression: String) -> Double? {
    let trimmed = expression.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return nil }

    var parser = Parser(trimmed)
    guard let result = parser.parseExpression() else { return nil }
    // 全入力を消費したか確認
    guard parser.isAtEnd else { return nil }
    guard result.isFinite else { return nil }
    return result
  }

  /// 計算結果を指定ロケールでフォーマットする
  public func formatResult(_ value: Double, locale: Locale) -> String {
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 10
    formatter.minimumFractionDigits = 0
    return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
  }
}

// MARK: - パーサー

private struct Parser {
  private let characters: [Character]
  private var position: Int

  init(_ input: String) {
    self.characters = Array(input)
    self.position = 0
  }

  var isAtEnd: Bool {
    var pos = position
    while pos < characters.count, characters[pos].isWhitespace {
      pos += 1
    }
    return pos >= characters.count
  }

  // MARK: - 文法
  // 文法: expression = term (('+' | '-') term)*
  // 文法: term = factor (('*' | '/' | '%') factor)*
  // 文法: factor = '-'? (number | '(' expression ')')

  /// 括弧のネスト深さの上限。
  ///
  /// 括弧付き式は再帰下降でパースするため、`(((…` のように極端に深くネストした入力
  /// （検索欄への大量貼り付け等）はスタックオーバーフローを起こし、アプリ全体が SIGSEGV で
  /// クラッシュする。正当な計算式がこの深さを超えることはないため、上限を超えたら無効な式として
  /// nil を返す（`+`/`*`/単項マイナスをループ化してスタック消費を抑えているのと同じ方針）。
  private static let maxParenDepth = 128

  mutating func parseExpression(depth: Int = 0) -> Double? {
    guard var result = parseTerm(depth: depth) else { return nil }

    while let op = peekOperator(), op == "+" || op == "-" {
      advance()  // 演算子を消費
      guard let right = parseTerm(depth: depth) else { return nil }
      if op == "+" {
        result += right
      } else {
        result -= right
      }
    }
    return result
  }

  private mutating func parseTerm(depth: Int) -> Double? {
    guard var result = parseFactor(depth: depth) else { return nil }

    while let op = peekOperator(), op == "*" || op == "/" || op == "%" {
      advance()  // 演算子を消費
      guard let right = parseFactor(depth: depth) else { return nil }
      if op == "*" {
        result *= right
      } else if op == "/" {
        if right == 0 { return nil }
        result /= right
      } else {
        if right == 0 { return nil }
        result = result.truncatingRemainder(dividingBy: right)
      }
    }
    return result
  }

  private mutating func parseFactor(depth: Int) -> Double? {
    skipWhitespace()

    // 単項マイナスは連続しても再帰させずループで処理（長い `---...` 入力でもスタック消費を O(1) に抑える）
    var negate = false
    while peek() == "-" {
      negate.toggle()
      advance()
      skipWhitespace()
    }

    let value: Double?
    // 括弧
    if peek() == "(" {
      // 括弧は再帰下降でパースするため、深いネストはスタックオーバーフローになる。
      // 正当な式では到達し得ない深さに達したら無効な式として nil を返す。
      guard depth < Self.maxParenDepth else { return nil }
      advance()  // '(' を消費
      guard let inner = parseExpression(depth: depth + 1) else { return nil }
      skipWhitespace()
      guard peek() == ")" else { return nil }
      advance()  // ')' を消費
      value = inner
    } else {
      // 数値
      value = parseNumber()
    }

    guard let v = value else { return nil }
    return negate ? -v : v
  }

  // MARK: - 字句解析ヘルパー

  private mutating func parseNumber() -> Double? {
    skipWhitespace()
    guard position < characters.count else { return nil }

    var numStr = ""
    var hasDecimalPoint = false

    while position < characters.count {
      let ch = characters[position]
      if ch.isNumber {
        numStr.append(ch)
        position += 1
      } else if ch == "." {
        if hasDecimalPoint { return nil }  // 複数の小数点
        hasDecimalPoint = true
        numStr.append(ch)
        position += 1
      } else {
        break
      }
    }

    guard !numStr.isEmpty else { return nil }
    guard numStr != "." else { return nil }
    guard !numStr.hasSuffix(".") else { return nil }

    return Double(numStr)
  }

  private func peek() -> Character? {
    var pos = position
    while pos < characters.count, characters[pos].isWhitespace {
      pos += 1
    }
    guard pos < characters.count else { return nil }
    return characters[pos]
  }

  private func peekOperator() -> Character? {
    var pos = position
    while pos < characters.count, characters[pos].isWhitespace {
      pos += 1
    }
    guard pos < characters.count else { return nil }
    let ch = characters[pos]
    if ch == "+" || ch == "-" || ch == "*" || ch == "/" || ch == "%" {
      return ch
    }
    return nil
  }

  @discardableResult
  private mutating func advance() -> Character? {
    skipWhitespace()
    guard position < characters.count else { return nil }
    let ch = characters[position]
    position += 1
    return ch
  }

  private mutating func skipWhitespace() {
    while position < characters.count, characters[position].isWhitespace {
      position += 1
    }
  }
}
