import Foundation

/// A small, local-only evaluator for spreadsheet formulas. It never executes code or accesses a network.
public enum SpreadsheetFormula {
    public enum FormulaError: Error, Equatable {
        case divisionByZero
        case invalidReference
        case cycle
        case value

        public var displayText: String {
            switch self {
            case .divisionByZero: return "#DIV/0!"
            case .invalidReference: return "#REF!"
            case .cycle: return "#CYCLE!"
            case .value: return "#VALUE!"
            }
        }
    }

    /// Evaluates one expression against rows, where A1 is row 0, column 0.
    /// Decimal numbers use a dot; comma and semicolon are both argument separators.
    public static func evaluate(_ expression: String, in rows: [[String]]) -> Result<Double, FormulaError> {
        do {
            var parser = try Parser(expression: expression, rows: rows)
            return .success(try parser.evaluate())
        } catch let error as FormulaError {
            return .failure(error)
        } catch {
            return .failure(.value)
        }
    }

    /// Returns the calculated display value for a cell, keeping the supplied rows untouched.
    public static func displayValue(atRow row: Int, column: Int, in rows: [[String]]) -> String {
        guard row >= 0, column >= 0, row < rows.count, column < rows[row].count else {
            return FormulaError.invalidReference.displayText
        }
        let raw = rows[row][column]
        guard raw.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("=") else { return raw }
        switch evaluate(raw, in: rows) {
        case .failure(let error): return error.displayText
        case .success(let value):
            if value.isFinite, value.rounded() == value, abs(value) < 1e15 { return String(Int64(value)) }
            return String(value)
        }
    }
}

private struct Parser {
    private enum Token: Equatable {
        case number(Double), identifier(String), reference(Int, Int), plus, minus, multiply, divide, power
        case leftParen, rightParen, comma, semicolon, colon, end
    }
    private enum Value { case number(Double), range([(Int, Int)]) }

    private let rows: [[String]]
    private let tokens: [Token]
    private let context: EvaluationContext
    private var index = 0
    private var powerDepth = 0
    private var unaryDepth = 0

    init(expression: String, rows: [[String]], context: EvaluationContext = EvaluationContext()) throws {
        guard expression.utf8.count <= 2_000 else { throw SpreadsheetFormula.FormulaError.value }
        self.rows = rows
        self.tokens = try Self.lex(expression)
        self.context = context
    }

    mutating func evaluate() throws -> Double {
        if current == .identifier("=") { advance() }
        let result = try parseExpression()
        guard current == .end, case .number(let number) = result, number.isFinite else { throw SpreadsheetFormula.FormulaError.value }
        return number
    }

    private var current: Token { index < tokens.count ? tokens[index] : .end }
    private mutating func advance() { index += 1 }

    private mutating func parseExpression() throws -> Value {
        var lhs = try parseTerm()
        while current == .plus || current == .minus {
            let op = current; advance()
            let rhs = try parseTerm()
            let a = try scalar(lhs), b = try scalar(rhs)
            lhs = .number(op == .plus ? a + b : a - b)
        }
        return lhs
    }

    private mutating func parseTerm() throws -> Value {
        var lhs = try parsePower()
        while current == .multiply || current == .divide {
            let op = current; advance()
            let rhs = try parsePower()
            let a = try scalar(lhs), b = try scalar(rhs)
            if op == .divide && b == 0 { throw SpreadsheetFormula.FormulaError.divisionByZero }
            lhs = .number(op == .multiply ? a * b : a / b)
        }
        return lhs
    }

    private mutating func parsePower() throws -> Value {
        guard powerDepth < 128 else { throw SpreadsheetFormula.FormulaError.value }
        powerDepth += 1
        defer { powerDepth -= 1 }
        var lhs = try parseUnary()
        if current == .power {
            advance()
            let rhs = try parsePower()
            lhs = .number(pow(try scalar(lhs), try scalar(rhs)))
        }
        return lhs
    }

