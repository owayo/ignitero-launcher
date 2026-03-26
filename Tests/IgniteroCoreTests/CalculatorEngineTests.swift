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

// MARK: - 浮動小数点の境界値

@Suite("CalculatorEngine - Floating Point Edge Cases")
struct CalculatorEngineFloatingPointTests {
  let engine = CalculatorEngine()

  @Test func veryLargeNumberReturnsNil() {
    // 1e308 * 10 = Infinity → isFinite チェックで nil
    #expect(
      engine.evaluate(
        "9999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999*9999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999"
      ) == nil)
  }

  @Test func negativeModulo() {
    let result = engine.evaluate("-10%3")
    #expect(result != nil)
    #expect(abs(result! - (-1.0)) < 1e-10)
  }

  @Test func zeroTimesAnything() {
    #expect(engine.evaluate("0*99999") == 0.0)
  }

  @Test func zeroResult() {
    #expect(engine.evaluate("0/1") == 0.0)
  }
}

// MARK: - 深いネスト括弧

@Suite("CalculatorEngine - Deep Nesting")
struct CalculatorEngineDeepNestingTests {
  let engine = CalculatorEngine()

  @Test func tenLevelNesting() {
    // ((((((((((1+1))))))))))
    #expect(engine.evaluate("((((((((((1+1))))))))))") == 2.0)
  }

  @Test func emptyParentheses() {
    // () は数値でも式でもないため nil
    #expect(engine.evaluate("()") == nil)
  }

  @Test func nestedSubtraction() {
    #expect(engine.evaluate("(10-(3-(2-1)))") == 8.0)
  }
}

// MARK: - 連続演算子と特殊パターン

@Suite("CalculatorEngine - Special Patterns")
struct CalculatorEngineSpecialPatternTests {
  let engine = CalculatorEngine()

  @Test func leadingZeros() {
    // "01" は Double("01") = 1.0 として解釈される
    #expect(engine.evaluate("01+02") == 3.0)
  }

  @Test func multipleOperationsWithParens() {
    #expect(engine.evaluate("(2+3)*(4-1)/(5%3)") == 7.5)
  }

  @Test func subtractNegative() {
    // 5 - (-3) = 8
    #expect(engine.evaluate("5-(-3)") == 8.0)
  }

  @Test func tripleNegative() {
    // ---5 = -(-((-5))) = -5
    #expect(engine.evaluate("---5") == -5.0)
  }

  @Test func decimalOnlyOperands() {
    #expect(engine.evaluate("0.1+0.2") != nil)
    let result = engine.evaluate("0.1+0.2")!
    #expect(abs(result - 0.3) < 1e-10)
  }
}

// MARK: - NaN / Infinity 検出

@Suite("CalculatorEngine - NaN and Infinity Detection")
struct CalculatorEngineNaNInfinityTests {
  let engine = CalculatorEngine()

  @Test("0/0 は nil を返す（NaN 検出）")
  func zeroDivZeroReturnsNil() {
    #expect(engine.evaluate("0/0") == nil)
  }

  @Test("非常に大きい数同士の乗算は nil を返す（Infinity 検出）")
  func overflowReturnsNil() {
    // Double.greatestFiniteMagnitude を超える結果は Infinity → isFinite チェックで nil
    let big = String(repeating: "9", count: 309)
    #expect(engine.evaluate("\(big)*\(big)") == nil)
  }

  @Test("0 除算は nil を返す（負の被除数）")
  func negativeDivByZero() {
    #expect(engine.evaluate("-1/0") == nil)
  }

  @Test("極めて小さい正の数")
  func verySmallPositive() {
    let result = engine.evaluate("0.00000001/100000")
    #expect(result != nil)
    if let r = result {
      #expect(r > 0)
      #expect(r.isFinite)
    }
  }
}

// MARK: - 括弧のミスマッチ詳細

@Suite("CalculatorEngine - Parenthesis Mismatch Details")
struct CalculatorEngineParenthesisMismatchTests {
  let engine = CalculatorEngine()

  @Test("複数レベルの括弧不整合（左が多い）")
  func multiLevelUnmatchedOpen() {
    #expect(engine.evaluate("(((1+2)") == nil)
  }

  @Test("複数レベルの括弧不整合（右が多い）")
  func multiLevelUnmatchedClose() {
    #expect(engine.evaluate("(1+2)))") == nil)
  }

  @Test("空括弧を含む式")
  func emptyParenInExpression() {
    #expect(engine.evaluate("() + 5") == nil)
  }

  @Test("入れ子で内側が空")
  func nestedEmptyParen() {
    #expect(engine.evaluate("(1 + ())") == nil)
  }

  @Test("括弧のみ（空でない）は値を返す")
  func parenOnlyWithValue() {
    #expect(engine.evaluate("(42)") == 42.0)
  }
}

// MARK: - 数値フォーマットの境界値

@Suite("CalculatorEngine - Number Format Boundaries")
struct CalculatorEngineNumberFormatBoundaryTests {
  let engine = CalculatorEngine()

  @Test("先頭ゼロ複数")
  func multipleLeadingZeros() {
    #expect(engine.evaluate("00001 + 00002") == 3.0)
  }

  @Test("小数点直後に何もない場合は nil")
  func trailingDecimalInExpression() {
    #expect(engine.evaluate("1. + 2") == nil)
  }

  @Test("1.2.3 は無効")
  func multipleDecimalPointsInNumber() {
    #expect(engine.evaluate("1.2.3") == nil)
  }

  @Test("1.5 + 2.3 は有効")
  func twoDecimalNumbers() {
    #expect(engine.evaluate("1.5 + 2.3") == 3.8)
  }

  @Test("非常に長い数値文字列（Infinity 検出）")
  func extremelyLongNumber() {
    let longNum = String(repeating: "9", count: 500)
    #expect(engine.evaluate(longNum) == nil)
  }
}
