//
//  JobDescriptionAnalyzerAgent.swift
//  JobScout
//
//  Created by Ilia Sazonov on 12/30/25.
//

import Foundation
import SwiftAgents
import Logging

private let log = Logger(label: "JobScout.JobDescriptionAnalyzerAgent")

/// Orchestrator agent that coordinates tech stack and compensation extraction
actor JobDescriptionAnalyzerAgent {
    private let provider: any InferenceProvider
    private let techStackAgent: TechStackExtractorAgent
    private let compensationAgent: CompensationExtractorAgent

    init(provider: any InferenceProvider) {
        self.provider = provider
        self.techStackAgent = TechStackExtractorAgent(provider: provider)
        self.compensationAgent = CompensationExtractorAgent(provider: provider)
        log.debug("JobDescriptionAnalyzerAgent initialized with custom provider")
    }

    init(apiKey: String) throws {
        let config = try OpenRouterConfiguration(
            apiKey: apiKey,
            model: .init(stringLiteral: "anthropic/claude-sonnet-4"),
            maxTokens: 2048
        )
        self.provider = OpenRouterProvider(configuration: config)
        self.techStackAgent = TechStackExtractorAgent(provider: self.provider)
        self.compensationAgent = CompensationExtractorAgent(provider: self.provider)
        log.debug("JobDescriptionAnalyzerAgent initialized with API key")
    }

    /// Analyze job description and extract structured data using specialized agents
    func analyze(description: String, role: String, company: String, jobId: Int) async throws -> JobDescriptionAnalysisOutput {
        log.info("[\(jobId)] Starting analysis for \(role) at \(company)")

        // Run both extractions concurrently for efficiency
        async let techTask = techStackAgent.extract(from: description, role: role, company: company, jobId: jobId)
        async let compTask = compensationAgent.extract(from: description, role: role, company: company, jobId: jobId)

        let technologies = try await techTask
        let compensation = try await compTask

        log.info("[\(jobId)] Analysis complete - technologies: \(technologies.count), salary: \(compensation.salary != nil), stock: \(compensation.stock != nil)")

        return JobDescriptionAnalysisOutput(
            technologies: technologies,
            salary: compensation.salary,
            stock: compensation.stock,
            summary: compensation.summary
        )
    }
}
