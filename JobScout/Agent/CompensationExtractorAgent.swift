//
//  CompensationExtractorAgent.swift
//  JobScout
//
//  Created by Ilia Sazonov on 12/30/25.
//

import Foundation
import SwiftAgents
import Logging

private let log = Logger(label: "JobScout.CompensationExtractorAgent")

/// Output structure for compensation extraction
struct CompensationExtractionResult: Codable {
    let salary: JobDescriptionAnalysisOutput.ExtractedSalary?
    let stock: JobDescriptionAnalysisOutput.ExtractedStock?
    let summary: String?
}

/// Agent specialized in extracting compensation details and job summary
actor CompensationExtractorAgent {
    private let provider: any InferenceProvider

    init(provider: any InferenceProvider) {
        self.provider = provider
    }

    /// Extract compensation info and summary from job description
    func extract(from description: String, role: String, company: String, jobId: Int) async throws -> CompensationExtractionResult {
        log.info("[\(jobId)] Extracting compensation for \(role) at \(company)")

        // Truncate if too long
        let maxChars = 6000
        let truncatedDesc = description.count > maxChars ? String(description.prefix(maxChars)) + "..." : description

        let prompt = """
        You are a compensation analyst expert. Analyze this job description and extract salary information, stock/equity compensation details, and provide a brief summary.

        Job Title: \(role)
        Company: \(company)

        Job Description:
        \(truncatedDesc)

        INSTRUCTIONS:

        1. SALARY EXTRACTION:
           - Look for salary ranges in any format: "$150,000 - $200,000", "$150K-200K", "$75/hour", etc.
           - Extract both minimum and maximum if a range is provided.
           - If only one number is given, use it for both min and max.
           - Identify the currency (default to USD if not specified).
           - Identify the period: "yearly" (annual), "monthly", "weekly", or "hourly".
           - Convert all salaries to their numeric values (e.g., "150K" = 150000).
           - Look for salary info in compensation sections, pay ranges, benefits sections.

        2. STOCK/EQUITY EXTRACTION:
           - Look for mentions of: RSU, restricted stock units, stock options, ESPP, employee stock purchase, equity grants, shares, stock compensation.
           - Identify the type: "RSU", "Options", "ESPP", or "Equity" (generic).
           - Extract any vesting details or specific terms mentioned.
           - Set hasStock to true if ANY stock/equity compensation is mentioned.

        3. JOB SUMMARY:
           - Write a concise 2-3 sentence summary of the role.
           - Focus on: main responsibilities, team/department, and key qualifications.
           - Be specific and informative, not generic.

        Respond with ONLY a valid JSON object (no markdown, no explanation):
        {
            "salary": {
                "min": 150000,
                "max": 200000,
                "currency": "USD",
                "period": "yearly"
            },
            "stock": {
                "hasStock": true,
                "type": "RSU",
                "details": "Equity package with 4-year vesting"
            },
            "summary": "This is a Senior Software Engineer role focused on building scalable backend systems. The position requires 5+ years of experience and involves leading technical projects within the platform team."
        }

        IMPORTANT:
        - Use null for salary if no salary information is found.
        - Use null for stock if no equity/stock compensation is mentioned.
        - Always provide a summary based on the job description.
        - For salary.period, use exactly one of: "yearly", "monthly", "weekly", "hourly"
        - For stock.type, use exactly one of: "RSU", "Options", "ESPP", "Equity", or null
        """

        do {
            let response = try await provider.generate(prompt: prompt, options: .init(temperature: 0.0))

            if let result = parseResponse(response, jobId: jobId) {
                log.info("[\(jobId)] Extracted compensation - salary: \(result.salary != nil), stock: \(result.stock != nil)")
                return result
            } else {
                log.warning("[\(jobId)] Failed to parse compensation response")
                return CompensationExtractionResult(salary: nil, stock: nil, summary: nil)
            }
        } catch {
            log.error("[\(jobId)] Compensation extraction failed: \(error)")
            return CompensationExtractionResult(salary: nil, stock: nil, summary: nil)
        }
    }

    private func parseResponse(_ response: String, jobId: Int) -> CompensationExtractionResult? {
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
            log.error("[\(jobId)] Compensation response is not valid UTF-8")
            return nil
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(CompensationExtractionResult.self, from: data)
        } catch {
            log.error("[\(jobId)] JSON parsing error for compensation: \(error)")
            log.debug("[\(jobId)] Raw response: \(jsonString.prefix(500))")
            return nil
        }
    }
}
