//
//  JobParsingTools.swift
//  JobScout
//
//  Created by Ilia Sazonov on 12/26/25.
//

import Foundation
import SwiftAgents

// MARK: - Detect Format Tool

nonisolated struct DetectFormatTool: Tool {
    let name = "detect_format"
    let description = "Analyzes content to detect whether tables are in HTML or Markdown format"

    let parameters: [ToolParameter] = [
        ToolParameter(
            name: "content",
            description: "The raw content to analyze for table format detection",
            type: .string,
            isRequired: true
        )
    ]

    func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        guard let content = arguments["content"]?.stringValue else {
            throw AgentError.invalidToolArguments(
                toolName: name,
                reason: "Missing required parameter 'content'"
            )
        }

        let parser = DeterministicTableParser()
        let format = parser.detectFormat(content)

        let hasHTMLTable = content.range(
            of: "<table[^>]*>",
            options: [.regularExpression, .caseInsensitive]
        ) != nil

        let hasMarkdownTable = content.range(
            of: "\\|[-:]+\\|",
            options: .regularExpression
        ) != nil

        return .string("""
            Format detected: \(format.rawValue)
            Has HTML tables: \(hasHTMLTable)
            Has Markdown tables: \(hasMarkdownTable)
            """)
    }
}

// MARK: - Parse Tables Tool

nonisolated struct ParseTablesTool: Tool {
    let name = "parse_tables"
    let description = "Parses all tables from content and returns structured table data with headers and rows"

    let parameters: [ToolParameter] = [
        ToolParameter(
            name: "content",
            description: "The content containing tables to parse",
            type: .string,
            isRequired: true
        ),
        ToolParameter(
            name: "format",
            description: "The format to parse: 'html', 'markdown', or 'auto' for automatic detection",
            type: .string,
            isRequired: false,
            defaultValue: .string("auto")
        )
    ]

    func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        guard let content = arguments["content"]?.stringValue else {
            throw AgentError.invalidToolArguments(
                toolName: name,
                reason: "Missing required parameter 'content'"
            )
        }

        let formatStr = arguments["format"]?.stringValue ?? "auto"
        let parser = DeterministicTableParser()

        let tableFormat: TableFormat?
        switch formatStr.lowercased() {
        case "html":
            tableFormat = .html
        case "markdown":
            tableFormat = .markdown
        default:
            tableFormat = nil
        }

        let tables = parser.parseTables(content, format: tableFormat)

        if tables.isEmpty {
            return .string("No tables found in the content.")
        }

        var result = "Found \(tables.count) table(s):\n\n"

        for (index, table) in tables.enumerated() {
            result += "Table \(index + 1) (\(table.format.rawValue)):\n"
            result += "Headers: \(table.headers.joined(separator: " | "))\n"
            result += "Rows: \(table.rowCount)\n"

            let sampleRows = table.rows.prefix(3)
            for row in sampleRows {
                result += "  - \(row.joined(separator: " | "))\n"
            }
            if table.rowCount > 3 {
                result += "  ... and \(table.rowCount - 3) more rows\n"
            }
            result += "\n"
        }

        return .string(result)
    }
}

// MARK: - Extract Jobs Tool

nonisolated struct ExtractJobsTool: Tool {
    let name = "extract_jobs"
    let description = "Extracts job postings from parsed table content and returns structured job data"

    let parameters: [ToolParameter] = [
        ToolParameter(
            name: "content",
            description: "The content containing job posting tables",
            type: .string,
            isRequired: true
        )
    ]

    func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        guard let content = arguments["content"]?.stringValue else {
            throw AgentError.invalidToolArguments(
                toolName: name,
                reason: "Missing required parameter 'content'"
            )
        }

        let parser = DeterministicTableParser()
        let jobs = parser.parseJobPostings(from: content)

        if jobs.isEmpty {
            return .string("No job postings found. The tables might not contain recognizable job listing columns (company, role, location).")
        }

        var result = "Found \(jobs.count) job posting(s):\n\n"

        for (index, job) in jobs.prefix(20).enumerated() {
            result += "\(index + 1). \(job.company) - \(job.role)\n"
            result += "   Location: \(job.location)\n"
            if let date = job.datePosted, !date.isEmpty {
                result += "   Posted: \(date)\n"
            }
            if let link = job.companyLink, !link.isEmpty {
                result += "   Apply: \(link)\n"
            }
            if let link = job.aggregatorLink, !link.isEmpty {
                result += "   Aggregator: \(link)\n"
            }
            if let notes = job.notes, !notes.isEmpty {
                result += "   Notes: \(notes)\n"
            }
            result += "\n"
        }

        if jobs.count > 20 {
            result += "... and \(jobs.count - 20) more job postings\n"
        }

        return .string(result)
    }
}

// MARK: - Analyze Columns Tool

nonisolated struct AnalyzeColumnsTool: Tool {
    let name = "analyze_columns"
    let description = "Analyzes table headers and suggests column mappings for job posting fields"

    let parameters: [ToolParameter] = [
        ToolParameter(
            name: "headers",
            description: "Comma-separated list of table column headers",
            type: .string,
            isRequired: true
        )
    ]

    func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        guard let headersStr = arguments["headers"]?.stringValue else {
            throw AgentError.invalidToolArguments(
                toolName: name,
                reason: "Missing required parameter 'headers'"
            )
        }

        let headerList = headersStr.components(separatedBy: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let mapping = ColumnMapping.from(headers: headerList)

        var result = "Column mapping analysis:\n\n"
        result += "Headers: \(headerList.joined(separator: ", "))\n\n"
        result += "Detected mappings:\n"

        if let idx = mapping.company, idx < headerList.count {
            result += "  - Company: column \(idx) (\(headerList[idx]))\n"
        } else {
            result += "  - Company: NOT FOUND\n"
        }

        if let idx = mapping.role, idx < headerList.count {
            result += "  - Role: column \(idx) (\(headerList[idx]))\n"
        } else {
            result += "  - Role: NOT FOUND\n"
        }

        if let idx = mapping.location, idx < headerList.count {
            result += "  - Location: column \(idx) (\(headerList[idx]))\n"
        } else {
            result += "  - Location: NOT FOUND\n"
        }

        if let idx = mapping.linkColumn, idx < headerList.count {
            result += "  - Link Column: column \(idx) (\(headerList[idx]))\n"
        } else {
            result += "  - Link Column: NOT FOUND\n"
        }

        if let idx = mapping.datePosted, idx < headerList.count {
            result += "  - Date Posted: column \(idx) (\(headerList[idx]))\n"
        } else {
            result += "  - Date Posted: NOT FOUND\n"
        }

        if let idx = mapping.notes, idx < headerList.count {
            result += "  - Notes: column \(idx) (\(headerList[idx]))\n"
        } else {
            result += "  - Notes: NOT FOUND\n"
        }

        return .string(result)
    }
}
