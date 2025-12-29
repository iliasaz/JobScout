//
//  ParsedTable.swift
//  JobScout
//
//  Created by Ilia Sazonov on 12/26/25.
//

import Foundation

/// Detected table format
enum TableFormat: String, Sendable, Codable {
    case html
    case markdown
    case mixed
    case unknown
}

/// Represents a parsed table with headers and rows
struct ParsedTable: Sendable {
    let headers: [String]
    let rows: [[String]]
    let format: TableFormat
    let category: String  // Section heading this table belongs to

    var isEmpty: Bool {
        rows.isEmpty
    }

    var rowCount: Int {
        rows.count
    }

    var columnCount: Int {
        headers.count
    }
}

/// Mapping of standard field names to column indices
struct ColumnMapping: Sendable {
    let company: Int?
    let role: Int?
    let location: Int?
    let linkColumn: Int?
    let datePosted: Int?
    let notes: Int?

    /// Creates a ColumnMapping by fuzzy matching header names
    static func from(headers: [String]) -> ColumnMapping {
        let lowercaseHeaders = headers.map { $0.lowercased() }

        func findIndex(for patterns: [String]) -> Int? {
            for (index, header) in lowercaseHeaders.enumerated() {
                for pattern in patterns {
                    if header.contains(pattern) {
                        return index
                    }
                }
            }
            return nil
        }

        return ColumnMapping(
            company: findIndex(for: ["company", "employer", "organization", "org"]),
            role: findIndex(for: ["role", "position", "title", "job"]),
            location: findIndex(for: ["location", "city", "office", "where", "place"]),
            linkColumn: findIndex(for: ["apply", "link", "application", "url"]),
            datePosted: findIndex(for: ["date", "posted", "added", "age", "when"]),
            notes: findIndex(for: ["note", "info", "requirement", "sponsor", "status"])
        )
    }

    /// Extracts a JobPosting from a row using this mapping
    /// - Parameters:
    ///   - row: The table row data
    ///   - category: The job category (from section heading)
    ///   - previousCompany: Company name from previous row (for ↳ handling)
    ///   - previousIsFAANG: FAANG status from previous row (for ↳ handling)
    /// - Returns: Tuple of (JobPosting, company name, isFAANG) or nil
    func extractJob(from row: [String], category: String = "Other", previousCompany: String? = nil, previousIsFAANG: Bool = false) -> (job: JobPosting, company: String, isFAANG: Bool)? {
        guard let companyIdx = company, companyIdx < row.count,
              let roleIdx = role, roleIdx < row.count else {
            return nil
        }

        let rawCompanyValue = row[companyIdx]
        let roleValue = Self.cleanValue(row[roleIdx])

        // Detect FAANG flag (fire emoji 🔥 or fire image)
        let isFAANG = rawCompanyValue.contains("🔥") ||
                      rawCompanyValue.lowercased().contains("alt=\"fire\"") ||
                      rawCompanyValue.lowercased().contains(":fire:")

        // Clean company value (remove link markers and fire emoji)
        var companyValue = Self.cleanValue(rawCompanyValue)
        companyValue = companyValue.replacingOccurrences(of: "🔥", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle ↳ symbol - use previous company name
        let actualCompany: String
        let actualIsFAANG: Bool
        if companyValue.hasPrefix("↳") || companyValue == "↳" {
            actualCompany = previousCompany ?? companyValue.replacingOccurrences(of: "↳", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            actualIsFAANG = previousIsFAANG
        } else {
            actualCompany = companyValue
            actualIsFAANG = isFAANG
        }

        // Skip empty rows or header-like rows
        guard !actualCompany.isEmpty, !roleValue.isEmpty,
              actualCompany.lowercased() != "company",
              roleValue.lowercased() != "role" else {
            return nil
        }

        // Extract links from link column and separate by type
        var companyLink: String?
        var simplifyLink: String?

        if let linkIdx = linkColumn, linkIdx < row.count {
            let links = Self.extractLinks(from: row[linkIdx])
            for link in links {
                if link.contains("simplify.jobs") {
                    simplifyLink = link
                } else if companyLink == nil && !link.isEmpty {
                    companyLink = link
                }
            }
        }

        // Also check company column for links (sometimes company name is a link)
        if companyLink == nil {
            let companyLinks = Self.extractLinks(from: rawCompanyValue)
            companyLink = companyLinks.first { !$0.contains("simplify.jobs") }
        }

        let job = JobPosting(
            company: actualCompany,
            role: roleValue,
            location: Self.cleanValue(location.flatMap { $0 < row.count ? row[$0] : nil } ?? ""),
            category: category,
            companyLink: companyLink,
            simplifyLink: simplifyLink,
            datePosted: Self.cleanValue(datePosted.flatMap { $0 < row.count ? row[$0] : nil }),
            notes: Self.cleanValue(notes.flatMap { $0 < row.count ? row[$0] : nil }),
            isFAANG: actualIsFAANG
        )

        return (job, actualCompany, actualIsFAANG)
    }

    /// Extracts all links from a cell value containing [[LINK:url]] markers
    private static func extractLinks(from cellContent: String) -> [String] {
        var links: [String] = []
        let pattern = "\\[\\[LINK:([^\\]]+)\\]\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return links
        }

        let range = NSRange(cellContent.startIndex..., in: cellContent)
        let matches = regex.matches(in: cellContent, options: [], range: range)

        for match in matches {
            if let linkRange = Range(match.range(at: 1), in: cellContent) {
                links.append(String(cellContent[linkRange]))
            }
        }

        return links
    }

    /// Removes link markers from cell content for display
    private static func cleanValue(_ value: String?) -> String {
        guard let value = value else { return "" }
        return value.replacingOccurrences(
            of: "\\[\\[LINK:[^\\]]+\\]\\]",
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
