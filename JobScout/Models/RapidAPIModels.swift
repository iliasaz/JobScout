//
//  RapidAPIModels.swift
//  JobScout
//
//  Created by Claude on 1/29/26.
//

import Foundation

// MARK: - Search Parameters

/// Parameters for RapidAPI Fresh LinkedIn Scraper job search
struct RapidAPISearchParams: Sendable {
    var keyword: String  // Required search keyword
    var page: Int = 1
    var sortBy: SortBy = .relevant
    var datePosted: DatePosted?
    var geocode: String?  // Reuses ScrapingDogLocation geocode IDs
    var experienceLevel: ExperienceLevel?
    var remote: RemoteType?
    var jobType: JobType?
    var easyApply: Bool?
    var under10Applicants: Bool?
    var hasVerifications: Bool?
    var fairChanceEmployer: Bool?

    /// Sort options
    enum SortBy: String, CaseIterable, Sendable {
        case recent = "recent"
        case relevant = "relevant"

        var displayName: String {
            switch self {
            case .recent: return "Most Recent"
            case .relevant: return "Most Relevant"
            }
        }
    }

    /// Date posted filter
    enum DatePosted: String, CaseIterable, Sendable {
        case anytime = "anytime"
        case pastMonth = "past_month"
        case pastWeek = "past_week"
        case past24Hours = "past_24_hours"

        var displayName: String {
            switch self {
            case .anytime: return "Any Time"
            case .pastMonth: return "Past Month"
            case .pastWeek: return "Past Week"
            case .past24Hours: return "Past 24 Hours"
            }
        }
    }

    /// Experience level filter
    enum ExperienceLevel: String, CaseIterable, Sendable {
        case internship = "internship"
        case entryLevel = "entry_level"
        case associate = "associate"
        case midSenior = "mid_senior"
        case director = "director"
        case executive = "executive"

        var displayName: String {
            switch self {
            case .internship: return "Internship"
            case .entryLevel: return "Entry Level"
            case .associate: return "Associate"
            case .midSenior: return "Mid-Senior"
            case .director: return "Director"
            case .executive: return "Executive"
            }
        }
    }

    /// Remote type filter
    enum RemoteType: String, CaseIterable, Sendable {
        case onsite = "on_site"
        case remote = "remote"
        case hybrid = "hybrid"

        var displayName: String {
            switch self {
            case .onsite: return "On-site"
            case .remote: return "Remote"
            case .hybrid: return "Hybrid"
            }
        }
    }

    /// Job type filter
    enum JobType: String, CaseIterable, Sendable {
        case fullTime = "full_time"
        case partTime = "part_time"
        case contract = "contract"
        case temporary = "temporary"
        case volunteer = "volunteer"
        case internship = "internship"
        case other = "other"

        var displayName: String {
            switch self {
            case .fullTime: return "Full-time"
            case .partTime: return "Part-time"
            case .contract: return "Contract"
            case .temporary: return "Temporary"
            case .volunteer: return "Volunteer"
            case .internship: return "Internship"
            case .other: return "Other"
            }
        }
    }

    /// Build URL query items (no API key - auth is via headers)
    func buildQueryItems() -> [URLQueryItem] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "keyword", value: keyword),
            URLQueryItem(name: "page", value: String(page))
        ]

        if sortBy != .relevant {
            items.append(URLQueryItem(name: "sort_by", value: sortBy.rawValue))
        }

        if let datePosted = datePosted, datePosted != .anytime {
            items.append(URLQueryItem(name: "date_posted", value: datePosted.rawValue))
        }

        if let geocode = geocode, !geocode.isEmpty {
            items.append(URLQueryItem(name: "geo_code", value: geocode))
        }

        if let experienceLevel = experienceLevel {
            items.append(URLQueryItem(name: "experience_level", value: experienceLevel.rawValue))
        }

        if let remote = remote {
            items.append(URLQueryItem(name: "remote", value: remote.rawValue))
        }

        if let jobType = jobType {
            items.append(URLQueryItem(name: "job_type", value: jobType.rawValue))
        }

        if let easyApply = easyApply, easyApply {
            items.append(URLQueryItem(name: "easy_apply", value: "true"))
        }

        if let under10Applicants = under10Applicants, under10Applicants {
            items.append(URLQueryItem(name: "under_10_applicants", value: "true"))
        }

        if let hasVerifications = hasVerifications, hasVerifications {
            items.append(URLQueryItem(name: "has_verifications", value: "true"))
        }

        if let fairChanceEmployer = fairChanceEmployer, fairChanceEmployer {
            items.append(URLQueryItem(name: "fair_chance_employer", value: "true"))
        }

        return items
    }
}

