//
//  JobRepository.swift
//  JobScout
//
//  Created by Ilia Sazonov on 12/29/25.
//

import Foundation
import GRDB
import StructuredQueries

/// Result of a save operation
struct SaveResult: Sendable {
    let savedCount: Int
    let skippedCount: Int
    let updatedCount: Int
}

/// Result of an FTS search with highlighted text
struct FTSSearchResult: Sendable {
    let job: PersistedJobPosting
    let highlightedCompany: String
    let highlightedRole: String
    let highlightedSummary: String
    let highlightedTechnologies: String
    let highlightedLocation: String
    let rank: Double
}

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

    /// Get all sources ordered by name
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

    /// Get all sources ordered by most recently used (for URL history dropdown)
    func getSourcesByRecentUsage(limit: Int = 20) async throws -> [JobSource] {
        let db = try await dbManager.getDatabase()

        return try await db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM job_sources
                ORDER BY COALESCE(last_fetched_at, created_at) DESC
                LIMIT ?
                """, arguments: [limit])
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

    /// Add or update a source URL (touch its last_fetched_at timestamp)
    func touchSource(url: String, name: String? = nil) async throws -> JobSource {
        let db = try await dbManager.getDatabase()

        return try await db.write { db in
            // Check if source exists
            if let existing = try Row.fetchOne(db, sql: """
                SELECT * FROM job_sources WHERE url = ?
                """, arguments: [url]) {
                // Update last_fetched_at
                try db.execute(sql: """
                    UPDATE job_sources SET last_fetched_at = datetime('now') WHERE id = ?
                    """, arguments: [existing["id"] as Int])

                return JobSource(
                    id: existing["id"],
                    url: existing["url"],
                    name: existing["name"],
                    lastFetchedAt: Date(),
                    createdAt: existing["created_at"]
                )
            }

            // Create new source with name derived from URL if not provided
            let sourceName = name ?? Self.extractSourceName(from: url)
            try db.execute(sql: """
                INSERT INTO job_sources (url, name, last_fetched_at, created_at)
                VALUES (?, ?, datetime('now'), datetime('now'))
                """, arguments: [url, sourceName])

            let id = db.lastInsertedRowID

            return JobSource(
                id: Int(id),
                url: url,
                name: sourceName,
                lastFetchedAt: Date(),
                createdAt: Date()
            )
        }
    }

    /// Delete a source by URL
    func deleteSource(url: String) async throws {
        let db = try await dbManager.getDatabase()

        try await db.write { db in
            // First get the source ID
            guard let row = try Row.fetchOne(db, sql: "SELECT id FROM job_sources WHERE url = ?", arguments: [url]) else {
                return // Source doesn't exist, nothing to delete
            }
            let sourceId: Int = row["id"]

            // Delete associated jobs first (foreign key constraint)
            try db.execute(sql: "DELETE FROM job_postings WHERE source_id = ?", arguments: [sourceId])

            // Delete the source
            try db.execute(sql: "DELETE FROM job_sources WHERE id = ?", arguments: [sourceId])
        }
    }

    /// Extract a friendly name from a URL
    private static func extractSourceName(from url: String) -> String {
        guard let parsedURL = URL(string: url) else { return url }
        let components = parsedURL.pathComponents.filter { $0 != "/" }
        if components.count >= 2 {
            return "\(components[0])/\(components[1])"
        } else if let host = parsedURL.host {
            return host
        }
        return url
    }

    // MARK: - Job Postings

    /// Save jobs from a fetch operation (upsert)
    /// Jobs are uniquely identified by their URL (company link, or aggregator link as fallback)
    func saveJobs(_ jobs: [JobPosting], sourceId: Int) async throws -> SaveResult {
        let db = try await dbManager.getDatabase()

        return try await db.write { db in
            var savedCount = 0
            var skippedCount = 0
            var updatedCount = 0

            for job in jobs {
                // Compute unique_link: prefer company link, fall back to aggregator link
                guard let uniqueLink = job.companyLink ?? job.aggregatorLink else {
                    // Skip jobs without any link - can't uniquely identify them
                    skippedCount += 1
                    continue
                }

                // Try to insert, ignore if duplicate (based on unique_link constraint)
                do {
                    // Map hasEasyApply: nil -> NSNull, true -> 1, false -> 0
                    let hasEasyApplyValue: DatabaseValueConvertible? = job.hasEasyApply.map { $0 ? 1 : 0 }

                    try db.execute(sql: """
                        INSERT INTO job_postings (
                            source_id, company, role, location, country, category,
                            company_website, company_link, aggregator_link, aggregator_name, unique_link, date_posted, notes, is_faang, is_internship,
                            has_easy_apply, created_at, updated_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'), datetime('now'))
                        """, arguments: [
                            sourceId,
                            job.company,
                            job.role,
                            job.location,
                            job.country,
                            job.category,
                            job.companyWebsite,
                            job.companyLink,
                            job.aggregatorLink,
                            job.aggregatorName,
                            uniqueLink,
                            job.datePosted,
                            job.notes,
                            job.isFAANG ? 1 : 0,
                            job.isInternship ? 1 : 0,
                            hasEasyApplyValue
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
                            company_website = COALESCE(?, company_website),
                            company_link = ?,
                            aggregator_link = COALESCE(?, aggregator_link),
                            aggregator_name = COALESCE(?, aggregator_name),
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
                            job.companyWebsite,
                            job.companyLink,
                            job.aggregatorLink,
                            job.aggregatorName,
                            job.datePosted,
                            job.notes,
                            job.isFAANG ? 1 : 0,
                            job.isInternship ? 1 : 0,
                            uniqueLink
                        ])
                    updatedCount += 1
                }
            }

            return SaveResult(savedCount: savedCount, skippedCount: skippedCount, updatedCount: updatedCount)
        }
    }

    /// Get all jobs, optionally filtered by source, with status info
    func getJobs(sourceId: Int? = nil) async throws -> [PersistedJobPosting] {
        let db = try await dbManager.getDatabase()

        return try await db.read { db in
            let sql: String
            let arguments: StatementArguments

            if let sourceId = sourceId {
                sql = """
                    SELECT jp.*, ujs.status as user_status, ujs.status_changed_at,
                           jda.salary_min, jda.salary_max, jda.salary_currency, jda.salary_period
                    FROM job_postings jp
                    LEFT JOIN user_job_status ujs ON jp.id = ujs.job_id
                    LEFT JOIN job_description_analysis jda ON jp.id = jda.job_id
                    WHERE jp.source_id = ?
                    ORDER BY jp.created_at DESC
                    """
                arguments = [sourceId]
            } else {
                sql = """
                    SELECT jp.*, ujs.status as user_status, ujs.status_changed_at,
                           jda.salary_min, jda.salary_max, jda.salary_currency, jda.salary_period
                    FROM job_postings jp
                    LEFT JOIN user_job_status ujs ON jp.id = ujs.job_id
                    LEFT JOIN job_description_analysis jda ON jp.id = jda.job_id
                    ORDER BY jp.created_at DESC
                    """
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

    /// Search jobs by company or role (legacy LIKE-based search)
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

    /// Full-text search using FTS5 with BM25 ranking and highlighting
    /// Searches across company, role, summary, technologies, salary, notes, and location
    func searchJobsFTS(query: String) async throws -> [FTSSearchResult] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return []
        }

        let db = try await dbManager.getDatabase()

        // Sanitize query by quoting each term to prevent FTS syntax injection
        let sanitizedQuery = Self.sanitizeFTSQuery(query)

        return try await db.read { db in
            // Use BM25 for ranking with column weights:
            // job_id=0 (UNINDEXED), company=10, role=10, summary=5, technologies=8, salary=3, notes=2, location=2
            let rows = try Row.fetchAll(db, sql: """
                SELECT
                    jp.*,
                    ujs.status as user_status,
                    ujs.status_changed_at,
                    jda.salary_min,
                    jda.salary_max,
                    jda.salary_currency,
                    jda.salary_period,
                    bm25(job_fts, 0, 10, 10, 5, 8, 3, 2, 2) as rank,
                    highlight(job_fts, 1, '**', '**') as hl_company,
                    highlight(job_fts, 2, '**', '**') as hl_role,
                    snippet(job_fts, 3, '**', '**', '...', 40) as hl_summary,
                    highlight(job_fts, 4, '**', '**') as hl_technologies,
                    highlight(job_fts, 7, '**', '**') as hl_location
                FROM job_fts
                INNER JOIN job_postings jp ON job_fts.job_id = jp.id
                LEFT JOIN user_job_status ujs ON jp.id = ujs.job_id
                LEFT JOIN job_description_analysis jda ON jp.id = jda.job_id
                WHERE job_fts MATCH ?
                ORDER BY rank
                """, arguments: [sanitizedQuery])

            return rows.map { row in
                FTSSearchResult(
                    job: Self.jobPosting(from: row),
                    highlightedCompany: row["hl_company"] ?? row["company"] ?? "",
                    highlightedRole: row["hl_role"] ?? row["role"] ?? "",
                    highlightedSummary: row["hl_summary"] ?? "",
                    highlightedTechnologies: row["hl_technologies"] ?? "",
                    highlightedLocation: row["hl_location"] ?? row["location"] ?? "",
                    rank: row["rank"] ?? 0.0
                )
            }
        }
    }

    /// Sanitize FTS query by quoting each term to prevent syntax errors
    private static func sanitizeFTSQuery(_ query: String) -> String {
        // Split by whitespace and quote each non-empty term
        let terms = query.split(whereSeparator: { $0.isWhitespace })
            .map { String($0) }
            .filter { !$0.isEmpty }

        // For single term, just quote it
        if terms.count == 1 {
            return "\"\(terms[0])\""
        }

        // For multiple terms, quote each and join with space (implicit AND)
        return terms.map { "\"\($0)\"" }.joined(separator: " ")
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
                    status_changed_at = CASE WHEN ? != 'new' THEN datetime('now') ELSE status_changed_at END,
                    updated_at = datetime('now')
                WHERE job_id = ?
                """, arguments: [status.rawValue, notes, status.rawValue, jobId])

            // If no row was updated, insert new status
            if db.changesCount == 0 {
                try db.execute(sql: """
                    INSERT INTO user_job_status (job_id, status, notes, status_changed_at, created_at, updated_at)
                    VALUES (?, ?, ?, CASE WHEN ? != 'new' THEN datetime('now') ELSE NULL END, datetime('now'), datetime('now'))
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
                statusChangedAt: row["status_changed_at"],
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
        // Parse user status from joined data
        let userStatusString: String? = row["user_status"]
        let userStatus = userStatusString.flatMap { JobStatus(rawValue: $0) } ?? .new

        // Build salary display string if we have salary data
        var salaryDisplay: String?
        if let salaryMin: Int = row["salary_min"], let salaryMax: Int = row["salary_max"] {
            let currency = (row["salary_currency"] as String?) ?? "USD"
            let period = (row["salary_period"] as String?) ?? "yearly"
            let salaryInfo = SalaryInfo(
                min: salaryMin,
                max: salaryMax,
                currency: currency,
                period: SalaryInfo.SalaryPeriod(rawValue: period) ?? .yearly
            )
            salaryDisplay = salaryInfo.displayString
        } else if let salaryMin: Int = row["salary_min"] {
            let currency = (row["salary_currency"] as String?) ?? "USD"
            let period = (row["salary_period"] as String?) ?? "yearly"
            let salaryInfo = SalaryInfo(
                min: salaryMin,
                max: nil,
                currency: currency,
                period: SalaryInfo.SalaryPeriod(rawValue: period) ?? .yearly
            )
            salaryDisplay = salaryInfo.displayString
        } else if let salaryMax: Int = row["salary_max"] {
            let currency = (row["salary_currency"] as String?) ?? "USD"
            let period = (row["salary_period"] as String?) ?? "yearly"
            let salaryInfo = SalaryInfo(
                min: nil,
                max: salaryMax,
                currency: currency,
                period: SalaryInfo.SalaryPeriod(rawValue: period) ?? .yearly
            )
            salaryDisplay = salaryInfo.displayString
        }

        // Parse hasEasyApply (NULL = unknown, 0 = false, 1 = true)
        let hasEasyApplyInt: Int? = row["has_easy_apply"]
        let hasEasyApply: Bool? = hasEasyApplyInt.map { $0 == 1 }

        return PersistedJobPosting(
            id: row["id"],
            sourceId: row["source_id"],
            company: row["company"],
            role: row["role"],
            location: row["location"],
            country: row["country"],
            category: row["category"],
            companyWebsite: row["company_website"],
            companyLink: row["company_link"],
            aggregatorLink: row["aggregator_link"],
            aggregatorName: row["aggregator_name"],
            uniqueLink: row["unique_link"],
            datePosted: row["date_posted"],
            notes: row["notes"],
            isFAANG: row["is_faang"] == 1,
            isInternship: row["is_internship"] == 1,
            createdAt: row["created_at"],
            updatedAt: row["updated_at"],
            lastViewed: row["last_viewed"],
            userStatus: userStatus,
            statusChangedAt: row["status_changed_at"],
            descriptionText: row["description_text"],
            analysisStatusRaw: row["analysis_status"],
            analysisError: row["analysis_error"],
            analyzedAt: row["analyzed_at"],
            salaryDisplay: salaryDisplay,
            hasEasyApply: hasEasyApply
        )
    }

    // MARK: - Easy Apply Detection

    /// Update hasEasyApply flag for a job
    func setEasyApply(jobId: Int, hasEasyApply: Bool) async throws {
        let db = try await dbManager.getDatabase()

        try await db.write { db in
            try db.execute(sql: """
                UPDATE job_postings SET has_easy_apply = ?, updated_at = datetime('now') WHERE id = ?
                """, arguments: [hasEasyApply ? 1 : 0, jobId])
        }
    }

    /// Update hasEasyApply flag for a job identified by its unique_link
    func setEasyApplyByLink(link: String, hasEasyApply: Bool) async throws {
        let db = try await dbManager.getDatabase()

        try await db.write { db in
            try db.execute(sql: """
                UPDATE job_postings SET has_easy_apply = ?, updated_at = datetime('now') WHERE unique_link = ?
                """, arguments: [hasEasyApply ? 1 : 0, link])
        }
    }

    // MARK: - Apply Tracking

    /// Update last_viewed timestamp when Apply button is clicked
    func recordApplyClick(jobId: Int) async throws {
        let db = try await dbManager.getDatabase()

        try await db.write { db in
            try db.execute(sql: """
                UPDATE job_postings SET last_viewed = datetime('now') WHERE id = ?
                """, arguments: [jobId])
        }
    }

    // MARK: - Job Description Analysis

    /// Set analysis status for a job
    func setAnalysisStatus(jobId: Int, status: AnalysisStatus, error: String? = nil) async throws {
        let db = try await dbManager.getDatabase()

        try await db.write { db in
            if status == .completed {
                try db.execute(sql: """
                    UPDATE job_postings SET
                        analysis_status = ?,
                        analysis_error = NULL,
                        analyzed_at = datetime('now'),
                        updated_at = datetime('now')
                    WHERE id = ?
                    """, arguments: [status.rawValue, jobId])
            } else if status == .failed {
                try db.execute(sql: """
                    UPDATE job_postings SET
                        analysis_status = ?,
                        analysis_error = ?,
                        updated_at = datetime('now')
                    WHERE id = ?
                    """, arguments: [status.rawValue, error, jobId])
            } else {
                try db.execute(sql: """
                    UPDATE job_postings SET
                        analysis_status = ?,
                        updated_at = datetime('now')
                    WHERE id = ?
                    """, arguments: [status.rawValue, jobId])
            }
        }
    }

    /// Get next job pending analysis
    func getNextPendingAnalysis() async throws -> PersistedJobPosting? {
        let db = try await dbManager.getDatabase()

        return try await db.read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT jp.*, ujs.status as user_status, ujs.status_changed_at
                FROM job_postings jp
                LEFT JOIN user_job_status ujs ON jp.id = ujs.job_id
                WHERE jp.analysis_status = 'pending'
                ORDER BY jp.created_at ASC
                LIMIT 1
                """)
            return row.map { Self.jobPosting(from: $0) }
        }
    }

    /// Queue all unanalyzed jobs for analysis
    func queueUnanalyzedJobs() async throws -> Int {
        let db = try await dbManager.getDatabase()

        return try await db.write { db in
            try db.execute(sql: """
                UPDATE job_postings SET analysis_status = 'pending'
                WHERE analysis_status IS NULL
                AND (company_link IS NOT NULL OR aggregator_link IS NOT NULL)
                """)
            return db.changesCount
        }
    }

    /// Queue specific jobs for analysis (e.g., newly saved jobs)
    func queueJobsForAnalysis(jobIds: [Int]) async throws {
        guard !jobIds.isEmpty else { return }
        let db = try await dbManager.getDatabase()

        try await db.write { db in
            let placeholders = jobIds.map { _ in "?" }.joined(separator: ", ")
            try db.execute(sql: """
                UPDATE job_postings SET analysis_status = 'pending'
                WHERE id IN (\(placeholders))
                AND (company_link IS NOT NULL OR aggregator_link IS NOT NULL)
                """, arguments: StatementArguments(jobIds))
        }
    }

    /// Save job description text
    func saveJobDescription(jobId: Int, description: String) async throws {
        let db = try await dbManager.getDatabase()

        try await db.write { db in
            try db.execute(sql: """
                UPDATE job_postings SET
                    description_text = ?,
                    updated_at = datetime('now')
                WHERE id = ?
                """, arguments: [description, jobId])
        }
    }

    /// Save analysis results
    func saveAnalysisResult(jobId: Int, result: JobDescriptionAnalysisOutput) async throws {
        let db = try await dbManager.getDatabase()

        try await db.write { db in
            // Save or update analysis record
            try db.execute(sql: """
                INSERT INTO job_description_analysis (
                    job_id, salary_min, salary_max, salary_currency, salary_period,
                    has_stock_compensation, stock_type, stock_details, job_summary,
                    created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'), datetime('now'))
                ON CONFLICT(job_id) DO UPDATE SET
                    salary_min = excluded.salary_min,
                    salary_max = excluded.salary_max,
                    salary_currency = excluded.salary_currency,
                    salary_period = excluded.salary_period,
                    has_stock_compensation = excluded.has_stock_compensation,
                    stock_type = excluded.stock_type,
                    stock_details = excluded.stock_details,
                    job_summary = excluded.job_summary,
                    updated_at = datetime('now')
                """, arguments: [
                    jobId,
                    result.salary?.min,
                    result.salary?.max,
                    result.salary?.currency ?? "USD",
                    result.salary?.period ?? "yearly",
                    result.stock?.hasStock == true ? 1 : 0,
                    result.stock?.type,
                    result.stock?.details,
                    result.summary
                ])

            // Save technologies (delete existing first, then insert new)
            try db.execute(sql: "DELETE FROM job_technologies WHERE job_id = ?", arguments: [jobId])

            for tech in result.technologies {
                try db.execute(sql: """
                    INSERT INTO job_technologies (job_id, technology, category, is_required, created_at)
                    VALUES (?, ?, ?, ?, datetime('now'))
                    """, arguments: [
                        jobId,
                        tech.name,
                        tech.category,
                        tech.required ? 1 : 0
                    ])
            }
        }
    }

    /// Get job analysis result
    func getJobAnalysis(jobId: Int) async throws -> JobAnalysisResult? {
        let db = try await dbManager.getDatabase()

        return try await db.read { db in
            // Get analysis record
            guard let analysisRow = try Row.fetchOne(db, sql: """
                SELECT * FROM job_description_analysis WHERE job_id = ?
                """, arguments: [jobId]) else {
                return nil
            }

            // Get technologies
            let techRows = try Row.fetchAll(db, sql: """
                SELECT * FROM job_technologies WHERE job_id = ? ORDER BY is_required DESC, technology ASC
                """, arguments: [jobId])

            let technologies = techRows.map { row in
                JobTechnology(
                    id: row["id"],
                    technology: row["technology"],
                    category: (row["category"] as String?).flatMap { JobTechnology.TechnologyCategory(rawValue: $0) },
                    isRequired: row["is_required"] == 1
                )
            }

            // Build salary info
            var salaryInfo: SalaryInfo?
            let salaryMin: Int? = analysisRow["salary_min"]
            let salaryMax: Int? = analysisRow["salary_max"]
            if salaryMin != nil || salaryMax != nil {
                salaryInfo = SalaryInfo(
                    min: salaryMin,
                    max: salaryMax,
                    currency: analysisRow["salary_currency"] ?? "USD",
                    period: SalaryInfo.SalaryPeriod(rawValue: analysisRow["salary_period"] ?? "yearly") ?? .yearly
                )
            }

            // Build stock info
            let hasStock: Bool = analysisRow["has_stock_compensation"] == 1
            let stockInfo = StockInfo(
                hasStock: hasStock,
                type: (analysisRow["stock_type"] as String?).flatMap { StockInfo.StockType(rawValue: $0) },
                details: analysisRow["stock_details"]
            )

            return JobAnalysisResult(
                jobId: jobId,
                salary: salaryInfo,
                stock: hasStock ? stockInfo : nil,
                technologies: technologies,
                summary: analysisRow["job_summary"],
                analyzedAt: analysisRow["updated_at"] ?? Date()
            )
        }
    }

    /// Get technologies for a job
    func getJobTechnologies(jobId: Int) async throws -> [JobTechnology] {
        let db = try await dbManager.getDatabase()

        return try await db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM job_technologies WHERE job_id = ? ORDER BY is_required DESC, technology ASC
                """, arguments: [jobId])

            return rows.map { row in
                JobTechnology(
                    id: row["id"],
                    technology: row["technology"],
                    category: (row["category"] as String?).flatMap { JobTechnology.TechnologyCategory(rawValue: $0) },
                    isRequired: row["is_required"] == 1
                )
            }
        }
    }

    /// Get count of jobs pending analysis
    func getPendingAnalysisCount() async throws -> Int {
        let db = try await dbManager.getDatabase()

        return try await db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM job_postings WHERE analysis_status = 'pending'") ?? 0
        }
    }

    /// Get count of jobs being processed
    func getProcessingAnalysisCount() async throws -> Int {
        let db = try await dbManager.getDatabase()

        return try await db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM job_postings WHERE analysis_status = 'processing'") ?? 0
        }
    }
}
