//
//  DataHarmonizer.swift
//  JobScout
//
//  Created by Ilia Sazonov on 12/29/25.
//

import Foundation
import SwiftAgents
import Logging

private let log = JobScoutLogger.harmonization

/// Result of harmonization including any errors
struct HarmonizationResult: Sendable {
    let jobs: [JobPosting]
    let inferredCategory: String
    let errors: [String]
}

/// Orchestrates data harmonization by combining multiple analyzers
actor DataHarmonizer {
    private let dateNormalizer: DateNormalizer
    private var contentAnalyzer: ContentAnalyzerAgent?
    private let keychainService = KeychainService.shared

    init() {
        self.dateNormalizer = DateNormalizer()
        self.contentAnalyzer = nil
        log.debug("DataHarmonizer initialized (API key will be loaded on first harmonize)")
    }

    /// Initialize with a specific inference provider
    init(provider: any InferenceProvider) {
        self.dateNormalizer = DateNormalizer()
        self.contentAnalyzer = ContentAnalyzerAgent(provider: provider)
        log.debug("DataHarmonizer initialized with custom provider")
    }

    /// Initialize with an OpenRouter API key
    init(apiKey: String) throws {
        self.dateNormalizer = DateNormalizer()
        self.contentAnalyzer = try ContentAnalyzerAgent(apiKey: apiKey)
        log.debug("DataHarmonizer initialized with API key")
    }

    /// Harmonize jobs extracted from a page
    /// - Parameters:
    ///   - jobs: Raw job postings from parser
    ///   - pageTitle: Title of the source page
    ///   - pageURL: URL of the source page
    ///   - pageDescription: Optional description or first heading
    /// - Returns: HarmonizationResult with harmonized jobs and metadata
    func harmonize(
        jobs: [JobPosting],
        pageTitle: String,
        pageURL: String,
        pageDescription: String? = nil
    ) async -> HarmonizationResult {
        log.info("Starting harmonization for \(jobs.count) jobs", metadata: [
            "pageTitle": "\(pageTitle)",
            "pageURL": "\(pageURL)"
        ])

        var errors: [String] = []
        var inferredCategory = "Other"

        // Try to initialize content analyzer if not already done
        if contentAnalyzer == nil {
            log.debug("Content analyzer not initialized, attempting to initialize")
            await initializeContentAnalyzer()
        }

        // Step 1: Analyze page content for category inference
        var contentMetadata: ContentMetadata?
        if let analyzer = contentAnalyzer {
            log.debug("Using LLM-based content analysis")
            do {
                contentMetadata = try await analyzer.analyze(
                    pageTitle: pageTitle,
                    pageURL: pageURL,
                    pageDescription: pageDescription,
                    sampleHeaders: extractSampleHeaders(from: jobs)
                )
                inferredCategory = contentMetadata?.inferredCategory.rawValue ?? "Other"
                log.info("LLM analysis succeeded", metadata: [
                    "inferredCategory": "\(inferredCategory)",
                    "confidence": "\(contentMetadata?.confidence ?? 0)"
                ])
            } catch {
                log.error("Content analysis failed: \(error)")
                errors.append("Content analysis failed: \(error.localizedDescription)")
                // Fall back to deterministic category inference
                inferredCategory = JobCategory.infer(from: pageTitle).rawValue
                log.info("Falling back to deterministic inference", metadata: [
                    "inferredCategory": "\(inferredCategory)"
                ])
            }
        } else {
            // No API key - use deterministic inference
            log.debug("No content analyzer available, using deterministic inference")
            inferredCategory = JobCategory.infer(from: pageTitle).rawValue
            log.info("Deterministic inference result", metadata: [
                "inferredCategory": "\(inferredCategory)"
            ])
        }

        // Step 2: Harmonize each job
        log.debug("Harmonizing \(jobs.count) individual jobs")
        let harmonizedJobs = jobs.map { job -> JobPosting in
            harmonizeJob(
                job,
                inferredCategory: inferredCategory,
                contentMetadata: contentMetadata
            )
        }

        // Log sample of harmonization results
        if let first = jobs.first, let harmonizedFirst = harmonizedJobs.first {
            log.debug("Sample harmonization", metadata: [
                "originalCategory": "\(first.category)",
                "harmonizedCategory": "\(harmonizedFirst.category)",
                "originalDate": "\(first.datePosted ?? "nil")",
                "harmonizedDate": "\(harmonizedFirst.datePosted ?? "nil")"
            ])
        }

        log.info("Harmonization complete", metadata: [
            "jobCount": "\(harmonizedJobs.count)",
            "errorCount": "\(errors.count)"
        ])

        return HarmonizationResult(
            jobs: harmonizedJobs,
            inferredCategory: inferredCategory,
            errors: errors
        )
    }

    /// Harmonize a single job posting
    private func harmonizeJob(
        _ job: JobPosting,
        inferredCategory: String,
        contentMetadata: ContentMetadata?
    ) -> JobPosting {
        // Normalize date
        var normalizedDate: String? = job.datePosted
        if let dateStr = job.datePosted {
            let normalized = dateNormalizer.normalize(dateStr)
            if normalized != nil && normalized != dateStr {
                log.trace("Date normalized", metadata: [
                    "original": "\(dateStr)",
                    "normalized": "\(normalized ?? "nil")"
                ])
            }
            normalizedDate = normalized ?? dateStr
        }

        // Re-classify links using LinkClassifier
        var companyWebsite = job.companyWebsite
        var companyLink = job.companyLink
        var aggregatorLink = job.aggregatorLink
        var aggregatorName = job.aggregatorName

        // If we have a company link, verify it's not actually an aggregator
        if let link = companyLink {
            let classification = LinkClassifier.classify(link)
            if case .aggregator(let name) = classification {
                log.trace("Reclassified company link as aggregator", metadata: [
                    "link": "\(link)",
                    "aggregator": "\(name)"
                ])
                // Move to aggregator
                if aggregatorLink == nil {
                    aggregatorLink = link
                    aggregatorName = name
                }
                companyLink = nil
            } else if LinkClassifier.isCompanyHomepage(link) {
                // This is a company homepage, not a job posting
                log.trace("Company link is a homepage, moving to companyWebsite", metadata: [
                    "link": "\(link)"
                ])
                if companyWebsite == nil {
                    companyWebsite = link
                }
                companyLink = nil
            }
        }

        // If the page source is an aggregator, the company link might actually be correct
        // but we should note the source aggregator
        if let metadata = contentMetadata, metadata.isAggregatorSource {
            if aggregatorName == nil {
                aggregatorName = metadata.aggregatorName
            }
        }

        // Extract company website from company link if not already set
        if companyWebsite == nil, let link = companyLink {
            companyWebsite = LinkClassifier.extractCompanyHomepage(from: link)
        }

        // Extract company website from aggregator link if still not set
        if companyWebsite == nil, let link = aggregatorLink {
            // For aggregators, we can't extract company website directly
            // but we might have other sources in the future
        }

        // Normalize category - strip emojis first
        let normalizedJobCategory = normalizeCategory(job.category)
        let normalizedInferredCategory = normalizeCategory(inferredCategory)

        // Determine category - use inferred if current is generic
        let finalCategory: String
        let isGeneric = isGenericCategory(normalizedJobCategory)
        if normalizedJobCategory == "Other" || normalizedJobCategory.isEmpty || isGeneric {
            finalCategory = normalizedInferredCategory
            if isGeneric {
                log.trace("Replacing generic category", metadata: [
                    "original": "\(job.category)",
                    "normalized": "\(normalizedJobCategory)",
                    "replacement": "\(normalizedInferredCategory)"
                ])
            }
        } else {
            finalCategory = normalizedJobCategory
        }

        return JobPosting(
            company: job.company,
            role: job.role,
            location: job.location,
            country: job.country,
            category: finalCategory,
            companyWebsite: companyWebsite,
            companyLink: companyLink,
            aggregatorLink: aggregatorLink,
            aggregatorName: aggregatorName,
            datePosted: normalizedDate,
            notes: job.notes,
            isFAANG: job.isFAANG,
            isInternship: job.isInternship
        )
    }

    /// Check if a category is too generic and should be replaced
    private func isGenericCategory(_ category: String) -> Bool {
        let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        let lowercased = trimmed.lowercased()

        // Exact matches
        let genericExact = [
            "daily list",
            "new jobs",
            "jobs",
            "listings",
            "opportunities",
            "positions",
            "all jobs",
            "other",
            "see full",
            "see more",
            "view all"
        ]

        if genericExact.contains(lowercased) {
            return true
        }

        // Partial matches - category contains these generic terms
        let genericPatterns = [
            "daily",
            "list",
            "new grad",
            "newgrad",
            "intern",  // But handled separately by isInternship
            "2024",
            "2025",
            "fall",
            "spring",
            "summer",
            "winter"
        ]

        for pattern in genericPatterns {
            if lowercased.contains(pattern) {
                return true
            }
        }

        return false
    }

    /// Strip emojis and normalize a category string
    private func normalizeCategory(_ category: String) -> String {
        // Remove emojis and other symbols
        let stripped = category.unicodeScalars.filter { scalar in
            // Keep letters, numbers, spaces, punctuation
            CharacterSet.letters.contains(scalar) ||
            CharacterSet.decimalDigits.contains(scalar) ||
            CharacterSet.whitespaces.contains(scalar) ||
            CharacterSet.punctuationCharacters.contains(scalar)
        }
        let cleaned = String(String.UnicodeScalarView(stripped))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Collapse multiple spaces
        let components = cleaned.components(separatedBy: .whitespaces)
        let normalized = components.filter { !$0.isEmpty }.joined(separator: " ")

        return normalized.isEmpty ? "Other" : normalized
    }

    /// Extract sample headers from jobs for context
    private func extractSampleHeaders(from jobs: [JobPosting]) -> [String] {
        guard let firstJob = jobs.first else { return [] }
        return ["Company", "Role", "Location", firstJob.category]
    }

    /// Initialize content analyzer with stored API key
    private func initializeContentAnalyzer() async {
        // Check if harmonization is enabled (default to true if not explicitly set)
        let harmonizationSet = UserDefaults.standard.object(forKey: "enableHarmonization") != nil
        let enabled = harmonizationSet ? UserDefaults.standard.bool(forKey: "enableHarmonization") : true

        guard enabled else {
            log.info("Harmonization is disabled in settings")
            return
        }

        log.debug("Harmonization enabled, checking for API key...")

        // Try to get API key from keychain
        do {
            if let apiKey = try await keychainService.getOpenRouterAPIKey() {
                let maskedKey = String(apiKey.prefix(8)) + "..." + String(apiKey.suffix(4))
                log.debug("Retrieved API key from keychain: \(maskedKey)")
                contentAnalyzer = try ContentAnalyzerAgent(apiKey: apiKey)
                log.info("Content analyzer initialized successfully")
            } else {
                log.warning("No API key found in keychain - please add one in Settings (⌘,)")
            }
        } catch {
            log.error("Failed to initialize content analyzer: \(error)")
            // No API key stored or error - continue without LLM
        }
    }

    // MARK: - Convenience Methods

    /// Quick harmonization without page context (deterministic only)
    func harmonizeDeterministic(_ jobs: [JobPosting]) -> [JobPosting] {
        jobs.map { job in
            // Normalize date
            var normalizedDate: String? = job.datePosted
            if let dateStr = job.datePosted {
                normalizedDate = dateNormalizer.normalize(dateStr) ?? dateStr
            }

            // Re-classify links
            var companyWebsite = job.companyWebsite
            var companyLink = job.companyLink
            var aggregatorLink = job.aggregatorLink
            var aggregatorName = job.aggregatorName

            if let link = companyLink {
                let classification = LinkClassifier.classify(link)
                if case .aggregator(let name) = classification {
                    if aggregatorLink == nil {
                        aggregatorLink = link
                        aggregatorName = name
                    }
                    companyLink = nil
                } else if LinkClassifier.isCompanyHomepage(link) {
                    if companyWebsite == nil {
                        companyWebsite = link
                    }
                    companyLink = nil
                }
            }

            // Extract company website from company link if not already set
            if companyWebsite == nil, let link = companyLink {
                companyWebsite = LinkClassifier.extractCompanyHomepage(from: link)
            }

            // Normalize category
            let normalizedCategory = normalizeCategory(job.category)
            let finalCategory = isGenericCategory(normalizedCategory) ? "Other" : normalizedCategory

            return JobPosting(
                company: job.company,
                role: job.role,
                location: job.location,
                country: job.country,
                category: finalCategory,
                companyWebsite: companyWebsite,
                companyLink: companyLink,
                aggregatorLink: aggregatorLink,
                aggregatorName: aggregatorName,
                datePosted: normalizedDate,
                notes: job.notes,
                isFAANG: job.isFAANG,
                isInternship: job.isInternship
            )
        }
    }

    /// Normalize a single date string
    func normalizeDate(_ dateString: String) -> String? {
        dateNormalizer.normalize(dateString)
    }

    /// Classify a single URL
    func classifyLink(_ url: String) -> LinkClassification {
        LinkClassifier.classify(url)
    }
}
