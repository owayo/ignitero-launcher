/**
 * 安全な計算式評価モジュール
 * 四則演算（+, -, *, /）と括弧をサポート
 */

// 計算式として有効かどうかを判定
export function isCalculatorExpression(input: string): boolean {
  const trimmed = input.trim();
  if (!trimmed) return false;

  // 数字、演算子、括弧、小数点、スペースのみで構成されているかチェック
  const validPattern = /^[\d+\-*/().%\s]+$/;
  if (!validPattern.test(trimmed)) return false;

  // 最低限1つの演算子が含まれている必要がある
  const hasOperator = /[+\-*/%]/.test(trimmed);
  if (!hasOperator) return false;

  // 最低限1つの数字が含まれている必要がある
  const hasNumber = /\d/.test(trimmed);
  if (!hasNumber) return false;

  // 括弧の対応をチェック
  let parenCount = 0;
  for (const char of trimmed) {
    if (char === '(') parenCount++;
    if (char === ')') parenCount--;
    // 閉じ括弧が多すぎる場合は即座にfalse
    if (parenCount < 0) return false;
  }
  // 開き括弧が閉じられていない場合もfalse
  if (parenCount !== 0) return false;

  return true;
}

// トークンの種類
type TokenType =
  | 'NUMBER'
  | 'PLUS'
  | 'MINUS'
  | 'MULTIPLY'
  | 'DIVIDE'
  | 'MODULO'
  | 'LPAREN'
  | 'RPAREN'
  | 'EOF';

interface Token {
  type: TokenType;
  value: number | null;
}

// レクサー（字句解析器）
class Lexer {
  private pos = 0;
  private currentChar: string | null;

  constructor(private text: string) {
    this.currentChar = text.length > 0 ? text[0] : null;
  }

  private advance(): void {
    this.pos++;
    this.currentChar = this.pos < this.text.length ? this.text[this.pos] : null;
  }

  private skipWhitespace(): void {
    while (this.currentChar !== null && /\s/.test(this.currentChar)) {
      this.advance();
    }
  }

  private readNumber(): number {
    let result = '';
    let hasDecimalPoint = false;

    while (this.currentChar !== null && /[\d.]/.test(this.currentChar)) {
      if (this.currentChar === '.') {
        // 複数の小数点を検出したらエラー
        if (hasDecimalPoint) {
          throw new Error('Invalid number: multiple decimal points');
        }
        hasDecimalPoint = true;
      }
      result += this.currentChar;
      this.advance();
    }

    // 小数点のみや末尾が小数点の場合をチェック
    if (result === '.' || result.endsWith('.')) {
      throw new Error('Invalid number format');
    }

    const num = parseFloat(result);
    if (isNaN(num)) {
      throw new Error('Invalid number');
    }

    return num;
  }

  getNextToken(): Token {
    while (this.currentChar !== null) {
      if (/\s/.test(this.currentChar)) {
        this.skipWhitespace();
        continue;
      }

      if (/[\d.]/.test(this.currentChar)) {
        return { type: 'NUMBER', value: this.readNumber() };
      }

      if (this.currentChar === '+') {
        this.advance();
        return { type: 'PLUS', value: null };
      }

      if (this.currentChar === '-') {
        this.advance();
        return { type: 'MINUS', value: null };
      }

      if (this.currentChar === '*') {
        this.advance();
        return { type: 'MULTIPLY', value: null };
      }

      if (this.currentChar === '/') {
        this.advance();
        return { type: 'DIVIDE', value: null };
      }

      if (this.currentChar === '%') {
        this.advance();
        return { type: 'MODULO', value: null };
      }

      if (this.currentChar === '(') {
        this.advance();
        return { type: 'LPAREN', value: null };
      }

      if (this.currentChar === ')') {
        this.advance();
        return { type: 'RPAREN', value: null };
      }

      throw new Error(`Invalid character: ${this.currentChar}`);
    }

    return { type: 'EOF', value: null };
  }
}

// パーサー（構文解析器）- 再帰下降パーサー
class Parser {
  private currentToken: Token;
  private lexer: Lexer;

  constructor(text: string) {
    this.lexer = new Lexer(text);
    this.currentToken = this.lexer.getNextToken();
  }

  private eat(tokenType: TokenType): void {
    if (this.currentToken.type === tokenType) {
      this.currentToken = this.lexer.getNextToken();
    } else {
      throw new Error(`Expected ${tokenType}, got ${this.currentToken.type}`);
    }
  }

  // factor : NUMBER | LPAREN expr RPAREN | (PLUS | MINUS) factor
  private factor(): number {
    const token = this.currentToken;

    if (token.type === 'NUMBER') {
      this.eat('NUMBER');
      return token.value!;
    }

    if (token.type === 'LPAREN') {
      this.eat('LPAREN');
      const result = this.expr();
      this.eat('RPAREN');
      return result;
    }

    // 単項マイナス/プラス
    if (token.type === 'MINUS') {
      this.eat('MINUS');
      return -this.factor();
    }

    if (token.type === 'PLUS') {
      this.eat('PLUS');
      return this.factor();
    }

    throw new Error(`Unexpected token: ${token.type}`);
  }

  // term : factor ((MULTIPLY | DIVIDE | MODULO) factor)*
  private term(): number {
    let result = this.factor();

    while (['MULTIPLY', 'DIVIDE', 'MODULO'].includes(this.currentToken.type)) {
      const token = this.currentToken;
      if (token.type === 'MULTIPLY') {
        this.eat('MULTIPLY');
        result *= this.factor();
      } else if (token.type === 'DIVIDE') {
        this.eat('DIVIDE');
        const divisor = this.factor();
        if (divisor === 0) {
          throw new Error('Division by zero');
        }
        result /= divisor;
      } else if (token.type === 'MODULO') {
        this.eat('MODULO');
        const divisor = this.factor();
        if (divisor === 0) {
          throw new Error('Modulo by zero');
        }
        result %= divisor;
      }
    }

    return result;
  }

  // expr : term ((PLUS | MINUS) term)*
  private expr(): number {
    let result = this.term();

    while (['PLUS', 'MINUS'].includes(this.currentToken.type)) {
      const token = this.currentToken;
      if (token.type === 'PLUS') {
        this.eat('PLUS');
        result += this.term();
      } else if (token.type === 'MINUS') {
        this.eat('MINUS');
        result -= this.term();
      }
    }

    return result;
  }

  parse(): number {
    const result = this.expr();
    if (this.currentToken.type !== 'EOF') {
      throw new Error('Unexpected token at end of expression');
    }
    return result;
  }
}

// 計算式を評価して結果を返す
export function evaluateExpression(
  input: string,
): { result: number; formatted: string } | null {
  if (!isCalculatorExpression(input)) {
    return null;
  }

  try {
    const parser = new Parser(input.trim());
    const result = parser.parse();

    // 結果が有限の数値かチェック
    if (!Number.isFinite(result)) {
      return null;
    }

    // 結果をフォーマット（小数点以下の無駄なゼロを削除）
    const formatted = Number.isInteger(result)
      ? result.toLocaleString('ja-JP')
      : result.toLocaleString('ja-JP', {
          minimumFractionDigits: 0,
          maximumFractionDigits: 10,
        });

    return { result, formatted };
  } catch {
    return null;
  }
}
