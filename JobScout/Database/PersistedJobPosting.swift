//
//  PersistedJobPosting.swift
//  JobScout
//
//  Created by Ilia Sazonov on 12/29/25.
//

import Foundation
import StructuredQueries

/// Persisted job posting in the database
@Table("job_postings")
nonisolated struct PersistedJobPosting: Identifiable, Sendable {
    let id: Int
    @Column("source_id")
    var sourceId: Int
    var company: String
    var role: String
    var location: String
    var country: String
    var category: String
    @Column("company_website")
    var companyWebsite: String?
    @Column("company_link")
    var companyLink: String?
    @Column("aggregator_link")
    var aggregatorLink: String?
    @Column("aggregator_name")
    var aggregatorName: String?
    @Column("unique_link")
    var uniqueLink: String
    @Column("date_posted")
    var datePosted: String?
    var notes: String?
    @Column("is_faang")
    var isFAANG: Bool
    @Column("is_internship")
    var isInternship: Bool
    @Column("created_at")
    let createdAt: Date
    @Column("updated_at")
    var updatedAt: Date
    @Column("last_viewed")
    var lastViewed: Date?

    // Status fields (populated from JOIN with user_job_status)
    var userStatus: JobStatus = .new
    var statusChangedAt: Date?

    // Analysis fields
    @Column("description_text")
    var descriptionText: String?
    @Column("analysis_status")
    var analysisStatusRaw: String?
    @Column("analysis_error")
    var analysisError: String?
    @Column("analyzed_at")
    var analyzedAt: Date?

    /// Parsed analysis status
    var analysisStatus: AnalysisStatus? {
        analysisStatusRaw.flatMap { AnalysisStatus(rawValue: $0) }
    }

    // Salary display (populated from JOIN with job_description_analysis)
    var salaryDisplay: String?

    /// Convert from in-memory JobPosting
    static func from(_ job: JobPosting, sourceId: Int) -> Draft? {
        // unique_link is required - prefer company link, fall back to aggregator link
        guard let uniqueLink = job.companyLink ?? job.aggregatorLink else {
            return nil
        }
        return Draft(
            sourceId: sourceId,
            company: job.company,
            role: job.role,
            location: job.location,
            country: job.country,
            category: job.category,
            companyLink: job.companyLink,
            aggregatorLink: job.aggregatorLink,
            aggregatorName: job.aggregatorName,
            uniqueLink: uniqueLink,
            datePosted: job.datePosted,
            notes: job.notes,
            isFAANG: job.isFAANG,
            isInternship: job.isInternship,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    /// Convert to in-memory JobPosting
    func toJobPosting() -> JobPosting {
        JobPosting(
            persistedId: id,
            company: company,
            role: role,
            location: location,
            country: country,
            category: category,
            companyWebsite: companyWebsite,
            companyLink: companyLink,
            aggregatorLink: aggregatorLink,
            aggregatorName: aggregatorName,
            datePosted: datePosted,
            notes: notes,
            isFAANG: isFAANG,
            isInternship: isInternship,
            lastViewed: lastViewed,
            userStatus: userStatus,
            statusChangedAt: statusChangedAt,
            descriptionText: descriptionText,
            analysisStatus: analysisStatus,
            analysisError: analysisError,
            salaryDisplay: salaryDisplay
        )
    }
}
