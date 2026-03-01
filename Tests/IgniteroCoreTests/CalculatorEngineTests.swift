import Foundation
import Testing

@testable import IgniteroCore

@Suite("CalculatorEngine - Basic Arithmetic")
struct CalculatorEngineBasicTests {
  let engine = CalculatorEngine()

  @Test func addition() {
    #expect(engine.evaluate("1+2") == 3.0)
  }

  @Test func subtraction() {
    #expect(engine.evaluate("10-3") == 7.0)
  }

  @Test func multiplication() {
    #expect(engine.evaluate("4*5") == 20.0)
  }

  @Test func division() {
    let result = engine.evaluate("10/3")
    #expect(result != nil)
    #expect(abs(result! - 3.3333333333333335) < 1e-10)
  }
}

@Suite("CalculatorEngine - Parentheses")
struct CalculatorEngineParenthesesTests {
  let engine = CalculatorEngine()

  @Test func simpleParentheses() {
    #expect(engine.evaluate("(1+2)*3") == 9.0)
  }

  @Test func nestedParentheses() {
    #expect(engine.evaluate("((2+3)*4)") == 20.0)
  }
}

@Suite("CalculatorEngine - Modulo")
struct CalculatorEngineModuloTests {
  let engine = CalculatorEngine()

  @Test func modulo() {
    #expect(engine.evaluate("10%3") == 1.0)
  }
}

@Suite("CalculatorEngine - Operator Precedence")
struct CalculatorEnginePrecedenceTests {
  let engine = CalculatorEngine()

  @Test func multiplicationBeforeAddition() {
    #expect(engine.evaluate("2+3*4") == 14.0)
  }
}

@Suite("CalculatorEngine - Negative Numbers")
struct CalculatorEngineNegativeTests {
  let engine = CalculatorEngine()

  @Test func negativeNumber() {
    #expect(engine.evaluate("-5+3") == -2.0)
  }
}

@Suite("CalculatorEngine - Decimals")
struct CalculatorEngineDecimalTests {
  let engine = CalculatorEngine()

  @Test func decimalAddition() {
    #expect(engine.evaluate("1.5+2.5") == 4.0)
  }
}

@Suite("CalculatorEngine - Error Cases")
struct CalculatorEngineErrorTests {
  let engine = CalculatorEngine()

  @Test func divisionByZero() {
    #expect(engine.evaluate("1/0") == nil)
  }

  @Test func moduloByZero() {
    #expect(engine.evaluate("10%0") == nil)
  }

  @Test func invalidInput() {
    #expect(engine.evaluate("abc") == nil)
  }

  @Test func emptyInput() {
    #expect(engine.evaluate("") == nil)
  }

  @Test func whitespaceOnlyInput() {
    #expect(engine.evaluate("   ") == nil)
  }

  @Test func trailingDecimalPoint() {
    #expect(engine.evaluate("5.") == nil)
  }

  @Test func multipleDecimalPoints() {
    #expect(engine.evaluate("1.2.3") == nil)
  }

  @Test func unmatchedOpenParen() {
    #expect(engine.evaluate("(1+2") == nil)
  }

  @Test func unmatchedCloseParen() {
    #expect(engine.evaluate("1+2)") == nil)
  }

  @Test func trailingOperator() {
    #expect(engine.evaluate("1+") == nil)
  }

  @Test func leadingOperator() {
    #expect(engine.evaluate("+1") == nil)
  }

  @Test func consecutiveOperators() {
    #expect(engine.evaluate("1++2") == nil)
  }

  @Test func onlyDecimalPoint() {
    #expect(engine.evaluate(".") == nil)
  }
}

@Suite("CalculatorEngine - Whitespace Handling")
struct CalculatorEngineWhitespaceTests {
  let engine = CalculatorEngine()

  @Test func spacesAroundOperators() {
    #expect(engine.evaluate("1 + 2") == 3.0)
  }

  @Test func spacesAroundNumbers() {
    #expect(engine.evaluate(" 42 ") == 42.0)
  }

  @Test func spacesInComplexExpression() {
    #expect(engine.evaluate(" ( 1 + 2 ) * 3 ") == 9.0)
  }
}

@Suite("CalculatorEngine - Complex Expressions")
struct CalculatorEngineComplexTests {
  let engine = CalculatorEngine()

  @Test func chainedOperations() {
    #expect(engine.evaluate("1+2+3+4+5") == 15.0)
  }

  @Test func mixedOperators() {
    #expect(engine.evaluate("2*3+4*5") == 26.0)
  }

  @Test func doubleNegative() {
    #expect(engine.evaluate("--5") == 5.0)
  }

  @Test func negativeInParentheses() {
    #expect(engine.evaluate("(-3)*(-4)") == 12.0)
  }

  @Test func singleNumber() {
    #expect(engine.evaluate("42") == 42.0)
  }

  @Test func zeroResult() {
    #expect(engine.evaluate("5-5") == 0.0)
  }
}

@Suite("CalculatorEngine - Format Result")
struct CalculatorEngineFormatTests {
  let engine = CalculatorEngine()

  @Test func formatLargeNumber() {
    let locale = Locale(identifier: "ja_JP")
    let result = engine.formatResult(1_234_567, locale: locale)
    #expect(result == "1,234,567")
  }

  @Test func formatDecimal() {
    let locale = Locale(identifier: "ja_JP")
    let result = engine.formatResult(3.14, locale: locale)
    #expect(result == "3.14")
  }
}
