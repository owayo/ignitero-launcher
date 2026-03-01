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

// MARK: - Parser

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

  // MARK: - Grammar
  // expression = term (('+' | '-') term)*
  // term       = factor (('*' | '/' | '%') factor)*
  // factor     = '-'? (number | '(' expression ')')

  mutating func parseExpression() -> Double? {
    guard var result = parseTerm() else { return nil }

    while let op = peekOperator(), op == "+" || op == "-" {
      advance()  // consume operator
      guard let right = parseTerm() else { return nil }
      if op == "+" {
        result += right
      } else {
        result -= right
      }
    }
    return result
  }

  private mutating func parseTerm() -> Double? {
    guard var result = parseFactor() else { return nil }

    while let op = peekOperator(), op == "*" || op == "/" || op == "%" {
      advance()  // consume operator
      guard let right = parseFactor() else { return nil }
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

  private mutating func parseFactor() -> Double? {
    skipWhitespace()

    // 単項マイナス
    if peek() == "-" {
      advance()
      guard let value = parseFactor() else { return nil }
      return -value
    }

    // 括弧
    if peek() == "(" {
      advance()  // consume '('
      guard let value = parseExpression() else { return nil }
      skipWhitespace()
      guard peek() == ")" else { return nil }
      advance()  // consume ')'
      return value
    }

    // 数値
    return parseNumber()
  }

  // MARK: - Lexer helpers

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
