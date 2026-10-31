import AppKit
import SwiftUI

struct SheetCell: Equatable { var row: Int; var column: Int }

enum SpreadsheetData {
    static func columnName(_ index: Int) -> String {
        var value = index + 1
        var result = ""
        while value > 0 { value -= 1; result = String(UnicodeScalar(65 + value % 26)!) + result; value /= 26 }
        return result
    }
    static func pasting(_ text: String, into source: [[String]], at cell: SheetCell) -> [[String]] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        var values = lines.map { $0.components(separatedBy: "\t") }
        if values.last == [""] { values.removeLast() }
        guard !values.isEmpty, values.count * (values.map(\.count).max() ?? 1) <= 10_000 else { return source }
        var rows = source
        let width = max(rows.map(\.count).max() ?? 0, cell.column + (values.map(\.count).max() ?? 1))
        while rows.count < cell.row + values.count { rows.append(Array(repeating: "", count: width)) }
        for index in rows.indices { while rows[index].count < width { rows[index].append("") } }
        for row in values.indices { for column in values[row].indices { rows[cell.row + row][cell.column + column] = values[row][column] } }
        return rows
    }
}

struct SpreadsheetEditor: View {
    @Binding var project: WorkspaceProject
    @State private var selected: SheetCell?
    private var columns: Int { max(1, project.tableRows.map(\.count).max() ?? 1) }
    private var formulaSummary: String {
        let cellCount = project.tableRows.reduce(0) { $0 + $1.count }
        guard cellCount <= 100_000 else { return "Summe nicht berechnet · über 100.000 Zellen" }
        var sum = 0.0
        var numericCount = 0
        var errorCount = 0
        for row in project.tableRows {
            for raw in row {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                if trimmed.hasPrefix("=") {
                    switch SpreadsheetFormula.evaluate(trimmed, in: project.tableRows) {
                    case .success(let value): sum += value; numericCount += 1
                    case .failure: errorCount += 1
                    }
                } else if let value = Double(trimmed), value.isFinite {
                    sum += value; numericCount += 1
                }
            }
        }
        let sumText = numericCount == 0 ? "—" : (sum.isFinite ? String(sum) : "Überlauf")
        var parts = ["Summe: \(sumText)", "\(numericCount) Zahlen"]
        if errorCount > 0 { parts.append("\(errorCount) Fehler") }
        return parts.joined(separator: " · ")
    }
    private var cellValue: Binding<String> {
        Binding(get: {
            guard let cell = selected, project.tableRows.indices.contains(cell.row), project.tableRows[cell.row].indices.contains(cell.column) else { return "" }
            return project.tableRows[cell.row][cell.column]
        }, set: { value in
            guard let cell = selected, project.tableRows.indices.contains(cell.row) else { return }
            while project.tableRows[cell.row].count <= cell.column { project.tableRows[cell.row].append("") }
            project.tableRows[cell.row][cell.column] = value
        })
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(selected.map { "\(SpreadsheetData.columnName($0.column))\($0.row + 1)" } ?? "—")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).frame(width: 42)
                Divider().frame(height: 17)
                TextField("Zelle auswählen", text: cellValue).textFieldStyle(.plain)
                    .disabled(selected == nil).accessibilityLabel("Zellinhalt")
                Spacer(minLength: 8)
                Button { project.tableRows.append(Array(repeating: "", count: columns)) } label: { Label("Zeile hinzufügen", systemImage: "plus") }
                    .help("Zeile hinzufügen")
                Button {
                    for index in project.tableRows.indices { project.tableRows[index].append("") }
                    if project.tableRows.isEmpty { project.tableRows = [[""]] }
                } label: { Label("Spalte hinzufügen", systemImage: "plus") }
                    .help("Spalte hinzufügen")
                Menu {
                    if let selected {
                        Button("Ausgewählte Zeile entfernen", role: .destructive) {
                            guard selected.row > 0, project.tableRows.indices.contains(selected.row) else { return }
                            project.tableRows.remove(at: selected.row); self.selected = nil
                        }.disabled(selected.row == 0)
                    }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                    .accessibilityLabel("Tabellenaktionen")
            }
            .font(.system(size: 12)).buttonStyle(.borderless).padding(.horizontal, 14).frame(height: 42)
            .background(Color(nsColor: .controlBackgroundColor))
            Divider()
            NativeSpreadsheet(rows: $project.tableRows, selected: $selected)
                .overlay(alignment: .bottomLeading) {
                    if project.tableRows.count <= 1 {
                        Button("Erste Zeile hinzufügen") { project.tableRows.append(Array(repeating: "", count: columns)) }
                            .buttonStyle(.plain).foregroundStyle(.secondary).font(.system(size: 12))
                            .padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6)).padding(18)
                    }
                }
            Divider()
            HStack {
                Text("\(max(0, project.tableRows.count - 1)) Zeilen · \(columns) Spalten")
                Spacer()
                Text(formulaSummary).help("Formeln werden lokal ausgewertet. Zahlen in der Tabelle werden summiert; Textzellen bleiben unberücksichtigt.")
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 18).frame(height: 28)
        }
    }
}

