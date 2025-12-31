//
//  TechStackExtractorAgent.swift
//  JobScout
//
//  Created by Ilia Sazonov on 12/30/25.
//

import Foundation
import SwiftAgents
import Logging

private let log = Logger(label: "JobScout.TechStackExtractorAgent")

/// Agent specialized in extracting technology stack from job descriptions
actor TechStackExtractorAgent {
    private let provider: any InferenceProvider

    init(provider: any InferenceProvider) {
        self.provider = provider
    }

    /// Extract technologies from job description
    func extract(from description: String, role: String, company: String, jobId: Int) async throws -> [JobDescriptionAnalysisOutput.ExtractedTechnology] {
        log.info("[\(jobId)] Extracting tech stack for \(role) at \(company)")

        // Truncate if too long
        let maxChars = 6000
        let truncatedDesc = description.count > maxChars ? String(description.prefix(maxChars)) + "..." : description

        let prompt = """
        You are a technical recruiter expert. Analyze this job description and extract ALL technologies, tools, platforms, languages, frameworks, and technical skills mentioned.

        Job Title: \(role)
        Company: \(company)

        Job Description:
        \(truncatedDesc)

        INSTRUCTIONS:
        1. Extract EVERY technology, programming language, framework, database, cloud platform, tool, methodology, or technical concept mentioned in the job description.
        2. Include vendor-specific products (e.g., "Oracle EBS", "SAP", "Salesforce", "ServiceNow").
        3. Include database languages and tools (e.g., "PL/SQL", "T-SQL", "HQL").
        4. Include ERP systems, CRM systems, and enterprise software.
        5. Include development methodologies (e.g., "Agile", "Scrum", "DevOps", "CI/CD").
        6. Include cloud services and platforms (e.g., "AWS Lambda", "Azure Functions", "GCP BigQuery").
        7. Include testing frameworks and tools.
        8. Include version control and collaboration tools.
        9. DO NOT limit yourself to common technologies - extract everything technical.
        10. Mark technologies as "required" if they appear in required qualifications or are described as "must have", "required", "essential".
        11. Mark technologies as NOT required if they appear in "nice to have", "preferred", or "bonus" sections.

        Categorize each technology into one of these categories:
        - Language: Programming languages (Python, Java, PL/SQL, JavaScript, etc.)
        - Framework: Application frameworks (React, Spring, Django, .NET, etc.)
        - Database: Databases and data stores (Oracle, PostgreSQL, MongoDB, Redis, etc.)
        - Cloud: Cloud platforms and services (AWS, Azure, GCP, their specific services)
        - Platform: Enterprise platforms and systems (Oracle EBS, SAP, Salesforce, ServiceNow, etc.)
        - Tool: Development and operations tools (Git, Docker, Jenkins, Terraform, etc.)
        - Methodology: Development practices (Agile, Scrum, DevOps, TDD, etc.)
        - Other: Anything that doesn't fit above categories

        Respond with ONLY a valid JSON array (no markdown, no explanation):
        [
            {"name": "Oracle EBS", "category": "Platform", "required": true},
            {"name": "PL/SQL", "category": "Language", "required": true},
            {"name": "Python", "category": "Language", "required": false}
        ]

        If no technologies are found, return an empty array: []
        """

        do {
            let response = try await provider.generate(prompt: prompt, options: .init(temperature: 0.0))

            if let technologies = parseResponse(response, jobId: jobId) {
                log.info("[\(jobId)] Extracted \(technologies.count) technologies")
                return technologies
            } else {
                log.warning("[\(jobId)] Failed to parse tech stack response")
                return []
            }
        } catch {
            log.error("[\(jobId)] Tech stack extraction failed: \(error)")
            return []
        }
    }

    private func parseResponse(_ response: String, jobId: Int) -> [JobDescriptionAnalysisOutput.ExtractedTechnology]? {
        var jsonString = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove markdown code blocks if present
        if jsonString.hasPrefix("```json") {
            jsonString = String(jsonString.dropFirst(7))
        } else if jsonString.hasPrefix("```") {
            jsonString = String(jsonString.dropFirst(3))
        }
        if jsonString.hasSuffix("```") {
            jsonString = String(jsonString.dropLast(3))
        }
        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = jsonString.data(using: .utf8) else {
            log.error("[\(jobId)] Tech stack response is not valid UTF-8")
            return nil
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode([JobDescriptionAnalysisOutput.ExtractedTechnology].self, from: data)
        } catch {
            log.error("[\(jobId)] JSON parsing error for tech stack: \(error)")
            log.debug("[\(jobId)] Raw response: \(jsonString.prefix(500))")
            return nil
        }
    }
}
