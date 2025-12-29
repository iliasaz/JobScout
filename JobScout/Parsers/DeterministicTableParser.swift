//
//  DeterministicTableParser.swift
//  JobScout
//
//  Created by Ilia Sazonov on 12/26/25.
//

import Foundation

/// A fast, regex-based parser for HTML and Markdown tables
/// Marked nonisolated to allow use from any concurrency context
nonisolated struct DeterministicTableParser: Sendable {

    // MARK: - Format Detection

    /// Detects the table format in the content
    func detectFormat(_ content: String) -> TableFormat {
        let hasHTMLTable = content.range(
            of: "<table[^>]*>",
            options: [.regularExpression, .caseInsensitive]
        ) != nil

        let hasMarkdownTable = content.range(
            of: "\\|[^|]+\\|[^|]+\\|",
            options: .regularExpression
        ) != nil && content.range(
            of: "\\|\\s*[-:]+\\s*\\|",
            options: .regularExpression
        ) != nil

        if hasHTMLTable && hasMarkdownTable {
            return .mixed
        } else if hasHTMLTable {
            return .html
        } else if hasMarkdownTable {
            return .markdown
        } else {
            return .unknown
        }
    }

    // MARK: - Table Parsing

    /// Parses all tables from the content
    func parseTables(_ content: String, format: TableFormat? = nil) -> [ParsedTable] {
        let detectedFormat = format ?? detectFormat(content)

        switch detectedFormat {
        case .html:
            return parseHTMLTables(content)
        case .markdown:
            return parseMarkdownTables(content)
        case .mixed:
            // When mixed, prefer HTML tables as they're more structured
            // Only parse Markdown if no HTML tables found
            let htmlTables = parseHTMLTables(content)
            if !htmlTables.isEmpty {
                return htmlTables
            }
            return parseMarkdownTables(content)
        case .unknown:
            return []
        }
    }

    // MARK: - HTML Table Parsing

    private func parseHTMLTables(_ content: String) -> [ParsedTable] {
        var tables: [ParsedTable] = []

        // Find all section headings and their positions
        let headings = extractHeadings(from: content)

        // Find all table blocks with their positions
        let tablePattern = "<table[^>]*>([\\s\\S]*?)</table>"
        guard let tableRegex = try? NSRegularExpression(
            pattern: tablePattern,
            options: .caseInsensitive
        ) else { return [] }

        let range = NSRange(content.startIndex..., in: content)
        let matches = tableRegex.matches(in: content, options: [], range: range)

        for match in matches {
            guard let tableRange = Range(match.range(at: 1), in: content) else { continue }
            let tableContent = String(content[tableRange])
            let tablePosition = match.range.location

            // Find the most recent heading before this table
            let category = findCategory(for: tablePosition, in: headings)

            if let table = parseHTMLTable(tableContent, category: category) {
                tables.append(table)
            }
        }

        return tables
    }

    /// Extracts all headings (h1-h6 or markdown #) with their positions
    private func extractHeadings(from content: String) -> [(position: Int, text: String)] {
        var headings: [(position: Int, text: String)] = []

        // HTML headings: <h1>...</h1>, <h2>...</h2>, etc.
        let htmlHeadingPattern = "<h[1-6][^>]*>([\\s\\S]*?)</h[1-6]>"
        if let regex = try? NSRegularExpression(pattern: htmlHeadingPattern, options: .caseInsensitive) {
            let range = NSRange(content.startIndex..., in: content)
            let matches = regex.matches(in: content, options: [], range: range)

            for match in matches {
                if let textRange = Range(match.range(at: 1), in: content) {
                    let text = stripHTML(String(content[textRange]))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty && !text.lowercased().contains("inactive") {
                        headings.append((match.range.location, text))
                    }
                }
            }
        }

        // Markdown headings: ## Heading
        let lines = content.components(separatedBy: .newlines)
        var position = 0
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                // Extract heading text (remove # symbols and anchors)
                var headingText = trimmed.drop(while: { $0 == "#" })
                    .trimmingCharacters(in: .whitespaces)
                // Remove anchor links like [text](#anchor)
                headingText = headingText.replacingOccurrences(
                    of: "\\[([^\\]]+)\\]\\([^)]*\\)",
                    with: "$1",
                    options: .regularExpression
                )
                if !headingText.isEmpty && !headingText.lowercased().contains("inactive") {
                    headings.append((position, headingText))
                }
            }
            position += line.count + 1 // +1 for newline
        }

        return headings.sorted { $0.position < $1.position }
    }

    /// Finds the category (heading) for a table at a given position
    private func findCategory(for position: Int, in headings: [(position: Int, text: String)]) -> String {
        var category = "Other"
        for heading in headings {
            if heading.position < position {
                category = heading.text
            } else {
                break
            }
        }
        return shortenCategory(category)
    }

    /// Shortens category names to 2-3 words max
    private func shortenCategory(_ category: String) -> String {
        // Remove common filler words and phrases
        var shortened = category
            .replacingOccurrences(of: "Positions", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Position", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Roles", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Role", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Jobs", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Job", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Opportunities", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Openings", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "New Grad", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Entry Level", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Full Time", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Full-Time", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "2024", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "2025", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Take only first 3 words
        let words = shortened.split(separator: " ").prefix(3)
        shortened = words.joined(separator: " ")

        // If empty after cleaning, return original truncated
        if shortened.isEmpty {
            let words = category.split(separator: " ").prefix(3)
            shortened = words.joined(separator: " ")
        }

        return shortened.isEmpty ? "Other" : shortened
    }

    private func parseHTMLTable(_ tableContent: String, category: String) -> ParsedTable? {
        var headers: [String] = []
        var rows: [[String]] = []

        // Extract headers from <th> tags or first <tr>
        let headerPattern = "<th[^>]*>([\\s\\S]*?)</th>"
        if let headerRegex = try? NSRegularExpression(pattern: headerPattern, options: .caseInsensitive) {
            let range = NSRange(tableContent.startIndex..., in: tableContent)
            let matches = headerRegex.matches(in: tableContent, options: [], range: range)

            for match in matches {
                if let cellRange = Range(match.range(at: 1), in: tableContent) {
                    let cellContent = stripHTML(String(tableContent[cellRange]))
                    headers.append(cellContent)
                }
            }
        }

        // Extract rows from <tr> tags
        let rowPattern = "<tr[^>]*>([\\s\\S]*?)</tr>"
        guard let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: .caseInsensitive) else {
            return nil
        }

        let range = NSRange(tableContent.startIndex..., in: tableContent)
        let rowMatches = rowRegex.matches(in: tableContent, options: [], range: range)

        for (index, match) in rowMatches.enumerated() {
            guard let rowRange = Range(match.range(at: 1), in: tableContent) else { continue }
            let rowContent = String(tableContent[rowRange])

            let cells = extractCells(from: rowContent)

            // If no headers yet and this is the first row, use as headers
            if headers.isEmpty && index == 0 {
                headers = cells
                continue
            }

            // Skip separator rows or empty rows
            if cells.isEmpty || cells.allSatisfy({ $0.isEmpty || $0 == "-" || $0 == "---" }) {
                continue
            }

            rows.append(cells)
        }

        guard !headers.isEmpty else { return nil }

        return ParsedTable(headers: headers, rows: rows, format: .html, category: category)
    }

    private func extractCells(from rowContent: String) -> [String] {
        var cells: [String] = []

        // Try <td> first, then <th>
        let cellPattern = "<t[dh][^>]*>([\\s\\S]*?)</t[dh]>"
        guard let cellRegex = try? NSRegularExpression(pattern: cellPattern, options: .caseInsensitive) else {
            return []
        }

        let range = NSRange(rowContent.startIndex..., in: rowContent)
        let matches = cellRegex.matches(in: rowContent, options: [], range: range)

        for match in matches {
            if let cellRange = Range(match.range(at: 1), in: rowContent) {
                let cellContent = extractCellContent(String(rowContent[cellRange]))
                cells.append(cellContent)
            }
        }

        return cells
    }

    private func extractCellContent(_ html: String) -> String {
        var result = html

        // Extract link URLs and text: <a href="url">text</a> -> text [[url]]
        // This preserves links in a parseable format
        let linkPattern = "<a[^>]*href=[\"']([^\"']*)[\"'][^>]*>([\\s\\S]*?)</a>"
        if let linkRegex = try? NSRegularExpression(pattern: linkPattern, options: .caseInsensitive) {
            let range = NSRange(result.startIndex..., in: result)
            result = linkRegex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: "$2[[LINK:$1]]"  // Keep text and URL in parseable format
            )
        }

        return stripHTML(result)
    }

    /// Extracts all links from a cell's content (after extractCellContent processing)
    func extractLinks(from cellContent: String) -> [String] {
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
    func cleanCellContent(_ cellContent: String) -> String {
        return cellContent.replacingOccurrences(
            of: "\\[\\[LINK:[^\\]]+\\]\\]",
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stripHTML(_ html: String) -> String {
        var result = html

        // Remove all HTML tags
        result = result.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )

        // Decode common HTML entities
        let entities: [(String, String)] = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&nbsp;", " "),
            ("&#39;", "'"),
        ]

        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        // Clean up whitespace
        result = result.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Markdown Table Parsing

    private func parseMarkdownTables(_ content: String) -> [ParsedTable] {
        var tables: [ParsedTable] = []
        let lines = content.components(separatedBy: .newlines)

        var currentHeaders: [String] = []
        var currentRows: [[String]] = []
        var currentCategory = "Other"
        var inTable = false

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // Check for heading lines
            if trimmedLine.hasPrefix("#") {
                var headingText = String(trimmedLine.drop(while: { $0 == "#" }))
                    .trimmingCharacters(in: .whitespaces)
                // Remove anchor links like [text](#anchor)
                headingText = headingText.replacingOccurrences(
                    of: "\\[([^\\]]+)\\]\\([^)]*\\)",
                    with: "$1",
                    options: .regularExpression
                )
                if !headingText.isEmpty && !headingText.lowercased().contains("inactive") {
                    currentCategory = shortenCategory(headingText)
                }
            }

            // Check if this is a table row (starts and ends with |, or contains multiple |)
            let pipeCount = trimmedLine.filter { $0 == "|" }.count
            let isTableRow = pipeCount >= 2

            if isTableRow {
                let cells = parseMarkdownRow(trimmedLine)

                // Check if this is a separator row (|---|---|)
                let isSeparator = cells.allSatisfy { cell in
                    let cleaned = cell.trimmingCharacters(in: .whitespaces)
                    return cleaned.isEmpty ||
                           cleaned.allSatisfy { $0 == "-" || $0 == ":" } ||
                           cleaned.range(of: "^:?-+:?$", options: .regularExpression) != nil
                }

                if isSeparator {
                    // This confirms we have headers, skip this row
                    inTable = true
                    continue
                }

                if !inTable && currentHeaders.isEmpty {
                    // This is the header row
                    currentHeaders = cells
                } else if inTable || !currentHeaders.isEmpty {
                    // This is a data row
                    inTable = true
                    if !cells.allSatisfy({ $0.isEmpty }) {
                        currentRows.append(cells)
                    }
                }
            } else if inTable {
                // End of table
                if !currentHeaders.isEmpty {
                    tables.append(ParsedTable(
                        headers: currentHeaders,
                        rows: currentRows,
                        format: .markdown,
                        category: currentCategory
                    ))
                }
                currentHeaders = []
                currentRows = []
                inTable = false
            }
        }

        // Don't forget the last table if file doesn't end with non-table line
        if !currentHeaders.isEmpty {
            tables.append(ParsedTable(
                headers: currentHeaders,
                rows: currentRows,
                format: .markdown,
                category: currentCategory
            ))
        }

        return tables
    }

    private func parseMarkdownRow(_ line: String) -> [String] {
        var cells: [String] = []
        var trimmedLine = line.trimmingCharacters(in: .whitespaces)

        // Remove leading and trailing pipes
        if trimmedLine.hasPrefix("|") {
            trimmedLine.removeFirst()
        }
        if trimmedLine.hasSuffix("|") {
            trimmedLine.removeLast()
        }

        // Split by |
        let parts = trimmedLine.components(separatedBy: "|")

        for part in parts {
            let cell = extractMarkdownCellContent(part.trimmingCharacters(in: .whitespaces))
            cells.append(cell)
        }

        return cells
    }

    private func extractMarkdownCellContent(_ cell: String) -> String {
        var result = cell

        // Convert markdown links [text](url) to text[[LINK:url]] format
        let linkPattern = "\\[([^\\]]+)\\]\\(([^)]+)\\)"
        result = result.replacingOccurrences(
            of: linkPattern,
            with: "$1[[LINK:$2]]",
            options: .regularExpression
        )

        // Strip any remaining HTML (some markdown files have mixed content)
        result = stripHTML(result)

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Job Extraction

    /// Extracts job postings from parsed tables
    func extractJobs(from tables: [ParsedTable]) -> [JobPosting] {
        var jobs: [JobPosting] = []
        var seenIds: Set<String> = []

        for table in tables {
            let mapping = ColumnMapping.from(headers: table.headers)

            // Skip tables that don't look like job listings
            guard mapping.company != nil || mapping.role != nil else {
                continue
            }

            // Track previous company for ↳ handling
            var previousCompany: String?
            var previousIsFAANG: Bool = false

            for row in table.rows {
                if let result = mapping.extractJob(from: row, category: table.category, previousCompany: previousCompany, previousIsFAANG: previousIsFAANG) {
                    let job = result.job

                    // Update tracking for next row
                    previousCompany = result.company
                    previousIsFAANG = result.isFAANG

                    // Skip inactive/locked postings (rows without any valid links)
                    let hasValidLink = (job.companyLink != nil && !job.companyLink!.isEmpty) ||
                                       (job.aggregatorLink != nil && !job.aggregatorLink!.isEmpty)
                    guard hasValidLink else { continue }

                    // Deduplicate based on job id
                    if !seenIds.contains(job.id) {
                        seenIds.insert(job.id)
                        jobs.append(job)
                    }
                }
            }
        }

        return jobs
    }

    // MARK: - Convenience Method

    /// Parses content and extracts all job postings
    func parseJobPostings(from content: String) -> [JobPosting] {
        let tables = parseTables(content)
        return extractJobs(from: tables)
    }
}
