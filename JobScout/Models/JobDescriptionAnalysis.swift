//
//  JobDescriptionAnalysis.swift
//  JobScout
//
//  Created by Ilia Sazonov on 12/30/25.
//

import Foundation
import GRDB

// MARK: - Salary Information

/// Represents extracted salary information
struct SalaryInfo: Codable, Sendable, Equatable {
    let min: Int?
    let max: Int?
    let currency: String
    let period: SalaryPeriod

    enum SalaryPeriod: String, Codable, Sendable, CaseIterable {
        case hourly
        case weekly
        case monthly
        case yearly

        var abbreviation: String {
            switch self {
            case .hourly: return "/hr"
            case .weekly: return "/wk"
            case .monthly: return "/mo"
            case .yearly: return "/yr"
            }
        }
    }

    /// Format salary for display (e.g., "$150k - $200k/yr" or "$75/hr")
    var displayString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 0

        // For yearly salaries >= 1000, show in K format
        let useKFormat = period == .yearly && (min ?? 0) >= 1000

        func format(_ value: Int) -> String {
            if useKFormat {
                let kValue = Double(value) / 1000.0
                if kValue == floor(kValue) {
                    return "$\(Int(kValue))k"
                } else {
                    return String(format: "$%.0fk", kValue)
                }
            } else {
                return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
            }
        }

        if let minVal = min, let maxVal = max {
            return "\(format(minVal)) - \(format(maxVal))\(period.abbreviation)"
        } else if let minVal = min {
            return "\(format(minVal))+\(period.abbreviation)"
        } else if let maxVal = max {
            return "Up to \(format(maxVal))\(period.abbreviation)"
        } else {
            return "Not specified"
        }
    }
}

// MARK: - Stock Compensation

/// Represents stock compensation information
struct StockInfo: Codable, Sendable, Equatable {
    let hasStock: Bool
    let type: StockType?
    let details: String?

    enum StockType: String, Codable, Sendable, CaseIterable {
        case rsu = "RSU"
        case options = "Options"
        case espp = "ESPP"
        case equity = "Equity"

        var displayName: String {
            switch self {
            case .rsu: return "RSU"
            case .options: return "Stock Options"
            case .espp: return "ESPP"
            case .equity: return "Equity"
            }
        }
    }
}

// MARK: - Technology/Skills

/// Represents a technology or skill extracted from a job description
struct JobTechnology: Codable, Sendable, Identifiable, Equatable, Hashable {
    let id: Int?
    let technology: String
    let category: TechnologyCategory?
    let isRequired: Bool

    enum TechnologyCategory: String, Codable, Sendable, CaseIterable {
        case language = "Language"
        case framework = "Framework"
        case database = "Database"
        case cloud = "Cloud"
        case tool = "Tool"
        case platform = "Platform"
        case methodology = "Methodology"
        case other = "Other"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(technology.lowercased())
    }

    static func == (lhs: JobTechnology, rhs: JobTechnology) -> Bool {
        lhs.technology.lowercased() == rhs.technology.lowercased()
    }
}

// MARK: - Analysis Status

/// Status of job description analysis
enum AnalysisStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case processing
    case completed
    case failed

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .processing: return "Processing"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }
}

// MARK: - Complete Analysis Result

/// Complete analysis result for a job posting
struct JobAnalysisResult: Codable, Sendable {
    let jobId: Int
    let salary: SalaryInfo?
    let stock: StockInfo?
    let technologies: [JobTechnology]
    let summary: String?
    let analyzedAt: Date

    var hasSalary: Bool { salary != nil }
    var hasStock: Bool { stock?.hasStock == true }
    var hasTechnologies: Bool { !technologies.isEmpty }
    var hasSummary: Bool { summary != nil && !summary!.isEmpty }
}

// MARK: - LLM Output Structure

/// Structure for parsing LLM JSON output
struct JobDescriptionAnalysisOutput: Codable, Sendable {
    let technologies: [ExtractedTechnology]
    let salary: ExtractedSalary?
    let stock: ExtractedStock?
    let summary: String?

