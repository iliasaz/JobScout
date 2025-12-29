# JobScout Agent Implementation Plan

## Overview

Build an intelligent agent using SwiftAgents that can parse job posting tables from GitHub README files, regardless of whether they're formatted as HTML tables or Markdown tables, and handle varying column structures.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        JobScoutAgent                            │
│  (ReActAgent with tools for content analysis and parsing)       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                          Tools                                  │
├─────────────────┬─────────────────┬─────────────────────────────┤
│ DetectFormatTool│ ParseTableTool  │ ExtractJobsTool             │
│ (Analyze content│ (Parse HTML or  │ (Normalize job data         │
│  to detect      │  Markdown table │  into structured format)    │
│  HTML/Markdown) │  based on type) │                             │
└─────────────────┴─────────────────┴─────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      JobPosting Model                           │
│  (Structured output: company, role, location, link, date)       │
└─────────────────────────────────────────────────────────────────┘
```

---

## Data Models

### JobPosting

```swift
struct JobPosting: Codable, Sendable {
    let company: String
    let role: String
    let location: String
    let applicationLink: String?
    let datePosted: String?
    let notes: String?  // Sponsorship info, requirements, etc.
}
```

### TableFormat (Enum)

```swift
enum TableFormat: String, Sendable {
    case html
    case markdown
    case mixed
    case unknown
}
```

### ParsedTable

```swift
struct ParsedTable: Sendable {
    let headers: [String]
    let rows: [[String]]
    let format: TableFormat
}
```

---

## Tools Implementation

### 1. DetectFormatTool

**Purpose:** Analyze content to determine if tables are HTML, Markdown, or mixed.

```swift
@Tool("Analyzes content to detect whether tables are HTML or Markdown format")
struct DetectFormatTool {
    @Parameter("The raw content to analyze")
    var content: String

    func execute() async throws -> SendableValue {
        // Detection logic:
        // 1. Look for <table>, <tr>, <td>, <th> tags → HTML
        // 2. Look for |---|---| patterns → Markdown
        // 3. Both present → Mixed

        let hasHTMLTable = content.contains(regex: "<table[^>]*>")
        let hasMarkdownTable = content.contains(regex: "\\|[\\s-]+\\|")

        let format: TableFormat
        if hasHTMLTable && hasMarkdownTable {
            format = .mixed
        } else if hasHTMLTable {
            format = .html
        } else if hasMarkdownTable {
            format = .markdown
        } else {
            format = .unknown
        }

        return [
            "format": .string(format.rawValue),
            "hasHTMLTables": .bool(hasHTMLTable),
            "hasMarkdownTables": .bool(hasMarkdownTable)
        ]
    }
}
```

### 2. ParseHTMLTableTool

**Purpose:** Extract tables from HTML format.

```swift
@Tool("Parses HTML tables and extracts headers and rows")
struct ParseHTMLTableTool {
    @Parameter("HTML content containing tables")
    var content: String

    func execute() async throws -> SendableValue {
        // Parse HTML tables:
        // 1. Find all <table>...</table> blocks
        // 2. Extract <th> or first <tr> as headers
        // 3. Extract remaining <tr> as data rows
        // 4. Strip HTML tags from cell content, preserve links

        var tables: [ParsedTable] = []
        // ... parsing logic ...

        return .array(tables.map { table in
            [
                "headers": .array(table.headers.map { .string($0) }),
                "rowCount": .int(table.rows.count),
                "rows": .array(table.rows.map { row in
                    .array(row.map { .string($0) })
                })
            ]
        })
    }
}
```

### 3. ParseMarkdownTableTool

**Purpose:** Extract tables from Markdown format.

```swift
@Tool("Parses Markdown tables and extracts headers and rows")
struct ParseMarkdownTableTool {
    @Parameter("Markdown content containing tables")
    var content: String

