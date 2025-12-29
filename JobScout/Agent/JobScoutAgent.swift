//
//  JobScoutAgent.swift
//  JobScout
//
//  Created by Ilia Sazonov on 12/26/25.
//

import Foundation
import SwiftAgents

/// Agent for intelligently parsing job postings from various table formats
actor JobScoutAgent {
    private let agent: ReActAgent

    init(provider: any InferenceProvider) throws {
        self.agent = ReActAgent.Builder()
            .inferenceProvider(provider)
            .instructions("""
                You are a job posting parser agent. Your task is to analyze content and extract job postings from tables.

                The content may contain tables in different formats:
                - HTML tables: Using <table>, <tr>, <th>, <td> tags
                - Markdown tables: Using | for columns and |---| for header separators

                Standard job posting fields to extract:
                - company: The hiring company name
                - role: Job title/position
                - location: Office location or "Remote"
                - applicationLink: URL to apply
                - datePosted: When the job was posted
                - notes: Additional info (sponsorship requirements, etc.)

                Steps to follow:
                1. First, use DetectFormatTool to identify the table format
                2. Use ParseTablesTool to parse the tables
                3. Use ExtractJobsTool to extract structured job postings
                4. If column headers are unclear, use AnalyzeColumnsTool to help map them

                Be thorough and extract all job postings you can find.
                """)
            .addTool(DetectFormatTool())
            .addTool(ParseTablesTool())
            .addTool(ExtractJobsTool())
            .addTool(AnalyzeColumnsTool())
            .configuration(
                .default
                    .maxIterations(8)
                    .temperature(0.3)
                    .timeout(.seconds(90))
            )
            .build()
    }

    /// Parses job postings from content using the agent
    func parseJobPostings(from content: String) async throws -> AgentResult {
        return try await agent.run("""
            Parse the following content and extract all job postings.
            Report the total number found and list key details for each.

            Content:
            \(content.prefix(50000))
            """)
    }

    /// Streams the agent's parsing process
    func streamParsing(from content: String) -> AsyncThrowingStream<AgentEvent, Error> {
        return agent.stream("""
            Parse the following content and extract all job postings.
            Report the total number found and list key details for each.

            Content:
            \(content.prefix(50000))
            """)
    }
}

// MARK: - Hybrid Parser

/// Combines fast deterministic parsing with agent fallback for complex cases
actor HybridJobParser {
    private let deterministicParser: DeterministicTableParser
    private var agent: JobScoutAgent?
    private let provider: (any InferenceProvider)?

    init(provider: (any InferenceProvider)? = nil) {
        self.deterministicParser = DeterministicTableParser()
        self.provider = provider
        self.agent = nil
    }

    /// Parses job postings, using deterministic parsing first with agent fallback
    func parse(content: String) async throws -> [JobPosting] {
        // Try deterministic parsing first (fast, no API cost)
        let jobs = deterministicParser.parseJobPostings(from: content)

        // If we found jobs, return them
        if !jobs.isEmpty {
            return jobs
        }

        // If no provider configured, can't use agent fallback
        guard let provider = provider else {
            return []
        }

        // Initialize agent lazily
        if agent == nil {
            agent = try JobScoutAgent(provider: provider)
        }

        // TODO: Parse agent result to extract jobs
        // For now, return empty - agent provides analysis but structured extraction
        // would require parsing the agent's text output
        let _ = try await agent?.parseJobPostings(from: content)

        // Re-try deterministic parsing in case agent output helps
        return deterministicParser.parseJobPostings(from: content)
    }

    /// Returns parsing statistics
    func analyzeContent(_ content: String) -> ContentAnalysis {
        let format = deterministicParser.detectFormat(content)
        let tables = deterministicParser.parseTables(content)
        let jobs = deterministicParser.extractJobs(from: tables)

        return ContentAnalysis(
            format: format,
            tableCount: tables.count,
            totalRows: tables.reduce(0) { $0 + $1.rowCount },
            jobCount: jobs.count,
            headers: tables.first?.headers ?? []
        )
    }
}

/// Analysis result for content
nonisolated struct ContentAnalysis: Sendable {
    let format: TableFormat
    let tableCount: Int
    let totalRows: Int
    let jobCount: Int
    let headers: [String]
}
