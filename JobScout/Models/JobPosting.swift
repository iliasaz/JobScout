//
//  JobPosting.swift
//  JobScout
//
//  Created by Ilia Sazonov on 12/26/25.
//

import Foundation

/// Represents a single job posting extracted from a table
struct JobPosting: Codable, Sendable, Identifiable, Hashable {
    /// Unique identifier combining all fields to ensure uniqueness
    var id: String {
        "\(company)-\(role)-\(location)-\(companyLink ?? "")-\(datePosted ?? "")"
    }

    let company: String
    let role: String
    let location: String
    let country: String         // Extracted country (defaults to "USA")
    let category: String        // Job category (Software Engineering, Product Management, etc.)
    let companyLink: String?    // Direct link to company career page
    let simplifyLink: String?   // Link to Simplify aggregator
    let datePosted: String?
    let notes: String?  // Sponsorship info, requirements, etc.
    let isFAANG: Bool   // True if company is a FAANG-like company (marked with fire emoji)

    init(
        company: String,
        role: String,
        location: String,
        country: String? = nil,
        category: String = "Other",
        companyLink: String? = nil,
        simplifyLink: String? = nil,
        datePosted: String? = nil,
        notes: String? = nil,
        isFAANG: Bool = false
    ) {
        self.company = company.trimmingCharacters(in: .whitespacesAndNewlines)
        self.role = role.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        self.location = cleanedLocation
        self.country = country ?? Self.extractCountry(from: cleanedLocation)
        self.category = category
        self.companyLink = Self.cleanLink(companyLink)
        self.simplifyLink = Self.cleanLink(simplifyLink)
        self.datePosted = datePosted?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isFAANG = isFAANG
    }

    /// Extracts country from location string, defaults to "USA"
    private static func extractCountry(from location: String) -> String {
        let loc = location.lowercased()

        // Check for explicit country mentions
        if loc.contains("canada") {
            return "Canada"
        }
        if loc.contains("uk") || loc.contains("united kingdom") || loc.contains("england") || loc.contains("london") {
            return "UK"
        }
        if loc.contains("germany") || loc.contains("berlin") || loc.contains("munich") {
            return "Germany"
        }
        if loc.contains("india") || loc.contains("bangalore") || loc.contains("hyderabad") || loc.contains("mumbai") {
            return "India"
        }
        if loc.contains("ireland") || loc.contains("dublin") {
            return "Ireland"
        }
        if loc.contains("australia") || loc.contains("sydney") || loc.contains("melbourne") {
            return "Australia"
        }
        if loc.contains("singapore") {
            return "Singapore"
        }
        if loc.contains("japan") || loc.contains("tokyo") {
            return "Japan"
        }
        if loc.contains("netherlands") || loc.contains("amsterdam") {
            return "Netherlands"
        }
        if loc.contains("france") || loc.contains("paris") {
            return "France"
        }
        if loc.contains("israel") || loc.contains("tel aviv") {
            return "Israel"
        }
        if loc.contains("china") || loc.contains("beijing") || loc.contains("shanghai") {
            return "China"
        }
        if loc.contains("mexico") {
            return "Mexico"
        }
        if loc.contains("brazil") || loc.contains("são paulo") || loc.contains("sao paulo") {
            return "Brazil"
        }
        if loc.contains("spain") || loc.contains("madrid") || loc.contains("barcelona") {
            return "Spain"
        }
        if loc.contains("italy") || loc.contains("milan") || loc.contains("rome") {
            return "Italy"
        }
        if loc.contains("poland") || loc.contains("warsaw") || loc.contains("krakow") {
            return "Poland"
        }
        if loc.contains("sweden") || loc.contains("stockholm") {
            return "Sweden"
        }
        if loc.contains("switzerland") || loc.contains("zurich") {
            return "Switzerland"
        }

        // Check for US indicators (state abbreviations, "USA", "US", or common US cities)
        if loc.contains("usa") || loc.contains("united states") {
            return "USA"
        }

        // US state abbreviations pattern (e.g., ", CA", ", NY", ", TX")
        let statePattern = ",\\s*(al|ak|az|ar|ca|co|ct|de|fl|ga|hi|id|il|in|ia|ks|ky|la|me|md|ma|mi|mn|ms|mo|mt|ne|nv|nh|nj|nm|ny|nc|nd|oh|ok|or|pa|ri|sc|sd|tn|tx|ut|vt|va|wa|wv|wi|wy|dc)\\b"
        if loc.range(of: statePattern, options: .regularExpression) != nil {
            return "USA"
        }

        // Common US cities without state
        let usCities = ["new york", "san francisco", "seattle", "austin", "boston", "chicago",
                        "los angeles", "denver", "atlanta", "miami", "dallas", "houston",
                        "phoenix", "philadelphia", "san diego", "san jose", "palo alto",
                        "mountain view", "menlo park", "cupertino", "redmond", "pittsburgh"]
        for city in usCities {
            if loc.contains(city) {
                return "USA"
            }
        }

        // "Remote" without country specification defaults to USA
        if loc.contains("remote") && !loc.contains(",") {
            return "USA"
        }

        // Default to USA if nothing else matches
        return "USA"
    }

    private static func cleanLink(_ link: String?) -> String? {
        guard let link = link?.trimmingCharacters(in: .whitespacesAndNewlines),
              !link.isEmpty else {
            return nil
        }
        return link
    }

    /// Parses datePosted string into a Date for sorting (newest first)
    /// Handles formats like "Dec 27", "Dec 2024", "12/27", etc.
    var parsedDate: Date? {
        guard let dateStr = datePosted, !dateStr.isEmpty else {
            return nil
        }

        let formatters: [DateFormatter] = {
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

            // "12/27" format
            let slashFormat = DateFormatter()
            slashFormat.dateFormat = "MM/dd"
            slashFormat.locale = Locale(identifier: "en_US_POSIX")
            formatters.append(slashFormat)

            // "12/27/24" format
            let slashFormatYear = DateFormatter()
            slashFormatYear.dateFormat = "MM/dd/yy"
            slashFormatYear.locale = Locale(identifier: "en_US_POSIX")
            formatters.append(slashFormatYear)

            // "2024-12-27" ISO format
            let isoFormat = DateFormatter()
            isoFormat.dateFormat = "yyyy-MM-dd"
            isoFormat.locale = Locale(identifier: "en_US_POSIX")
            formatters.append(isoFormat)

            return formatters
        }()

        let trimmed = dateStr.trimmingCharacters(in: .whitespacesAndNewlines)

        for formatter in formatters {
            if let date = formatter.date(from: trimmed) {
                // For formats without year, assume current year
                // If the date is in the future, assume previous year
                let calendar = Calendar.current
                let now = Date()

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

    /// Sort date for comparison - returns distant past for nil dates so they sort last
    var sortDate: Date {
        parsedDate ?? Date.distantPast
    }
}

extension JobPosting: CustomStringConvertible {
    var description: String {
        var desc = "\(company) - \(role) (\(location))"
        if let date = datePosted, !date.isEmpty {
            desc += " [Posted: \(date)]"
        }
        if let notes = notes, !notes.isEmpty {
            desc += " - \(notes)"
        }
        return desc
    }
}