    func execute() async throws -> SendableValue {
        // Parse Markdown tables:
        // 1. Find lines starting with |
        // 2. First row = headers
        // 3. Second row = separator (|---|---|)
        // 4. Remaining rows = data

        var tables: [ParsedTable] = []
        // ... parsing logic ...

        return .array(tables.map { ... })
    }
}
```

### 4. MapColumnsTool

**Purpose:** Intelligently map varying column names to standard fields.

```swift
@Tool("Maps table columns to standard job posting fields using fuzzy matching")
struct MapColumnsTool {
    @Parameter("Array of column header names from the table")
    var headers: [String]

    func execute() async throws -> SendableValue {
        // Map common variations:
        // "Company", "Employer", "Organization" → company
        // "Role", "Position", "Title", "Job" → role
        // "Location", "City", "Office", "Where" → location
        // "Apply", "Link", "Application", "URL" → applicationLink
        // "Date", "Posted", "Added", "Age" → datePosted

        let mappings: [String: String] = [:]
        // ... fuzzy matching logic ...

        return .dictionary(mappings.mapValues { .string($0) })
    }
}
```

### 5. ExtractJobsTool

**Purpose:** Convert parsed table rows into structured JobPosting objects.

```swift
@Tool("Extracts job postings from parsed table data using column mappings")
struct ExtractJobsTool {
    @Parameter("Parsed table rows as array of arrays")
    var rows: [[String]]

    @Parameter("Column index mappings (e.g., {'company': 0, 'role': 1})")
    var columnMappings: [String: Int]

    func execute() async throws -> SendableValue {
        var jobs: [JobPosting] = []

        for row in rows {
            let job = JobPosting(
                company: row[safe: columnMappings["company"] ?? -1] ?? "",
                role: row[safe: columnMappings["role"] ?? -1] ?? "",
                location: row[safe: columnMappings["location"] ?? -1] ?? "",
                applicationLink: row[safe: columnMappings["applicationLink"] ?? -1],
                datePosted: row[safe: columnMappings["datePosted"] ?? -1],
                notes: row[safe: columnMappings["notes"] ?? -1]
            )
            jobs.append(job)
        }

        return .array(jobs.map { $0.toSendableValue() })
    }
}
```

---

## Agent Configuration

### JobScoutAgent

```swift
import SwiftAgents