private final class SheetTableView: NSTableView {
    var pasteCells: ((String) -> Void)?
    var cellClicked: ((SheetCell) -> Void)?
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point), column = column(at: point)
        if row >= 0, tableColumns.indices.contains(column), let dataColumn = Int(tableColumns[column].identifier.rawValue) {
            cellClicked?(.init(row: row, column: dataColumn))
        }
        super.mouseDown(with: event)
    }
    @objc func paste(_ sender: Any?) {
        if let text = NSPasteboard.general.string(forType: .string) { pasteCells?(text) }
    }
}

private struct NativeSpreadsheet: NSViewRepresentable {
    @Binding var rows: [[String]]
    @Binding var selected: SheetCell?
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        let table = SheetTableView()
        table.delegate = context.coordinator; table.dataSource = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.beginEditing)
        table.rowHeight = 34
        table.intercellSpacing = .zero
        table.gridStyleMask = [.solidHorizontalGridLineMask, .solidVerticalGridLineMask]
        table.gridColor = .separatorColor
        table.usesAlternatingRowBackgroundColors = true
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.allowsColumnReordering = false
        table.allowsEmptySelection = true
        table.setAccessibilityLabel("Tabellenzellen")
        table.cellClicked = { [weak coordinator = context.coordinator] cell in coordinator?.parent.selected = cell }
        table.pasteCells = { [weak coordinator = context.coordinator] text in coordinator?.paste(text) }
        scroll.documentView = table
        context.coordinator.table = table
        context.coordinator.rebuildColumns()
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.snapshot != rows else { return }
        context.coordinator.snapshot = rows
        context.coordinator.rebuildColumns()
        context.coordinator.table?.reloadData()
    }
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
        var parent: NativeSpreadsheet
        var snapshot: [[String]]
        weak var table: SheetTableView?
        init(_ parent: NativeSpreadsheet) { self.parent = parent; snapshot = parent.rows }
        func numberOfRows(in tableView: NSTableView) -> Int { snapshot.count }
        func rebuildColumns() {
            guard let table else { return }
            let count = max(1, snapshot.map(\.count).max() ?? 1)
            guard table.tableColumns.count != count + 1 else { return }
            for column in table.tableColumns { table.removeTableColumn(column) }
            let number = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("row"))
            number.title = ""; number.width = 42; number.minWidth = 42; number.maxWidth = 42
            number.resizingMask = []
            table.addTableColumn(number)
            for index in 0..<count {
                let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(String(index)))
                column.title = SpreadsheetData.columnName(index)
                column.width = 158; column.minWidth = 90
                column.resizingMask = .userResizingMask
                table.addTableColumn(column)
            }
        }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn else { return nil }
            let label = tableColumn.identifier.rawValue == "row"
            let field = NSTextField()
            field.isBordered = false; field.drawsBackground = false
            field.focusRingType = .none
            field.isEditable = !label; field.isSelectable = !label
            field.font = .systemFont(ofSize: label ? 11 : 12, weight: row == 0 && !label ? .semibold : .regular)
            field.textColor = label ? .secondaryLabelColor : .labelColor
            field.alignment = label ? .center : .left
            field.lineBreakMode = .byTruncatingTail
            field.translatesAutoresizingMaskIntoConstraints = false
            let cell = NSTableCellView()
            cell.addSubview(field); cell.textField = field
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            if label { field.stringValue = String(row + 1) }
            else if let column = Int(tableColumn.identifier.rawValue) {
                field.identifier = NSUserInterfaceItemIdentifier("\(row):\(column)")
                field.stringValue = SpreadsheetFormula.displayValue(atRow: row, column: column, in: snapshot)
                field.delegate = self
                field.setAccessibilityLabel("\(SpreadsheetData.columnName(column))\(row + 1)")
            }
            return cell
        }
        @objc func beginEditing() {
            guard let table, table.clickedRow >= 0, table.clickedColumn > 0 else { return }
            let cell = SheetCell(row: table.clickedRow, column: table.clickedColumn - 1)
            parent.selected = cell
            editCell(cell)
        }
        private func editCell(_ cell: SheetCell) {
            guard let table, cell.row >= 0, cell.row < snapshot.count, cell.column >= 0 else { return }
            let tableColumn = cell.column + 1
            table.scrollRowToVisible(cell.row)
            table.scrollColumnToVisible(tableColumn)
            let rawValue = snapshot[cell.row].indices.contains(cell.column) ? snapshot[cell.row][cell.column] : ""
            if let cellView = table.view(atColumn: tableColumn, row: cell.row, makeIfNecessary: true) as? NSTableCellView {
                cellView.textField?.stringValue = rawValue
            }
            table.editColumn(tableColumn, row: cell.row, with: nil, select: true)
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            let forward = commandSelector == #selector(NSResponder.insertTab(_:))
            let backward = commandSelector == #selector(NSResponder.insertBacktab(_:))
            let down = commandSelector == #selector(NSResponder.insertNewline(_:))
            guard forward || backward || down, let cell = parent.selected, let table else { return false }
            let width = max(1, snapshot.map(\.count).max() ?? 1)
            var next = cell
            if down { next.row += 1 }
            else if backward { next.column -= 1; if next.column < 0 { next.column = width - 1; next.row -= 1 } }
            else { next.column += 1; if next.column >= width { next.column = 0; next.row += 1 } }
            guard next.row >= 0 else { return true }
            table.window?.makeFirstResponder(table)
            if next.row >= snapshot.count {
                snapshot.append(Array(repeating: "", count: width)); parent.rows = snapshot; table.reloadData()
            }
            parent.selected = next
            table.scrollRowToVisible(next.row); table.scrollColumnToVisible(next.column + 1)
            DispatchQueue.main.async { [weak self] in self?.editCell(next) }
            return true
        }
        func coordinate(_ notification: Notification) -> (NSTextField, SheetCell)? {
            guard let field = notification.object as? NSTextField, let key = field.identifier?.rawValue else { return nil }
            let numbers = key.split(separator: ":").compactMap { Int($0) }
            guard numbers.count == 2 else { return nil }
            return (field, SheetCell(row: numbers[0], column: numbers[1]))
        }
        func controlTextDidBeginEditing(_ notification: Notification) {
            guard let (_, cell) = coordinate(notification) else { return }
            parent.selected = cell
        }
        func controlTextDidEndEditing(_ notification: Notification) {
            DispatchQueue.main.async { [weak self] in
                self?.table?.reloadData()
            }
        }
        func controlTextDidChange(_ notification: Notification) {
            guard let (field, cell) = coordinate(notification), snapshot.indices.contains(cell.row) else { return }
            while snapshot[cell.row].count <= cell.column { snapshot[cell.row].append("") }
            snapshot[cell.row][cell.column] = field.stringValue
            parent.rows = snapshot
        }
        func paste(_ text: String) {
            let start = parent.selected ?? SheetCell(row: max(1, table?.selectedRow ?? 1), column: 0)
            parent.rows = SpreadsheetData.pasting(text, into: parent.rows, at: start)
        }
    }
}