// MARK: - Search Response Models

/// Response from RapidAPI job search endpoint
struct RapidAPISearchResponse: Codable, Sendable {
    let success: Bool?
    let cost: Double?
    let page: Int?
    let total: Int?
    let has_more: Bool?
    let data: [RapidAPIJob]?
    let error: String?
    let message: String?
}

/// Single job from search results
struct RapidAPIJob: Codable, Sendable, Identifiable {
    let id: String?
    let title: String?
    let url: String?
    let listed_at: String?  // ISO 8601 date
    let is_promote: Bool?
    let is_easy_apply: Bool?
    let location: String?
    let company: RapidAPICompany?

    /// Convert to JobPosting for display and storage
    func toJobPosting() -> JobPosting? {
        guard let companyName = company?.name, !companyName.isEmpty,
              let role = title, !role.isEmpty else {
            return nil
        }

        return JobPosting(
            company: companyName,
            role: role,
            location: location ?? "Not specified",
            companyWebsite: company?.url,
            aggregatorLink: url,
            aggregatorName: "LinkedIn",
            datePosted: parseISO8601Date(listed_at),
            hasEasyApply: is_easy_apply
        )
    }

    /// Parse ISO 8601 date string to "yyyy-MM-dd" format
    private func parseISO8601Date(_ dateString: String?) -> String? {
        guard let dateString = dateString, !dateString.isEmpty else { return nil }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Try with fractional seconds first, then without
        if let date = isoFormatter.date(from: dateString) {
            let outputFormatter = DateFormatter()
            outputFormatter.dateFormat = "yyyy-MM-dd"
            outputFormatter.locale = Locale(identifier: "en_US_POSIX")
            return outputFormatter.string(from: date)
        }

        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: dateString) {
            let outputFormatter = DateFormatter()
            outputFormatter.dateFormat = "yyyy-MM-dd"
            outputFormatter.locale = Locale(identifier: "en_US_POSIX")
            return outputFormatter.string(from: date)
        }

        // Already in yyyy-MM-dd format?
        if dateString.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
            return dateString
        }

        return dateString
    }
}

/// Company information from search results
struct RapidAPICompany: Codable, Sendable {
    let id: String?
    let name: String?
    let url: String?
    let verified: Bool?
    let logo: [RapidAPILogo]?
}

/// Company logo
struct RapidAPILogo: Codable, Sendable {
    let url: String?
    let width: Int?
    let height: Int?
}

// MARK: - Job Details Response Models

/// Response from RapidAPI job details endpoint
struct RapidAPIJobDetailsResponse: Codable, Sendable {
    let success: Bool?
    let cost: Double?
    let data: RapidAPIJobDetails?
    let error: String?
    let message: String?
}

/// Detailed job information
struct RapidAPIJobDetails: Codable, Sendable {
    let id: String?
    let title: String?
    let description: String?
    let job_url: String?
    let location: String?
    let level: String?
    let employment_status: String?
    let salary: RapidAPISalary?
    let industries: [String]?
    let job_functions: [String]?
    let benefits: [String]?
    let workplace_types: [String]?
    let company: RapidAPIDetailCompany?

