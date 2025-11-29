import { describe, it, expect } from 'vitest';
import { isCalculatorExpression, evaluateExpression } from './calculator';

describe('Calculator', () => {
  describe('isCalculatorExpression', () => {
    it('should return true for valid expressions', () => {
      expect(isCalculatorExpression('1+2')).toBe(true);
      expect(isCalculatorExpression('10 - 5')).toBe(true);
      expect(isCalculatorExpression('3 * 4')).toBe(true);
      expect(isCalculatorExpression('8 / 2')).toBe(true);
      expect(isCalculatorExpression('10 % 3')).toBe(true);
      expect(isCalculatorExpression('(1+2)*3')).toBe(true);
      expect(isCalculatorExpression('1.5 + 2.5')).toBe(true);
    });

    it('should return false for non-expressions', () => {
      expect(isCalculatorExpression('')).toBe(false);
      expect(isCalculatorExpression('   ')).toBe(false);
      expect(isCalculatorExpression('hello')).toBe(false);
      expect(isCalculatorExpression('42')).toBe(false); // 演算子なし
      expect(isCalculatorExpression('abc + 123')).toBe(false);
    });

    it('should return false for unbalanced parentheses', () => {
      expect(isCalculatorExpression('(1+2')).toBe(false);
      expect(isCalculatorExpression('1+2)')).toBe(false);
      expect(isCalculatorExpression('((1+2)')).toBe(false);
      expect(isCalculatorExpression(')1+2(')).toBe(false);
    });

    it('should return true for balanced parentheses', () => {
      expect(isCalculatorExpression('(1+2)')).toBe(true);
      expect(isCalculatorExpression('((1+2))')).toBe(true);
      expect(isCalculatorExpression('(1+2)*(3+4)')).toBe(true);
    });
  });

  describe('evaluateExpression - Basic Operations', () => {
    it('should evaluate addition', () => {
      const result = evaluateExpression('1+2');
      expect(result).not.toBeNull();
      expect(result!.result).toBe(3);
    });

    it('should evaluate subtraction', () => {
      const result = evaluateExpression('5-3');
      expect(result).not.toBeNull();
      expect(result!.result).toBe(2);
    });

    it('should evaluate multiplication', () => {
      const result = evaluateExpression('4*3');
      expect(result).not.toBeNull();
      expect(result!.result).toBe(12);
    });

    it('should evaluate division', () => {
      const result = evaluateExpression('8/2');
      expect(result).not.toBeNull();
      expect(result!.result).toBe(4);
    });

    it('should evaluate modulo', () => {
      const result = evaluateExpression('10%3');
      expect(result).not.toBeNull();
      expect(result!.result).toBe(1);
    });
  });

  describe('evaluateExpression - Operator Precedence', () => {
    it('should respect multiplication over addition', () => {
      const result = evaluateExpression('1+2*3');
      expect(result).not.toBeNull();
      expect(result!.result).toBe(7); // 1 + (2*3) = 7
    });

    it('should respect division over subtraction', () => {
      const result = evaluateExpression('10-6/2');
      expect(result).not.toBeNull();
      expect(result!.result).toBe(7); // 10 - (6/2) = 7
    });

    it('should handle parentheses', () => {
      const result = evaluateExpression('(1+2)*3');
      expect(result).not.toBeNull();
      expect(result!.result).toBe(9);
    });

    it('should handle nested parentheses', () => {
      const result = evaluateExpression('((2+3)*2)+1');
      expect(result).not.toBeNull();
      expect(result!.result).toBe(11);
    });
  });

  describe('evaluateExpression - Unary Operators', () => {
    it('should handle unary minus', () => {
      const result = evaluateExpression('-5+3');
      expect(result).not.toBeNull();
      expect(result!.result).toBe(-2);
    });

    it('should handle unary plus', () => {
      const result = evaluateExpression('+5+3');
      expect(result).not.toBeNull();
      expect(result!.result).toBe(8);
    });

    it('should handle unary minus in parentheses', () => {
      const result = evaluateExpression('(-5)*2');
      expect(result).not.toBeNull();
      expect(result!.result).toBe(-10);
    });
  });

  describe('evaluateExpression - Decimal Numbers', () => {
    it('should handle decimal numbers', () => {
      const result = evaluateExpression('1.5+2.5');
      expect(result).not.toBeNull();
      expect(result!.result).toBe(4);
    });

    it('should handle decimal in multiplication', () => {
      const result = evaluateExpression('0.1*10');
      expect(result).not.toBeNull();
      expect(result!.result).toBeCloseTo(1);
    });

    it('should reject multiple decimal points', () => {
      const result = evaluateExpression('1.2.3+1');
      expect(result).toBeNull();
    });

    it('should reject trailing decimal point', () => {
      const result = evaluateExpression('1.+2');
      expect(result).toBeNull();
    });
  });

  describe('evaluateExpression - Division and Modulo by Zero', () => {
    it('should return null for division by zero', () => {
      const result = evaluateExpression('5/0');
      expect(result).toBeNull();
    });

    it('should return null for modulo by zero', () => {
      const result = evaluateExpression('5%0');
      expect(result).toBeNull();
    });

    it('should handle zero in numerator', () => {
      const result = evaluateExpression('0/5');
      expect(result).not.toBeNull();
      expect(result!.result).toBe(0);
    });
  });

  describe('evaluateExpression - Whitespace Handling', () => {
    it('should handle spaces between numbers and operators', () => {
      const result = evaluateExpression('1 + 2');
      expect(result).not.toBeNull();
      expect(result!.result).toBe(3);
    });

    it('should handle multiple spaces', () => {
      const result = evaluateExpression('1  +  2');
      expect(result).not.toBeNull();
      expect(result!.result).toBe(3);
    });

    it('should handle leading and trailing spaces', () => {
      const result = evaluateExpression('  1+2  ');
      expect(result).not.toBeNull();
      expect(result!.result).toBe(3);
    });
  });

  describe('evaluateExpression - Complex Expressions', () => {
    it('should evaluate complex expression', () => {
      const result = evaluateExpression('(10+5)*2-8/4');
      expect(result).not.toBeNull();
      expect(result!.result).toBe(28); // (15)*2 - 2 = 30 - 2 = 28
    });

    it('should evaluate chained operations', () => {
      const result = evaluateExpression('1+2+3+4+5');
      expect(result).not.toBeNull();
      expect(result!.result).toBe(15);
    });

    it('should evaluate mixed operations', () => {
      const result = evaluateExpression('2*3+4*5');
      expect(result).not.toBeNull();
      expect(result!.result).toBe(26); // 6 + 20 = 26
    });
  });

  describe('evaluateExpression - Formatting', () => {
    it('should format integer result', () => {
      const result = evaluateExpression('1000+2000');
      expect(result).not.toBeNull();
      expect(result!.formatted).toBe('3,000');
    });

    it('should format decimal result', () => {
      const result = evaluateExpression('10/3');
      expect(result).not.toBeNull();
      expect(result!.result).toBeCloseTo(3.3333333333);
    });
  });

  describe('evaluateExpression - Edge Cases', () => {
    it('should return null for invalid expressions', () => {
      expect(evaluateExpression('hello')).toBeNull();
      expect(evaluateExpression('')).toBeNull();
    });

    it('should return null for incomplete expressions', () => {
      expect(evaluateExpression('1+')).toBeNull();
      expect(evaluateExpression('*2')).toBeNull();
    });

    it('should handle large numbers', () => {
      const result = evaluateExpression('1000000*1000000');
      expect(result).not.toBeNull();
      expect(result!.result).toBe(1000000000000);
    });

    it('should handle very small decimals', () => {
      const result = evaluateExpression('0.001+0.002');
      expect(result).not.toBeNull();
      expect(result!.result).toBeCloseTo(0.003);
    });
  });
});