    struct ExtractedTechnology: Codable, Sendable {
        let name: String
        let category: String?
        let required: Bool
    }

    struct ExtractedSalary: Codable, Sendable {
        let min: Int?
        let max: Int?
        let currency: String
        let period: String
    }

    struct ExtractedStock: Codable, Sendable {
        let hasStock: Bool
        let type: String?
        let details: String?
    }

    /// Convert to domain models
    func toJobAnalysisResult(jobId: Int) -> JobAnalysisResult {
        let salaryInfo: SalaryInfo? = salary.map { s in
            SalaryInfo(
                min: s.min,
                max: s.max,
                currency: s.currency,
                period: SalaryInfo.SalaryPeriod(rawValue: s.period.lowercased()) ?? .yearly
            )
        }

        let stockInfo: StockInfo? = stock.map { s in
            StockInfo(
                hasStock: s.hasStock,
                type: s.type.flatMap { StockInfo.StockType(rawValue: $0) },
                details: s.details
            )
        }

        let techs = technologies.map { t in
            JobTechnology(
                id: nil,
                technology: t.name,
                category: t.category.flatMap { JobTechnology.TechnologyCategory(rawValue: $0) },
                isRequired: t.required
            )
        }

        return JobAnalysisResult(
            jobId: jobId,
            salary: salaryInfo,
            stock: stockInfo,
            technologies: techs,
            summary: summary,
            analyzedAt: Date()
        )
    }
}

// MARK: - Persisted Models

/// Database model for job_description_analysis table
struct PersistedJobAnalysis: Identifiable, Sendable {
    let id: Int
    var jobId: Int
    var salaryMin: Int?
    var salaryMax: Int?
    var salaryCurrency: String?
    var salaryPeriod: String?
    var hasStockCompensation: Bool
    var stockType: String?
    var stockDetails: String?
    var jobSummary: String?
    let createdAt: Date
    var updatedAt: Date

    /// Convert to SalaryInfo
    var salaryInfo: SalaryInfo? {
        guard salaryMin != nil || salaryMax != nil else { return nil }
        return SalaryInfo(
            min: salaryMin,
            max: salaryMax,
            currency: salaryCurrency ?? "USD",
            period: SalaryInfo.SalaryPeriod(rawValue: salaryPeriod ?? "yearly") ?? .yearly
        )
    }

    /// Convert to StockInfo
    var stockInfo: StockInfo? {
        StockInfo(
            hasStock: hasStockCompensation,
            type: stockType.flatMap { StockInfo.StockType(rawValue: $0) },
            details: stockDetails
        )
    }

    /// Create from database row
    static func from(row: Row) -> PersistedJobAnalysis {
        PersistedJobAnalysis(
            id: row["id"],
            jobId: row["job_id"],
            salaryMin: row["salary_min"],
            salaryMax: row["salary_max"],
            salaryCurrency: row["salary_currency"],
            salaryPeriod: row["salary_period"],
            hasStockCompensation: row["has_stock_compensation"] == 1,
            stockType: row["stock_type"],
            stockDetails: row["stock_details"],
            jobSummary: row["job_summary"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }
}

/// Database model for job_technologies table
struct PersistedJobTechnology: Identifiable, Sendable {
    let id: Int
    var jobId: Int
    var technology: String
    var category: String?
    var isRequired: Bool
    let createdAt: Date

    /// Convert to JobTechnology
    func toJobTechnology() -> JobTechnology {
        JobTechnology(
            id: id,
            technology: technology,
            category: category.flatMap { JobTechnology.TechnologyCategory(rawValue: $0) },
            isRequired: isRequired
        )
    }

    /// Create from database row
    static func from(row: Row) -> PersistedJobTechnology {
        PersistedJobTechnology(
            id: row["id"],
            jobId: row["job_id"],
            technology: row["technology"],
            category: row["category"],
            isRequired: row["is_required"] == 1,
            createdAt: row["created_at"]
        )
    }
}
