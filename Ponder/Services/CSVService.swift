//
//  CSVService.swift
//  Ponder
//

import Foundation

enum CSVService {

    // MARK: - Export
    static func export(cells: [TableCellModel], rows: Int, cols: Int) -> String {
        var lines: [String] = []
        for r in 0..<rows {
            var rowValues: [String] = []
            for c in 0..<cols {
                let cell = cells.first { $0.row == r && $0.col == c }
                let val = cell?.value ?? ""
                // Escape commas and quotes
                if val.contains(",") || val.contains("\"") || val.contains("\n") {
                    rowValues.append("\"\(val.replacingOccurrences(of: "\"", with: "\"\""))\"")
                } else {
                    rowValues.append(val)
                }
            }
            lines.append(rowValues.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Parse
    static func parse(_ csv: String) -> [[String]] {
        var result: [[String]] = []
        let lines = csv.components(separatedBy: "\n")
        for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            result.append(parseRow(line))
        }
        return result
    }

    private static func parseRow(_ row: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var i = row.startIndex

        while i < row.endIndex {
            let ch = row[i]
            if ch == "\"" {
                if inQuotes && row.index(after: i) < row.endIndex && row[row.index(after: i)] == "\"" {
                    current.append("\"")
                    i = row.index(i, offsetBy: 2)
                    continue
                }
                inQuotes.toggle()
            } else if ch == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(ch)
            }
            i = row.index(after: i)
        }
        fields.append(current)
        return fields
    }
}
