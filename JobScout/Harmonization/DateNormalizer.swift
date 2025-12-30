//
//  DateNormalizer.swift
//  JobScout
//
//  Created by Ilia Sazonov on 12/29/25.
//

import Foundation

/// Normalizes various date formats to ISO format (YYYY-MM-DD)
struct DateNormalizer: Sendable {
    /// Reference date for relative date calculations (defaults to now)
    let referenceDate: Date

    init(referenceDate: Date = Date()) {
        self.referenceDate = referenceDate
    }

    // MARK: - Date Formatters

    private static let isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let inputFormatters: [DateFormatter] = {
        var formatters: [DateFormatter] = []

        // "Dec 27" format (assumes current year)
        let monthDay = DateFormatter()
        monthDay.dateFormat = "MMM d"
        monthDay.locale = Locale(identifier: "en_US_POSIX")
        formatters.append(monthDay)

        // "Dec 27, 2024" format
        let monthDayYear = DateFormatter()
        monthDayYear.dateFormat = "MMM d, yyyy"
        monthDayYear.locale = Locale(identifier: "en_US_POSIX")
        formatters.append(monthDayYear)

        // "December 27" format
        let fullMonthDay = DateFormatter()
        fullMonthDay.dateFormat = "MMMM d"
        fullMonthDay.locale = Locale(identifier: "en_US_POSIX")
        formatters.append(fullMonthDay)

        // "December 27, 2024" format
        let fullMonthDayYear = DateFormatter()
        fullMonthDayYear.dateFormat = "MMMM d, yyyy"
        fullMonthDayYear.locale = Locale(identifier: "en_US_POSIX")
        formatters.append(fullMonthDayYear)

        // "12/27" format
        let slashFormat = DateFormatter()
        slashFormat.dateFormat = "MM/dd"
        slashFormat.locale = Locale(identifier: "en_US_POSIX")
        formatters.append(slashFormat)

        // "12/27/24" format
        let slashFormatYearShort = DateFormatter()
        slashFormatYearShort.dateFormat = "MM/dd/yy"
        slashFormatYearShort.locale = Locale(identifier: "en_US_POSIX")
        formatters.append(slashFormatYearShort)

        // "12/27/2024" format
        let slashFormatYear = DateFormatter()
        slashFormatYear.dateFormat = "MM/dd/yyyy"
        slashFormatYear.locale = Locale(identifier: "en_US_POSIX")
        formatters.append(slashFormatYear)

        // "2024-12-27" ISO format
        let isoFormat = DateFormatter()
        isoFormat.dateFormat = "yyyy-MM-dd"
        isoFormat.locale = Locale(identifier: "en_US_POSIX")
        formatters.append(isoFormat)

        // "27-Dec-2024" format
        let dayMonthYear = DateFormatter()
        dayMonthYear.dateFormat = "dd-MMM-yyyy"
        dayMonthYear.locale = Locale(identifier: "en_US_POSIX")
        formatters.append(dayMonthYear)

        return formatters
    }()

    // MARK: - Public Methods

    /// Normalize a date string to ISO format (YYYY-MM-DD)
    /// - Parameter dateString: The input date string in various formats
    /// - Returns: ISO formatted date string, or nil if parsing fails
    func normalize(_ dateString: String) -> String? {
        let trimmed = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Try relative date patterns first ("X days ago", "yesterday", etc.)
        if let date = parseRelativeDate(trimmed) {
            return Self.isoFormatter.string(from: date)
        }

        // Try fixed date formats
        if let date = parseFixedDate(trimmed) {
            return Self.isoFormatter.string(from: date)
        }

        return nil
    }

    /// Parse a date string and return as Date
    /// - Parameter dateString: The input date string
    /// - Returns: Parsed Date, or nil if parsing fails
    func parse(_ dateString: String) -> Date? {
        let trimmed = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let date = parseRelativeDate(trimmed) {
            return date
        }

        return parseFixedDate(trimmed)
    }

    // MARK: - Private Methods

