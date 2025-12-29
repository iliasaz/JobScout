//
//  JobRepository.swift
//  JobScout
//
//  Created by Ilia Sazonov on 12/29/25.
//

import Foundation
import GRDB
import StructuredQueries

/// Repository for managing job postings and related data
actor JobRepository {
    private let dbManager: DatabaseManager

    init(dbManager: DatabaseManager = .shared) {
        self.dbManager = dbManager
    }

    // MARK: - Job Sources

    /// Create or get existing source by URL
    func getOrCreateSource(url: String, name: String) async throws -> JobSource {
        let db = try await dbManager.getDatabase()

        return try await db.write { db in
            // Check if source exists
            if let existing = try Row.fetchOne(db, sql: """
                SELECT * FROM job_sources WHERE url = ?
                """, arguments: [url]) {
                return JobSource(
                    id: existing["id"],
                    url: existing["url"],
                    name: existing["name"],
                    lastFetchedAt: existing["last_fetched_at"],
                    createdAt: existing["created_at"]
                )
            }

            // Create new source
            try db.execute(sql: """
                INSERT INTO job_sources (url, name, created_at)
                VALUES (?, ?, datetime('now'))
                """, arguments: [url, name])

            let id = db.lastInsertedRowID

            return JobSource(
                id: Int(id),
                url: url,
                name: name,
                lastFetchedAt: nil,
                createdAt: Date()
            )
        }
    }

    /// Update the last fetched timestamp for a source
    func updateLastFetched(sourceId: Int) async throws {
        let db = try await dbManager.getDatabase()

        try await db.write { db in
            try db.execute(sql: """
                UPDATE job_sources SET last_fetched_at = datetime('now') WHERE id = ?
                """, arguments: [sourceId])
        }
    }

    /// Get all sources
    func getAllSources() async throws -> [JobSource] {
        let db = try await dbManager.getDatabase()

        return try await db.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM job_sources ORDER BY name")
            return rows.map { row in
                JobSource(
                    id: row["id"],
                    url: row["url"],
                    name: row["name"],
                    lastFetchedAt: row["last_fetched_at"],
                    createdAt: row["created_at"]
                )
            }
        }
    }

    // MARK: - Job Postings

    /// Save jobs from a fetch operation (upsert)
    /// Jobs are uniquely identified by their URL (company link, or aggregator link as fallback)
    func saveJobs(_ jobs: [JobPosting], sourceId: Int) async throws -> Int {
        let db = try await dbManager.getDatabase()

        return try await db.write { db in
            var savedCount = 0

            for job in jobs {
                // Compute unique_link: prefer company link, fall back to aggregator link
                guard let uniqueLink = job.companyLink ?? job.simplifyLink else {
                    // Skip jobs without any link - can't uniquely identify them
                    continue
                }

                // Try to insert, ignore if duplicate (based on unique_link constraint)
                do {
                    try db.execute(sql: """
                        INSERT INTO job_postings (
                            source_id, company, role, location, country, category,
                            company_link, simplify_link, unique_link, date_posted, notes, is_faang, is_internship,
                            created_at, updated_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'), datetime('now'))
                        """, arguments: [
                            sourceId,
                            job.company,
                            job.role,
                            job.location,
                            job.country,
                            job.category,
                            job.companyLink,
                            job.simplifyLink,
                            uniqueLink,
                            job.datePosted,
                            job.notes,
                            job.isFAANG ? 1 : 0,
                            job.isInternship ? 1 : 0
                        ])
                    savedCount += 1
                } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
                    // Duplicate based on unique_link, update the record
                    try db.execute(sql: """
                        UPDATE job_postings SET
                            source_id = ?,
                            company = ?,
                            role = ?,
                            location = ?,
                            country = ?,
                            category = ?,
                            company_link = ?,
                            simplify_link = COALESCE(?, simplify_link),
                            date_posted = COALESCE(?, date_posted),
                            notes = COALESCE(?, notes),
                            is_faang = ?,
                            is_internship = ?,
                            updated_at = datetime('now')
                        WHERE unique_link = ?
                        """, arguments: [
                            sourceId,
                            job.company,
                            job.role,
                            job.location,
                            job.country,
                            job.category,
                            job.companyLink,
                            job.simplifyLink,
                            job.datePosted,
                            job.notes,
                            job.isFAANG ? 1 : 0,
                            job.isInternship ? 1 : 0,
                            uniqueLink
                        ])
                }
            }

            return savedCount
        }
    }

    /// Get all jobs, optionally filtered by source
    func getJobs(sourceId: Int? = nil) async throws -> [PersistedJobPosting] {
        let db = try await dbManager.getDatabase()

        return try await db.read { db in
            let sql: String
            let arguments: StatementArguments

            if let sourceId = sourceId {
                sql = "SELECT * FROM job_postings WHERE source_id = ? ORDER BY created_at DESC"
                arguments = [sourceId]
            } else {
                sql = "SELECT * FROM job_postings ORDER BY created_at DESC"
                arguments = []
            }

            let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
            return rows.map { Self.jobPosting(from: $0) }
        }
    }

    /// Get jobs filtered by country
    func getJobsByCountry(_ country: String) async throws -> [PersistedJobPosting] {
        let db = try await dbManager.getDatabase()

        return try await db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM job_postings WHERE country = ? ORDER BY created_at DESC
                """, arguments: [country])
            return rows.map { Self.jobPosting(from: $0) }
        }
    }

    /// Get jobs filtered by category
    func getJobsByCategory(_ category: String) async throws -> [PersistedJobPosting] {
        let db = try await dbManager.getDatabase()

        return try await db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM job_postings WHERE category = ? ORDER BY created_at DESC
                """, arguments: [category])
            return rows.map { Self.jobPosting(from: $0) }
        }
    }

    /// Search jobs by company or role
    func searchJobs(query: String) async throws -> [PersistedJobPosting] {
        let db = try await dbManager.getDatabase()
        let searchPattern = "%\(query)%"

        return try await db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM job_postings
                WHERE company LIKE ? COLLATE NOCASE
                   OR role LIKE ? COLLATE NOCASE
                ORDER BY created_at DESC
                """, arguments: [searchPattern, searchPattern])
            return rows.map { Self.jobPosting(from: $0) }
        }
    }

    /// Get total job count
    func getJobCount() async throws -> Int {
        let db = try await dbManager.getDatabase()

        return try await db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM job_postings") ?? 0
        }
    }

    /// Get distinct countries
    func getDistinctCountries() async throws -> [String] {
        let db = try await dbManager.getDatabase()

        return try await db.read { db in
            try String.fetchAll(db, sql: "SELECT DISTINCT country FROM job_postings ORDER BY country")
        }
    }

    /// Get distinct categories
    func getDistinctCategories() async throws -> [String] {
        let db = try await dbManager.getDatabase()

        return try await db.read { db in
            try String.fetchAll(db, sql: "SELECT DISTINCT category FROM job_postings ORDER BY category")
        }
    }

    // MARK: - User Job Status

    /// Set user status for a job
    func setJobStatus(jobId: Int, status: JobStatus, notes: String? = nil) async throws {
        let db = try await dbManager.getDatabase()

        try await db.write { db in
            // Try to update existing status
            try db.execute(sql: """
                UPDATE user_job_status SET
                    status = ?,
                    notes = COALESCE(?, notes),
                    applied_at = CASE WHEN ? = 'applied' THEN datetime('now') ELSE applied_at END,
                    updated_at = datetime('now')
                WHERE job_id = ?
                """, arguments: [status.rawValue, notes, status.rawValue, jobId])

            // If no row was updated, insert new status
            if db.changesCount == 0 {
                try db.execute(sql: """
                    INSERT INTO user_job_status (job_id, status, notes, applied_at, created_at, updated_at)
                    VALUES (?, ?, ?, CASE WHEN ? = 'applied' THEN datetime('now') ELSE NULL END, datetime('now'), datetime('now'))
                    """, arguments: [jobId, status.rawValue, notes, status.rawValue])
            }
        }
    }

    /// Get user status for a job
    func getJobStatus(jobId: Int) async throws -> UserJobStatus? {
        let db = try await dbManager.getDatabase()

        return try await db.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT * FROM user_job_status WHERE job_id = ?
                """, arguments: [jobId]) else {
                return nil
            }

            return UserJobStatus(
                id: row["id"],
                jobId: row["job_id"],
                status: JobStatus(rawValue: row["status"]) ?? .new,
                notes: row["notes"],
                appliedAt: row["applied_at"],
                createdAt: row["created_at"],
                updatedAt: row["updated_at"]
            )
        }
    }

    /// Get jobs with a specific user status
    func getJobsByStatus(_ status: JobStatus) async throws -> [PersistedJobPosting] {
        let db = try await dbManager.getDatabase()

        return try await db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT jp.* FROM job_postings jp
                INNER JOIN user_job_status ujs ON jp.id = ujs.job_id
                WHERE ujs.status = ?
                ORDER BY jp.created_at DESC
                """, arguments: [status.rawValue])
            return rows.map { Self.jobPosting(from: $0) }
        }
    }

    /// Delete a job and its associated status
    func deleteJob(id: Int) async throws {
        let db = try await dbManager.getDatabase()

        try await db.write { db in
            try db.execute(sql: "DELETE FROM job_postings WHERE id = ?", arguments: [id])
        }
    }

    /// Delete all jobs from a source
    func deleteJobsFromSource(sourceId: Int) async throws {
        let db = try await dbManager.getDatabase()

        try await db.write { db in
            try db.execute(sql: "DELETE FROM job_postings WHERE source_id = ?", arguments: [sourceId])
        }
    }

    /// Delete all data from the database (jobs, sources, and user status)
    func deleteAllData() async throws {
        let db = try await dbManager.getDatabase()

        try await db.write { db in
            // Delete in order respecting foreign key constraints
            try db.execute(sql: "DELETE FROM user_job_status")
            try db.execute(sql: "DELETE FROM job_postings")
            try db.execute(sql: "DELETE FROM job_sources")
        }
    }

    // MARK: - Helpers

    /// Create a PersistedJobPosting from a database row
    private static func jobPosting(from row: Row) -> PersistedJobPosting {
        PersistedJobPosting(
            id: row["id"],
            sourceId: row["source_id"],
            company: row["company"],
            role: row["role"],
            location: row["location"],
            country: row["country"],
            category: row["category"],
            companyLink: row["company_link"],
            simplifyLink: row["simplify_link"],
            uniqueLink: row["unique_link"],
            datePosted: row["date_posted"],
            notes: row["notes"],
            isFAANG: row["is_faang"] == 1,
            isInternship: row["is_internship"] == 1,
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }
}
