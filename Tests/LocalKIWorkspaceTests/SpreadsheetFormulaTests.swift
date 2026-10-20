import XCTest
@testable import Lokal_KI_Workspace

final class SpreadsheetFormulaTests: XCTestCase {
    private func value(_ expression: String, rows: [[String]] = []) -> Double? {
        try? SpreadsheetFormula.evaluate(expression, in: rows).get()
    }

    func testArithmeticPrecedenceParenthesesAndExponent() {
        XCTAssertEqual(value("=2+3*4"), 14)
        XCTAssertEqual(value("=(2+3)*4"), 20)
        XCTAssertEqual(value("=2^3^2"), 512)
    }

    func testReferencesAbsoluteReferencesAndAggregates() {
        let rows = [["2", "3"], ["4", "=A1+$B$1"], ["6", "text"]]
        XCTAssertEqual(value("=A2+B2", rows: rows), 9)
        XCTAssertEqual(value("=SUM(A1:A3)", rows: rows), 12)
        XCTAssertEqual(value("=SUMME(A1;B1)", rows: rows), 5)
        XCTAssertEqual(value("=AVERAGE(A1:A3)", rows: rows), 4)
        XCTAssertEqual(value("=MITTELWERT(A1:A3)", rows: rows), 4)
        XCTAssertEqual(value("=MIN(A1:B2)", rows: rows), 2)
        XCTAssertEqual(value("=MAX(A1:B2)", rows: rows), 5)
        XCTAssertEqual(value("=ANZAHL(A1:B3)", rows: rows), 5)
    }

    func testDisplayValueKeepsRawCellUnchangedAndShowsExcelLikeErrors() {
        let rows = [["7", "=A1*3", "=1/0"]]
        XCTAssertEqual(SpreadsheetFormula.displayValue(atRow: 0, column: 1, in: rows), "21")
        XCTAssertEqual(SpreadsheetFormula.displayValue(atRow: 0, column: 2, in: rows), "#DIV/0!")
        XCTAssertEqual(rows[0][1], "=A1*3")
    }

    func testCyclesInvalidReferencesAndInvalidExpressions() {
        let rows = [["=B1", "=A1"]]
        XCTAssertEqual(SpreadsheetFormula.displayValue(atRow: 0, column: 0, in: rows), "#CYCLE!")
        XCTAssertEqual(SpreadsheetFormula.evaluate("=Z99", in: [["1"]]), .failure(.invalidReference))
        XCTAssertEqual(SpreadsheetFormula.evaluate("=1/0", in: []), .failure(.divisionByZero))
        XCTAssertEqual(SpreadsheetFormula.evaluate("=1+oops", in: []), .failure(.value))
        XCTAssertEqual(SpreadsheetFormula.evaluate("=A1", in: [["word"]]), .failure(.value))
    }

    func testRangesIgnoreTextButPropagateFormulaErrors() {
        let rows = [["Umsatz", "2"], ["3", "Notiz"], ["=1/0", "4"]]
        XCTAssertEqual(value("=SUM(A1:B3)", rows: rows), nil)
        XCTAssertEqual(value("=SUM(A1:B2)", rows: rows), 5)
        XCTAssertEqual(value("=COUNT(A1:B2)", rows: [["Titel", "2"], ["Text", "4"]]), 2)
        XCTAssertEqual(SpreadsheetFormula.evaluate("=SUM(A1:A3)", in: rows), .failure(.divisionByZero))
    }

    func testParserLimitsLargeRangesColumnsAndNonFiniteResults() {
        XCTAssertEqual(SpreadsheetFormula.evaluate("=" + String(repeating: "1", count: 2_001), in: []), .failure(.value))
        XCTAssertEqual(SpreadsheetFormula.evaluate("=" + String(repeating: "(", count: 129) + "1" + String(repeating: ")", count: 129), in: []), .failure(.value))
        XCTAssertEqual(SpreadsheetFormula.evaluate("=1" + String(repeating: "^1", count: 129), in: []), .failure(.value))
        XCTAssertEqual(SpreadsheetFormula.evaluate("=" + String(repeating: "-", count: 129) + "1", in: []), .failure(.value))
        XCTAssertEqual(SpreadsheetFormula.evaluate("=A1:A10001", in: [["1"]]), .failure(.invalidReference))
        XCTAssertEqual(SpreadsheetFormula.evaluate("=ZZZZZZZZZZZZZZZZZZZZ1", in: [["1"]]), .failure(.invalidReference))
        let huge = String(repeating: "9", count: 308)
        XCTAssertEqual(SpreadsheetFormula.evaluate("=\(huge)*\(huge)", in: []), .failure(.value))
    }

    func testRepeatedReferenceChainUsesBoundedWork() {
        var rows = [["1"]]
        for row in 2...50 {
            let previous = row - 1
            rows.append(["=A\(previous)+A\(previous)"])
        }
        XCTAssertEqual(value("=A50", rows: rows), 562_949_953_421_312)
    }
}