actor JobScoutAgent {
    private let agent: ReActAgent

    init(provider: OpenRouterProvider) {
        self.agent = ReActAgent.Builder()
            .inferenceProvider(provider)
            .instructions("""
                You are a job posting parser agent. Your task is to:
                1. Analyze the provided content to detect table format (HTML or Markdown)
                2. Parse the tables to extract rows and headers
                3. Map column headers to standard job posting fields
                4. Extract structured job posting data

                Available table formats:
                - HTML: Uses <table>, <tr>, <th>, <td> tags
                - Markdown: Uses | for columns and |---| for header separator

                Standard job posting fields:
                - company: The hiring company name
                - role: Job title/position
                - location: Office location or "Remote"
                - applicationLink: URL to apply
                - datePosted: When the job was posted
                - notes: Additional info (sponsorship, requirements)

                Always detect the format first, then use the appropriate parser.
                Handle variations in column names intelligently.
                """)
            .addTool(DetectFormatTool())
            .addTool(ParseHTMLTableTool())
            .addTool(ParseMarkdownTableTool())
            .addTool(MapColumnsTool())
            .addTool(ExtractJobsTool())
            .configuration(
                .default
                    .maxIterations(10)
                    .temperature(0.3)  // Lower for more deterministic parsing
                    .timeout(.seconds(120))
            )
            .build()
    }

    func parseJobPostings(from content: String) async throws -> [JobPosting] {
        let result = try await agent.run("""
            Parse the following content and extract all job postings:

            \(content)
            """)

        // Parse result.output to extract JobPosting array
        return parseJobPostingsFromOutput(result.output)
    }
}
```

---

## Alternative: Hybrid Approach (Recommended)

Since LLM calls can be slow/expensive for parsing, use a **hybrid approach**:

1. **Deterministic parsing first** - Use regex/string parsing for well-formed tables
2. **Agent fallback** - Only invoke the agent when:
   - Format detection is ambiguous
   - Column mapping is unclear
   - Parsing fails or produces poor results

```swift
actor HybridJobParser {
    private let deterministicParser: DeterministicTableParser
    private let agent: JobScoutAgent

    func parse(content: String) async throws -> [JobPosting] {
        // Try deterministic parsing first
        do {
            let format = deterministicParser.detectFormat(content)
            let tables = try deterministicParser.parseTables(content, format: format)
            let jobs = try deterministicParser.extractJobs(from: tables)

            // If we got results, return them
            if !jobs.isEmpty {
                return jobs
            }
        } catch {
            // Fall through to agent
        }

        // Fallback to agent for complex/ambiguous cases
        return try await agent.parseJobPostings(from: content)
    }
}
```

---

## Implementation Steps

### Phase 1: Core Infrastructure
1. [ ] Create `Models/JobPosting.swift` with data models
2. [ ] Create `Models/ParsedTable.swift` for intermediate parsing
3. [ ] Create `Parsers/DeterministicTableParser.swift` for regex-based parsing

### Phase 2: Tools
4. [ ] Implement `Tools/DetectFormatTool.swift`
5. [ ] Implement `Tools/ParseHTMLTableTool.swift`
6. [ ] Implement `Tools/ParseMarkdownTableTool.swift`
7. [ ] Implement `Tools/MapColumnsTool.swift`
8. [ ] Implement `Tools/ExtractJobsTool.swift`

### Phase 3: Agent
9. [ ] Create `Agent/JobScoutAgent.swift`
10. [ ] Add OpenRouter API key configuration (via environment or settings)
11. [ ] Create `Agent/HybridJobParser.swift` combining deterministic + agent

### Phase 4: UI Integration
12. [ ] Update `ContentView.swift` to use the new parser
13. [ ] Add UI for displaying parsed job postings
14. [ ] Add loading/progress indicators for agent operations

### Phase 5: Testing & Refinement
15. [ ] Test with various README formats from different job repos
16. [ ] Tune agent prompts based on results
17. [ ] Add caching for parsed results

---

## File Structure

```
JobScout/
├── Models/
│   ├── JobPosting.swift
│   └── ParsedTable.swift
├── Parsers/
│   └── DeterministicTableParser.swift
├── Tools/
│   ├── DetectFormatTool.swift
│   ├── ParseHTMLTableTool.swift
│   ├── ParseMarkdownTableTool.swift
│   ├── MapColumnsTool.swift
│   └── ExtractJobsTool.swift
├── Agent/
│   ├── JobScoutAgent.swift
│   └── HybridJobParser.swift
├── Views/
│   ├── ContentView.swift
│   └── JobPostingRow.swift
└── Config/
    └── APIConfiguration.swift
```

---

## API Key Management

For OpenRouter API key:

```swift
// Option 1: Environment variable
let apiKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] ?? ""

// Option 2: Keychain storage (recommended for production)
let apiKey = try KeychainService.shared.get("openrouter_api_key")

// Option 3: User settings (for development)
@AppStorage("openRouterAPIKey") var apiKey: String = ""
```

---

## Example Usage

```swift
// In ContentView or a ViewModel
let parser = HybridJobParser(
    provider: try OpenRouterProvider(
        apiKey: apiKey,
        model: .claude35Sonnet
    )
)

let content = try await downloadMarkdown(from: url)
let jobs = try await parser.parse(content: content)

// Display in UI
ForEach(jobs, id: \.applicationLink) { job in
    JobPostingRow(job: job)
}
```

---

## Notes

- **Model choice**: Claude 3.5 Sonnet recommended for best parsing accuracy
- **Cost optimization**: Use deterministic parsing first, agent as fallback
- **Rate limiting**: OpenRouter has rate limits; implement retry logic
- **Caching**: Cache parsed results to avoid re-parsing same content
- **Error handling**: Gracefully handle API failures, fall back to simple display
