//
//  Formatting.swift
//  Ocean Cast
//
//  Number, quantity, money and date formatting helpers.
//

import Foundation

enum Parse {
    /// Accepts both "1.5" and "1,5"; returns nil for empty or invalid input
    /// so callers can tell "not entered" apart from zero.
    static func double(_ text: String) -> Double? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }

    static func int(_ text: String) -> Int? {
        guard let value = double(text) else { return nil }
        return Int(value.rounded())
    }
}

enum Format {
    static func quantity(_ value: Double) -> String {
        if value.rounded() == value && abs(value) < 1_000_000 {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
            .replacingOccurrences(of: "0$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
    }

    static func measure(_ value: Double, _ unit: MeasureUnit) -> String {
        "\(quantity(value)) \(unit.short)"
    }

    static func money(_ value: Double?, currency: String) -> String? {
        guard let value else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "\(quantity(value)) \(currency)"
    }

    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

enum DateFormat {
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    private static let shortDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f
    }()

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    static func day(_ date: Date) -> String { dayFormatter.string(from: date) }
    static func shortDay(_ date: Date) -> String { shortDayFormatter.string(from: date) }
    static func stamp(_ date: Date) -> String { stampFormatter.string(from: date) }

    static func daysBetween(_ from: Date, _ to: Date) -> Int {
        let cal = Calendar.current
        let a = cal.startOfDay(for: from)
        let b = cal.startOfDay(for: to)
        return cal.dateComponents([.day], from: a, to: b).day ?? 0
    }

    /// "in 3 days" / "today" / "4 days ago"
    static func relativeDays(_ date: Date, from reference: Date = Date()) -> String {
        let days = daysBetween(reference, date)
        switch days {
        case 0: return "today"
        case 1: return "tomorrow"
        case -1: return "yesterday"
        case let d where d > 1: return "in \(d) days"
        default: return "\(-days) days ago"
        }
    }
}
