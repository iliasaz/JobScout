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
    @Column("company_link")
    var companyLink: String?
    @Column("simplify_link")
    var simplifyLink: String?
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

    /// Convert from in-memory JobPosting
    static func from(_ job: JobPosting, sourceId: Int) -> Draft? {
        // unique_link is required - prefer company link, fall back to aggregator link
        guard let uniqueLink = job.companyLink ?? job.simplifyLink else {
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
            simplifyLink: job.simplifyLink,
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
            company: company,
            role: role,
            location: location,
            country: country,
            category: category,
            companyLink: companyLink,
            simplifyLink: simplifyLink,
            datePosted: datePosted,
            notes: notes,
            isFAANG: isFAANG,
            isInternship: isInternship
        )
    }
}