    private mutating func parseUnary() throws -> Value {
        guard unaryDepth < 128 else { throw SpreadsheetFormula.FormulaError.value }
        unaryDepth += 1
        defer { unaryDepth -= 1 }
        if current == .plus { advance(); return .number(try scalar(parseUnary())) }
        if current == .minus { advance(); return .number(-(try scalar(parseUnary()))) }
        return try parsePrimary()
    }

    private mutating func parsePrimary() throws -> Value {
        switch current {
        case .number(let n): advance(); return .number(n)
        case .reference(let row, let col):
            advance()
            if current == .colon {
                advance()
                guard case .reference(let endRow, let endCol) = current else { throw SpreadsheetFormula.FormulaError.value }
                advance()
                let r0 = min(row, endRow), r1 = max(row, endRow), c0 = min(col, endCol), c1 = max(col, endCol)
                let height = r1 - r0 + 1
                let width = c1 - c0 + 1
                guard height <= 10_000, width <= 10_000, height <= 10_000 / width else { throw SpreadsheetFormula.FormulaError.invalidReference }
                return .range((r0...r1).flatMap { r in (c0...c1).map { (r, $0) } })
            }
            return .number(try cellValue(row: row, column: col))
        case .identifier(let name):
            advance()
            guard current == .leftParen else { throw SpreadsheetFormula.FormulaError.value }
            advance()
            var args: [Value] = []
            if current != .rightParen {
                args.append(try parseExpression())
                while current == .comma || current == .semicolon {
                    advance(); args.append(try parseExpression())
                }
            }
            guard current == .rightParen else { throw SpreadsheetFormula.FormulaError.value }
            advance()
            return .number(try aggregate(name: name.uppercased(), args: args))
        case .leftParen:
            advance()
            let value = try parseExpression()
            guard current == .rightParen else { throw SpreadsheetFormula.FormulaError.value }
            advance(); return value
        default: throw SpreadsheetFormula.FormulaError.value
        }
    }

    private func scalar(_ value: Value) throws -> Double {
        guard case .number(let number) = value else { throw SpreadsheetFormula.FormulaError.value }
        return number
    }

    private mutating func cellValue(row: Int, column: Int) throws -> Double {
        guard row >= 0, column >= 0, row < rows.count, column < rows[row].count else { throw SpreadsheetFormula.FormulaError.invalidReference }
        let key = "\(row):\(column)"
        guard !context.resolving.contains(key) else { throw SpreadsheetFormula.FormulaError.cycle }
        if let cached = context.cellCache[key] { return cached }
        guard context.remainingCellEvaluations > 0 else { throw SpreadsheetFormula.FormulaError.value }
        context.remainingCellEvaluations -= 1
        let raw = rows[row][column].trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { context.cellCache[key] = 0; return 0 }
        if raw.hasPrefix("=") {
            guard context.resolving.count < 128 else { throw SpreadsheetFormula.FormulaError.value }
            context.resolving.insert(key); defer { context.resolving.remove(key) }
            var nested = try Parser(expression: raw, rows: rows, context: context)
            let result = try nested.evaluate()
            context.cellCache[key] = result
            return result
        }
        guard let value = Double(raw), value.isFinite else { throw SpreadsheetFormula.FormulaError.value }
        context.cellCache[key] = value
        return value
    }