    /// Enrich an existing JobPosting with details from the API
    func enrichJobPosting(_ job: JobPosting) -> JobPosting {
        // Build salary display if available
        var salaryDisplay = job.salaryDisplay
        if let salary = salary, salary.salary_exists == true {
            salaryDisplay = formatSalary(salary)
        }

        // Build description with metadata
        var fullDescription = job.descriptionText
        if let desc = description, !desc.isEmpty {
            var parts: [String] = []

            if let level = level, !level.isEmpty {
                parts.append("Level: \(level)")
            }
            if let employment = employment_status, !employment.isEmpty {
                parts.append("Employment: \(employment)")
            }
            if let industries = industries, !industries.isEmpty {
                parts.append("Industries: \(industries.joined(separator: ", "))")
            }
            if let benefits = benefits, !benefits.isEmpty {
                parts.append("Benefits: \(benefits.joined(separator: ", "))")
            }
            if !parts.isEmpty {
                parts.append("")
            }
            parts.append(desc)
            fullDescription = parts.joined(separator: "\n")
        }

        return JobPosting(
            persistedId: job.persistedId,
            company: company?.name ?? job.company,
            role: title ?? job.role,
            location: location ?? job.location,
            country: job.country,
            category: job.category,
            companyWebsite: company?.url ?? job.companyWebsite,
            companyLink: job.companyLink,
            aggregatorLink: job_url ?? job.aggregatorLink,
            aggregatorName: job.aggregatorName ?? "LinkedIn",
            datePosted: job.datePosted,
            notes: job.notes,
            isFAANG: job.isFAANG,
            isInternship: job.isInternship,
            lastViewed: job.lastViewed,
            userStatus: job.userStatus,
            statusChangedAt: job.statusChangedAt,
            descriptionText: fullDescription ?? job.descriptionText,
            analysisStatus: job.analysisStatus,
            analysisError: job.analysisError,
            salaryDisplay: salaryDisplay ?? job.salaryDisplay,
            hasEasyApply: job.hasEasyApply
        )
    }

    /// Format salary info for display
    private func formatSalary(_ salary: RapidAPISalary) -> String? {
        guard salary.salary_exists == true else { return nil }

        let currency = salary.currency ?? "USD"
        let period = salary.pay_period ?? "yearly"

        if let min = salary.min_salary, let max = salary.max_salary {
            let minStr = formatSalaryAmount(min, currency: currency)
            let maxStr = formatSalaryAmount(max, currency: currency)
            return "\(minStr) - \(maxStr)/\(abbreviatePeriod(period))"
        } else if let min = salary.min_salary {
            let minStr = formatSalaryAmount(min, currency: currency)
            return "From \(minStr)/\(abbreviatePeriod(period))"
        } else if let max = salary.max_salary {
            let maxStr = formatSalaryAmount(max, currency: currency)
            return "Up to \(maxStr)/\(abbreviatePeriod(period))"
        }

        return nil
    }

    private func formatSalaryAmount(_ amount: Double, currency: String) -> String {
        if amount >= 1000 {
            let k = amount / 1000.0
            if k == Double(Int(k)) {
                return "$\(Int(k))k"
            } else {
                return "$\(String(format: "%.1f", k))k"
            }
        }
        return "$\(Int(amount))"
    }

    private func abbreviatePeriod(_ period: String) -> String {
        switch period.lowercased() {
        case "yearly", "year": return "yr"
        case "monthly", "month": return "mo"
        case "hourly", "hour": return "hr"
        case "weekly", "week": return "wk"
        default: return period
        }
    }
}

/// Salary information from job details
struct RapidAPISalary: Codable, Sendable {
    let min_salary: Double?
    let max_salary: Double?
    let currency: String?
    let pay_period: String?
    let salary_exists: Bool?
}

/// Company details from job details endpoint
struct RapidAPIDetailCompany: Codable, Sendable {
    let name: String?
    let url: String?
    let description: String?
    let staff_count: Int?
    let headquarter: String?
}