    /// Parse relative date strings like "2 days ago", "yesterday", "15d", "2mo", etc.
    private func parseRelativeDate(_ input: String) -> Date? {
        let lowercased = input.lowercased().trimmingCharacters(in: .whitespaces)
        let calendar = Calendar.current

        // "today"
        if lowercased == "today" || lowercased == "just now" || lowercased == "now" {
            return referenceDate
        }

        // "yesterday"
        if lowercased == "yesterday" {
            return calendar.date(byAdding: .day, value: -1, to: referenceDate)
        }

        // Shorthand format: "Xd" (e.g., "0d", "15d", "1d")
        if let match = lowercased.range(of: #"^(\d+)d$"#, options: .regularExpression) {
            let numberPart = lowercased[match].components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            if let days = Int(numberPart) {
                return calendar.date(byAdding: .day, value: -days, to: referenceDate)
            }
        }

        // Shorthand format: "Xw" (e.g., "1w", "2w")
        if let match = lowercased.range(of: #"^(\d+)w$"#, options: .regularExpression) {
            let numberPart = lowercased[match].components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            if let weeks = Int(numberPart) {
                return calendar.date(byAdding: .weekOfYear, value: -weeks, to: referenceDate)
            }
        }

        // Shorthand format: "Xmo" (e.g., "1mo", "2mo")
        if let match = lowercased.range(of: #"^(\d+)mo$"#, options: .regularExpression) {
            let numberPart = lowercased[match].components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            if let months = Int(numberPart) {
                return calendar.date(byAdding: .month, value: -months, to: referenceDate)
            }
        }

        // Shorthand format: "Xm" for months (e.g., "1m", "2m") - but not to be confused with minutes
        // Only match if it's exactly "Xm" and X > 0 (0m would more likely be minutes)
        if let match = lowercased.range(of: #"^(\d+)m$"#, options: .regularExpression) {
            let numberPart = lowercased[match].components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            if let value = Int(numberPart), value > 0 {
                // Treat as months for values > 0
                return calendar.date(byAdding: .month, value: -value, to: referenceDate)
            }
        }

        // Shorthand format: "Xy" or "Xyr" for years (e.g., "1y", "1yr")
        if let match = lowercased.range(of: #"^(\d+)y(?:r)?$"#, options: .regularExpression) {
            let numberPart = lowercased[match].components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            if let years = Int(numberPart) {
                return calendar.date(byAdding: .year, value: -years, to: referenceDate)
            }
        }

        // "X days ago" / "X day ago"
        if let match = lowercased.range(of: #"(\d+)\s*days?\s*ago"#, options: .regularExpression) {
            let numberPart = lowercased[match].components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            if let days = Int(numberPart) {
                return calendar.date(byAdding: .day, value: -days, to: referenceDate)
            }
        }

        // "X weeks ago" / "X week ago"
        if let match = lowercased.range(of: #"(\d+)\s*weeks?\s*ago"#, options: .regularExpression) {
            let numberPart = lowercased[match].components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            if let weeks = Int(numberPart) {
                return calendar.date(byAdding: .weekOfYear, value: -weeks, to: referenceDate)
            }
        }

        // "X months ago" / "X month ago"
        if let match = lowercased.range(of: #"(\d+)\s*months?\s*ago"#, options: .regularExpression) {
            let numberPart = lowercased[match].components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            if let months = Int(numberPart) {
                return calendar.date(byAdding: .month, value: -months, to: referenceDate)
            }
        }

        // "X hours ago" / "X hour ago" - treat as today
        if lowercased.contains("hour") && lowercased.contains("ago") {
            return referenceDate
        }

        // "X minutes ago" / "X minute ago" - treat as today
        if lowercased.contains("minute") && lowercased.contains("ago") {
            return referenceDate
        }

        // Shorthand: "Xh" for hours - treat as today
        if lowercased.range(of: #"^(\d+)h$"#, options: .regularExpression) != nil {
            return referenceDate
        }

        // "last week"
        if lowercased == "last week" {
            return calendar.date(byAdding: .weekOfYear, value: -1, to: referenceDate)
        }

        // "last month"
        if lowercased == "last month" {
            return calendar.date(byAdding: .month, value: -1, to: referenceDate)
        }

        return nil
    }

    /// Parse fixed date formats using formatters
    private func parseFixedDate(_ input: String) -> Date? {
        let calendar = Calendar.current
        let now = referenceDate

        for formatter in Self.inputFormatters {
            if let date = formatter.date(from: input) {
                // For formats without year, assume current year
                // If the date is in the future, assume previous year
                if !formatter.dateFormat.contains("y") {
                    var components = calendar.dateComponents([.month, .day], from: date)
                    components.year = calendar.component(.year, from: now)

                    if let adjustedDate = calendar.date(from: components) {
                        // If date is more than a month in the future, assume previous year
                        if adjustedDate > now.addingTimeInterval(30 * 24 * 60 * 60) {
                            components.year = calendar.component(.year, from: now) - 1
                            return calendar.date(from: components)
                        }
                        return adjustedDate
                    }
                }
                return date
            }
        }

        return nil
    }
}