    private mutating func aggregate(name: String, args: [Value]) throws -> Double {
        let supported = ["SUM", "SUMME", "AVERAGE", "MITTELWERT", "MIN", "MAX", "COUNT", "ANZAHL"]
        guard supported.contains(name), !args.isEmpty else { throw SpreadsheetFormula.FormulaError.value }
        var values: [Double] = []
        for arg in args {
            switch arg {
            case .number(let number): values.append(number)
            case .range(let refs):
                for (row, col) in refs {
                    guard row < rows.count, col < rows[row].count else { throw SpreadsheetFormula.FormulaError.invalidReference }
                    let text = rows[row][col].trimmingCharacters(in: .whitespacesAndNewlines)
                    if text.isEmpty { continue }
                    if let number = Double(text), number.isFinite {
                        values.append(number)
                    } else if text.hasPrefix("=") {
                        values.append(try cellValue(row: row, column: col))
                    }
                }
            }
        }
        switch name {
        case "SUM", "SUMME": return values.reduce(0, +)
        case "AVERAGE", "MITTELWERT":
            guard !values.isEmpty else { throw SpreadsheetFormula.FormulaError.divisionByZero }
            return values.reduce(0, +) / Double(values.count)
        case "MIN": return values.min() ?? 0
        case "MAX": return values.max() ?? 0
        case "COUNT", "ANZAHL": return Double(values.count)
        default: throw SpreadsheetFormula.FormulaError.value
        }
    }

    private static func lex(_ source: String) throws -> [Token] {
        var chars = Array(source.trimmingCharacters(in: .whitespacesAndNewlines))
        if chars.first == "=" { chars.removeFirst() }
        var i = 0, result: [Token] = [], nesting = 0
        while i < chars.count {
            let ch = chars[i]
            if ch.isWhitespace { i += 1; continue }
            switch ch {
            case "+": result.append(.plus); i += 1
            case "-": result.append(.minus); i += 1
            case "*": result.append(.multiply); i += 1
            case "/": result.append(.divide); i += 1
            case "^": result.append(.power); i += 1
            case "(":
                nesting += 1
                guard nesting <= 128 else { throw SpreadsheetFormula.FormulaError.value }
                result.append(.leftParen); i += 1
            case ")": nesting = max(0, nesting - 1); result.append(.rightParen); i += 1
            case ",": result.append(.comma); i += 1
            case ";": result.append(.semicolon); i += 1
            case ":": result.append(.colon); i += 1
            default:
                if ch.isNumber || ch == "." {
                    let start = i; var dots = 0
                    while i < chars.count && (chars[i].isNumber || chars[i] == ".") { if chars[i] == "." { dots += 1 }; i += 1 }
                    guard dots <= 1, let value = Double(String(chars[start..<i])) else { throw SpreadsheetFormula.FormulaError.value }
                    result.append(.number(value)); continue
                }
                if ch == "$" || ch.isLetter {
                    let start = i
                    if chars[i] == "$" { i += 1 }
                    while i < chars.count && chars[i].isLetter { i += 1 }
                    let lettersEnd = i
                    if i < chars.count && chars[i] == "$" { i += 1 }
                    let digitStart = i
                    while i < chars.count && chars[i].isNumber { i += 1 }
                    if digitStart < i && lettersEnd > start {
                        let letters = String(chars[start..<lettersEnd]).replacingOccurrences(of: "$", with: "").uppercased()
                        var col = 0
                        for letter in letters.unicodeScalars {
                            guard let value = letter.value >= 65 && letter.value <= 90 ? Int(letter.value - 64) : nil else { throw SpreadsheetFormula.FormulaError.value }
                            guard col <= (16_384 - value) / 26 else { throw SpreadsheetFormula.FormulaError.invalidReference }
                            col = col * 26 + value
                        }
                        let digits = String(chars[digitStart..<i])
                        guard let rowNumber = Int(digits), rowNumber > 0, col > 0 else { throw SpreadsheetFormula.FormulaError.invalidReference }
                        result.append(.reference(rowNumber - 1, col - 1)); continue
                    }
                    if digitStart == i {
                        let word = String(chars[start..<i]).replacingOccurrences(of: "$", with: "")
                        result.append(.identifier(word.uppercased())); continue
                    }
                    throw SpreadsheetFormula.FormulaError.value
                }
                throw SpreadsheetFormula.FormulaError.value
            }
        }
        result.append(.end)
        return result
    }
}

/// Shared by nested formula parsers so repeated references reuse computed values and work stays bounded.
private final class EvaluationContext {
    var resolving: Set<String> = []
    var cellCache: [String: Double] = [:]
    var remainingCellEvaluations = 100_000
}
