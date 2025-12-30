//
//  ContentAnalyzerAgent.swift
//  JobScout
//
//  Created by Ilia Sazonov on 12/29/25.
//

import Foundation
import SwiftAgents
import Logging

private let log = JobScoutLogger.api

/// Metadata extracted from page content analysis
struct ContentMetadata: Sendable {
    /// Inferred job category from fixed taxonomy
    let inferredCategory: JobCategory
    /// True if the source itself is an aggregator site
    let isAggregatorSource: Bool
    /// Name of the aggregator if source is an aggregator
    let aggregatorName: String?
    /// Confidence level (0.0-1.0)
    let confidence: Double
}

/// Agent that uses LLM to analyze page content and extract metadata
actor ContentAnalyzerAgent {
    private let provider: any InferenceProvider

    init(provider: any InferenceProvider) {
        self.provider = provider
        log.debug("ContentAnalyzerAgent initialized with custom provider")
    }

    /// Convenience initializer with OpenRouter API key
    init(apiKey: String) throws {
        let config = try OpenRouterConfiguration(
            apiKey: apiKey,
            model: .init(stringLiteral: "anthropic/claude-sonnet-4.5"),
            maxTokens: 1024
        )
        self.provider = OpenRouterProvider(configuration: config)
      log.debug("ContentAnalyzerAgent initialized with OpenRouter (model: \(config.model)")
    }

    /// Analyze page content to extract metadata
    /// - Parameters:
    ///   - pageTitle: The title of the page
    ///   - pageURL: The URL of the page
    ///   - pageDescription: Optional description or first heading
    ///   - sampleHeaders: Sample table headers from the page
    /// - Returns: ContentMetadata with inferred information
    func analyze(
        pageTitle: String,
        pageURL: String,
        pageDescription: String? = nil,
        sampleHeaders: [String] = []
    ) async throws -> ContentMetadata {
        log.info("Analyzing page content", metadata: [
            "pageTitle": "\(pageTitle)",
            "pageURL": "\(pageURL)"
        ])

        // First, do deterministic analysis
        let deterministicResult = analyzeDeterministically(
            pageTitle: pageTitle,
            pageURL: pageURL,
            pageDescription: pageDescription,
            sampleHeaders: sampleHeaders
        )

        log.debug("Deterministic analysis result", metadata: [
            "category": "\(deterministicResult.inferredCategory.rawValue)",
            "confidence": "\(deterministicResult.confidence)",
            "isAggregator": "\(deterministicResult.isAggregatorSource)"
        ])

        // If we have high confidence from deterministic analysis, use it
        if deterministicResult.confidence > 0.8 {
            log.info("Using deterministic result (high confidence)")
            return deterministicResult
        }

        // Otherwise, use LLM for better inference
        log.info("Confidence too low, using LLM for better inference")
        return try await analyzeWithLLM(
            pageTitle: pageTitle,
            pageURL: pageURL,
            pageDescription: pageDescription,
            sampleHeaders: sampleHeaders,
            fallback: deterministicResult
        )
    }

    // MARK: - Deterministic Analysis

    /// Analyze using deterministic rules (no LLM)
    private func analyzeDeterministically(
        pageTitle: String,
        pageURL: String,
        pageDescription: String?,
        sampleHeaders: [String]
    ) -> ContentMetadata {
        // Check if source is an aggregator
        let isAggregator = LinkClassifier.isAggregator(pageURL)
        let aggregatorName = LinkClassifier.aggregatorName(from: pageURL)

        // Infer category from title and description
        let textToAnalyze = [pageTitle, pageDescription ?? ""].joined(separator: " ")
        let category = JobCategory.infer(from: textToAnalyze)

        // Calculate confidence based on signals
        var confidence = 0.5

        // Higher confidence if we found a specific category
        if category != .other {
            confidence += 0.2
        }

        // Higher confidence for known aggregators
        if isAggregator {
            confidence += 0.1
        }

        // Higher confidence if title contains job-related keywords
        let jobKeywords = ["job", "career", "hiring", "position", "opportunity", "engineer", "developer", "internship", "new grad"]
        let lowercasedTitle = pageTitle.lowercased()
        if jobKeywords.contains(where: { lowercasedTitle.contains($0) }) {
            confidence += 0.1
        }

        return ContentMetadata(
            inferredCategory: category,
            isAggregatorSource: isAggregator,
            aggregatorName: aggregatorName,
            confidence: min(confidence, 1.0)
        )
    }

    // MARK: - LLM Analysis

    /// Analyze using LLM for better inference
    private func analyzeWithLLM(
        pageTitle: String,
        pageURL: String,
        pageDescription: String?,
        sampleHeaders: [String],
        fallback: ContentMetadata
    ) async throws -> ContentMetadata {
        let prompt = buildPrompt(
            pageTitle: pageTitle,
            pageURL: pageURL,
            pageDescription: pageDescription,
            sampleHeaders: sampleHeaders
        )

        log.debug("Sending prompt to LLM", metadata: [
            "promptLength": "\(prompt.count)"
        ])

        let response: String
        do {
            response = try await provider.generate(prompt: prompt, options: InferenceOptions(
                temperature: 0.0,  // Deterministic output
                maxTokens: 200
            ))
            log.debug("LLM response received", metadata: [
                "responseLength": "\(response.count)",
                "response": "\(response.prefix(200))"
            ])
        } catch {
            log.error("LLM generation failed", metadata: [
                "error": "\(error)",
                "errorType": "\(type(of: error))"
            ])
            throw error
        }

        // Parse the response
        let result = parseResponse(response, fallback: fallback)
        log.info("LLM analysis complete", metadata: [
            "category": "\(result.inferredCategory.rawValue)",
            "confidence": "\(result.confidence)"
        ])
        return result
    }

    private func buildPrompt(
        pageTitle: String,
        pageURL: String,
        pageDescription: String?,
        sampleHeaders: [String]
    ) -> String {
        let categoriesList = JobCategory.allCases.map { $0.rawValue }.joined(separator: ", ")

        return """
        Analyze this job listing page and respond with ONLY a JSON object (no explanation):

        Page Title: \(pageTitle)
        URL: \(pageURL)
        Description: \(pageDescription ?? "N/A")
        Table Headers: \(sampleHeaders.isEmpty ? "N/A" : sampleHeaders.joined(separator: ", "))

        Respond with this exact JSON format:
        {"category": "<one of: \(categoriesList)>", "is_aggregator": <true or false>, "confidence": <0.0-1.0>}

        Choose the most specific category that applies. Default to "Software Engineering" for general tech job listings.
        Set is_aggregator to true if this is a job aggregator site (like LinkedIn, Indeed, Glassdoor, Simplify, Jobright).
        """
    }

    private func parseResponse(_ response: String, fallback: ContentMetadata) -> ContentMetadata {
        // Try to extract JSON from response
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Find JSON in the response
        guard let jsonStart = trimmed.firstIndex(of: "{"),
              let jsonEnd = trimmed.lastIndex(of: "}") else {
            return fallback
        }

        let jsonString = String(trimmed[jsonStart...jsonEnd])

        guard let data = jsonString.data(using: .utf8) else {
            return fallback
        }

        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let categoryString = json["category"] as? String ?? "Other"
                let isAggregator = json["is_aggregator"] as? Bool ?? fallback.isAggregatorSource
                let confidence = json["confidence"] as? Double ?? 0.7

                // Find matching category
                let category = JobCategory.allCases.first {
                    $0.rawValue.lowercased() == categoryString.lowercased()
                } ?? .other

                return ContentMetadata(
                    inferredCategory: category,
                    isAggregatorSource: isAggregator,
                    aggregatorName: isAggregator ? fallback.aggregatorName : nil,
                    confidence: confidence
                )
            }
        } catch {
            // JSON parsing failed, use fallback
        }

        return fallback
    }
}
