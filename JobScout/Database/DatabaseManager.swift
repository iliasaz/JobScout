//
//  DatabaseManager.swift
//  JobScout
//
//  Created by Ilia Sazonov on 12/29/25.
//

import Foundation
import GRDB

/// Manages SQLite database connection and migrations
actor DatabaseManager {
    static let shared = DatabaseManager()

    private var dbQueue: DatabaseQueue?

    private init() {}

    /// Get the database queue, creating it if necessary
    func getDatabase() async throws -> DatabaseQueue {
        if let dbQueue = dbQueue {
            return dbQueue
        }

        let dbQueue = try await setupDatabase()
        self.dbQueue = dbQueue
        return dbQueue
    }

    /// Setup the database at app launch
    private func setupDatabase() async throws -> DatabaseQueue {
        let fileManager = FileManager.default

        // Get Application Support directory
        let appSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        // Create app-specific directory
        let appDirectory = appSupportURL.appendingPathComponent("JobScout", isDirectory: true)
        try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)

        // Database file path
        let dbPath = appDirectory.appendingPathComponent("jobscout.sqlite").path

        // Create database queue
        var config = Configuration()
        config.prepareDatabase { db in
            // Enable foreign keys
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        let dbQueue = try DatabaseQueue(path: dbPath, configuration: config)

        // Run migrations
        try await runMigrations(on: dbQueue)

        return dbQueue
    }

    /// Run database migrations
    private func runMigrations(on dbQueue: DatabaseQueue) async throws {
        var migrator = DatabaseMigrator()

        // Migration 1: Create initial tables
        migrator.registerMigration("001_CreateTables") { db in
            // Create job_sources table
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS "job_sources" (
                    "id" INTEGER PRIMARY KEY AUTOINCREMENT,
                    "url" TEXT NOT NULL UNIQUE,
                    "name" TEXT NOT NULL,
                    "last_fetched_at" TEXT,
                    "created_at" TEXT NOT NULL DEFAULT (datetime('now'))
                )
                """)

            // Create job_postings table
            // unique_link is the canonical identifier: company_link if present, else simplify_link
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS "job_postings" (
                    "id" INTEGER PRIMARY KEY AUTOINCREMENT,
                    "source_id" INTEGER NOT NULL REFERENCES "job_sources"("id") ON DELETE CASCADE,
                    "company" TEXT NOT NULL,
                    "role" TEXT NOT NULL,
                    "location" TEXT NOT NULL,
                    "country" TEXT NOT NULL DEFAULT 'USA',
                    "category" TEXT NOT NULL DEFAULT 'Other',
                    "company_link" TEXT,
                    "simplify_link" TEXT,
                    "unique_link" TEXT NOT NULL,
                    "date_posted" TEXT,
                    "notes" TEXT,
                    "is_faang" INTEGER NOT NULL DEFAULT 0,
                    "created_at" TEXT NOT NULL DEFAULT (datetime('now')),
                    "updated_at" TEXT NOT NULL DEFAULT (datetime('now')),
                    UNIQUE("unique_link")
                )
                """)

            // Create indexes for job_postings
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS "idx_job_postings_source" ON "job_postings"("source_id")
                """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS "idx_job_postings_country" ON "job_postings"("country")
                """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS "idx_job_postings_category" ON "job_postings"("category")
                """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS "idx_job_postings_company" ON "job_postings"("company")
                """)

            // Create user_job_status table
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS "user_job_status" (
                    "id" INTEGER PRIMARY KEY AUTOINCREMENT,
                    "job_id" INTEGER NOT NULL UNIQUE REFERENCES "job_postings"("id") ON DELETE CASCADE,
                    "status" TEXT NOT NULL DEFAULT 'new',
                    "notes" TEXT,
                    "applied_at" TEXT,
                    "created_at" TEXT NOT NULL DEFAULT (datetime('now')),
                    "updated_at" TEXT NOT NULL DEFAULT (datetime('now'))
                )
                """)
        }

        // Migration 2: Add unique_link column for URL-based deduplication
        migrator.registerMigration("002_AddUniqueLink") { db in
            // Check if column already exists (for fresh installs with updated 001 migration)
            let columns = try Row.fetchAll(db, sql: "PRAGMA table_info(job_postings)")
            let hasUniqueLink = columns.contains { $0["name"] as String == "unique_link" }

            if !hasUniqueLink {
                // Add the column
                try db.execute(sql: """
                    ALTER TABLE job_postings ADD COLUMN "unique_link" TEXT
                    """)

                // Populate unique_link from existing data (company_link or simplify_link)
                try db.execute(sql: """
                    UPDATE job_postings SET unique_link = COALESCE(company_link, simplify_link)
                    """)

                // Delete rows without any link (can't be uniquely identified)
                try db.execute(sql: """
                    DELETE FROM job_postings WHERE unique_link IS NULL
                    """)
            }

            // Drop old unique constraint and create new one
            // SQLite doesn't support DROP CONSTRAINT, so we need to recreate the table
            // For simplicity, we'll just create the index if it doesn't exist
            try db.execute(sql: """
                CREATE UNIQUE INDEX IF NOT EXISTS "idx_job_postings_unique_link" ON "job_postings"("unique_link")
                """)
        }

        // Migration 3: Add is_internship column
        migrator.registerMigration("003_AddIsInternship") { db in
            // Check if column already exists
            let columns = try Row.fetchAll(db, sql: "PRAGMA table_info(job_postings)")
            let hasIsInternship = columns.contains { $0["name"] as String == "is_internship" }

            if !hasIsInternship {
                // Add the column with default value
                try db.execute(sql: """
                    ALTER TABLE job_postings ADD COLUMN "is_internship" INTEGER NOT NULL DEFAULT 0
                    """)

                // Populate based on role containing "intern"
                try db.execute(sql: """
                    UPDATE job_postings SET is_internship = 1 WHERE LOWER(role) LIKE '%intern%'
                    """)
            }
        }

        // Migration 4: Rename simplify_link to aggregator_link and add aggregator_name
        migrator.registerMigration("004_RenameSimplifyToAggregator") { db in
            let columns = try Row.fetchAll(db, sql: "PRAGMA table_info(job_postings)")
            let columnNames = columns.compactMap { $0["name"] as? String }

            // Add aggregator_link column if it doesn't exist
            if !columnNames.contains("aggregator_link") {
                try db.execute(sql: """
                    ALTER TABLE job_postings ADD COLUMN "aggregator_link" TEXT
                    """)

                // Copy data from simplify_link if it exists
                if columnNames.contains("simplify_link") {
                    try db.execute(sql: """
                        UPDATE job_postings SET aggregator_link = simplify_link
                        """)
                }
            }

            // Add aggregator_name column if it doesn't exist
            if !columnNames.contains("aggregator_name") {
                try db.execute(sql: """
                    ALTER TABLE job_postings ADD COLUMN "aggregator_name" TEXT
                    """)

                // Infer aggregator name from aggregator_link
                try db.execute(sql: """
                    UPDATE job_postings SET aggregator_name = 'Simplify'
                    WHERE aggregator_link LIKE '%simplify.jobs%' OR aggregator_link LIKE '%simplify.co%'
                    """)
                try db.execute(sql: """
                    UPDATE job_postings SET aggregator_name = 'Jobright'
                    WHERE aggregator_link LIKE '%jobright.ai%'
                    """)
                try db.execute(sql: """
                    UPDATE job_postings SET aggregator_name = 'LinkedIn'
                    WHERE aggregator_link LIKE '%linkedin.com%'
                    """)
                try db.execute(sql: """
                    UPDATE job_postings SET aggregator_name = 'Indeed'
                    WHERE aggregator_link LIKE '%indeed.com%'
                    """)
                try db.execute(sql: """
                    UPDATE job_postings SET aggregator_name = 'Glassdoor'
                    WHERE aggregator_link LIKE '%glassdoor.com%'
                    """)
            }

            // Note: We don't drop simplify_link to avoid data loss
            // SQLite doesn't support DROP COLUMN easily
        }

        // Migration 5: Add last_viewed column for tracking apply button clicks
        migrator.registerMigration("005_AddLastViewed") { db in
            let columns = try Row.fetchAll(db, sql: "PRAGMA table_info(job_postings)")
            let columnNames = columns.compactMap { $0["name"] as? String }

            if !columnNames.contains("last_viewed") {
                try db.execute(sql: """
                    ALTER TABLE job_postings ADD COLUMN "last_viewed" TEXT
                    """)
            }
        }

        // Migration 6: Rename applied_at to status_changed_at in user_job_status
        migrator.registerMigration("006_RenameAppliedAtToStatusChangedAt") { db in
            let columns = try Row.fetchAll(db, sql: "PRAGMA table_info(user_job_status)")
            let columnNames = columns.compactMap { $0["name"] as? String }

            // Add status_changed_at if it doesn't exist
            if !columnNames.contains("status_changed_at") {
                try db.execute(sql: """
                    ALTER TABLE user_job_status ADD COLUMN "status_changed_at" TEXT
                    """)

                // Copy data from applied_at if it exists
                if columnNames.contains("applied_at") {
                    try db.execute(sql: """
                        UPDATE user_job_status SET status_changed_at = applied_at
                        """)
                }
            }
        }

        // Migration 7: Add company_website column to job_postings
        migrator.registerMigration("007_AddCompanyWebsite") { db in
            let columns = try Row.fetchAll(db, sql: "PRAGMA table_info(job_postings)")
            let columnNames = columns.compactMap { $0["name"] as? String }

            if !columnNames.contains("company_website") {
                try db.execute(sql: """
                    ALTER TABLE job_postings ADD COLUMN "company_website" TEXT
                    """)
            }
        }

        // Migration 8: Add job description analysis tables and columns
        migrator.registerMigration("008_AddJobDescriptionAnalysis") { db in
            let columns = try Row.fetchAll(db, sql: "PRAGMA table_info(job_postings)")
            let columnNames = columns.compactMap { $0["name"] as? String }

            // Add columns to job_postings for raw description and analysis status
            if !columnNames.contains("description_text") {
                try db.execute(sql: """
                    ALTER TABLE job_postings ADD COLUMN "description_text" TEXT
                    """)
            }

            if !columnNames.contains("analysis_status") {
                // Status: pending/processing/completed/failed
                try db.execute(sql: """
                    ALTER TABLE job_postings ADD COLUMN "analysis_status" TEXT
                    """)
            }

            if !columnNames.contains("analysis_error") {
                try db.execute(sql: """
                    ALTER TABLE job_postings ADD COLUMN "analysis_error" TEXT
                    """)
            }

            if !columnNames.contains("analyzed_at") {
                try db.execute(sql: """
                    ALTER TABLE job_postings ADD COLUMN "analyzed_at" TEXT
                    """)
            }

            // Create job_description_analysis table for extracted data
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS "job_description_analysis" (
                    "id" INTEGER PRIMARY KEY AUTOINCREMENT,
                    "job_id" INTEGER NOT NULL UNIQUE REFERENCES "job_postings"("id") ON DELETE CASCADE,
                    "salary_min" INTEGER,
                    "salary_max" INTEGER,
                    "salary_currency" TEXT DEFAULT 'USD',
                    "salary_period" TEXT DEFAULT 'yearly',
                    "has_stock_compensation" INTEGER DEFAULT 0,
                    "stock_type" TEXT,
                    "stock_details" TEXT,
                    "job_summary" TEXT,
                    "created_at" TEXT NOT NULL DEFAULT (datetime('now')),
                    "updated_at" TEXT NOT NULL DEFAULT (datetime('now'))
                )
                """)

            // Create job_technologies table for many-to-many relationship
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS "job_technologies" (
                    "id" INTEGER PRIMARY KEY AUTOINCREMENT,
                    "job_id" INTEGER NOT NULL REFERENCES "job_postings"("id") ON DELETE CASCADE,
                    "technology" TEXT NOT NULL,
                    "category" TEXT,
                    "is_required" INTEGER DEFAULT 1,
                    "created_at" TEXT NOT NULL DEFAULT (datetime('now')),
                    UNIQUE("job_id", "technology")
                )
                """)

            // Create indexes
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS "idx_job_analysis_job_id" ON "job_description_analysis"("job_id")
                """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS "idx_job_technologies_job_id" ON "job_technologies"("job_id")
                """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS "idx_job_postings_analysis_status" ON "job_postings"("analysis_status")
                """)
        }

        // Migration 9: Add FTS5 full-text search index
        migrator.registerMigration("009_AddFTSIndex") { db in
            // Create FTS5 virtual table for full-text search
            // Using trigram tokenizer for substring matching
            try db.execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS "job_fts" USING fts5(
                    job_id UNINDEXED,
                    company,
                    role,
                    summary,
                    technologies,
                    salary,
                    notes,
                    location,
                    tokenize='trigram'
                )
                """)

            // Populate FTS index from existing data
            try db.execute(sql: """
                INSERT INTO job_fts (job_id, company, role, summary, technologies, salary, notes, location)
                SELECT
                    jp.id,
                    jp.company,
                    jp.role,
                    COALESCE(jda.job_summary, ''),
                    COALESCE((
                        SELECT GROUP_CONCAT(technology, ' ')
                        FROM job_technologies jt
                        WHERE jt.job_id = jp.id
                    ), ''),
                    CASE
                        WHEN jda.salary_min IS NOT NULL AND jda.salary_max IS NOT NULL
                        THEN jda.salary_min || '-' || jda.salary_max || ' ' || COALESCE(jda.salary_currency, 'USD')
                        WHEN jda.salary_min IS NOT NULL
                        THEN jda.salary_min || ' ' || COALESCE(jda.salary_currency, 'USD')
                        WHEN jda.salary_max IS NOT NULL
                        THEN jda.salary_max || ' ' || COALESCE(jda.salary_currency, 'USD')
                        ELSE ''
                    END,
                    COALESCE(jp.notes, ''),
                    jp.location
                FROM job_postings jp
                LEFT JOIN job_description_analysis jda ON jp.id = jda.job_id
                """)

            // Create triggers to keep FTS index in sync

            // Trigger: After INSERT on job_postings
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS job_fts_insert AFTER INSERT ON job_postings
                BEGIN
                    INSERT INTO job_fts (job_id, company, role, summary, technologies, salary, notes, location)
                    VALUES (NEW.id, NEW.company, NEW.role, '', '', '', COALESCE(NEW.notes, ''), NEW.location);
                END
                """)

            // Trigger: After UPDATE on job_postings
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS job_fts_update AFTER UPDATE OF company, role, notes, location ON job_postings
                BEGIN
                    UPDATE job_fts SET
                        company = NEW.company,
                        role = NEW.role,
                        notes = COALESCE(NEW.notes, ''),
                        location = NEW.location
                    WHERE job_id = NEW.id;
                END
                """)

            // Trigger: After DELETE on job_postings
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS job_fts_delete AFTER DELETE ON job_postings
                BEGIN
                    DELETE FROM job_fts WHERE job_id = OLD.id;
                END
                """)

            // Trigger: After INSERT on job_description_analysis (for summary and salary)
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS job_fts_analysis_insert AFTER INSERT ON job_description_analysis
                BEGIN
                    UPDATE job_fts SET
                        summary = COALESCE(NEW.job_summary, ''),
                        salary = CASE
                            WHEN NEW.salary_min IS NOT NULL AND NEW.salary_max IS NOT NULL
                            THEN NEW.salary_min || '-' || NEW.salary_max || ' ' || COALESCE(NEW.salary_currency, 'USD')
                            WHEN NEW.salary_min IS NOT NULL
                            THEN NEW.salary_min || ' ' || COALESCE(NEW.salary_currency, 'USD')
                            WHEN NEW.salary_max IS NOT NULL
                            THEN NEW.salary_max || ' ' || COALESCE(NEW.salary_currency, 'USD')
                            ELSE ''
                        END
                    WHERE job_id = NEW.job_id;
                END
                """)

            // Trigger: After UPDATE on job_description_analysis
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS job_fts_analysis_update AFTER UPDATE ON job_description_analysis
                BEGIN
                    UPDATE job_fts SET
                        summary = COALESCE(NEW.job_summary, ''),
                        salary = CASE
                            WHEN NEW.salary_min IS NOT NULL AND NEW.salary_max IS NOT NULL
                            THEN NEW.salary_min || '-' || NEW.salary_max || ' ' || COALESCE(NEW.salary_currency, 'USD')
                            WHEN NEW.salary_min IS NOT NULL
                            THEN NEW.salary_min || ' ' || COALESCE(NEW.salary_currency, 'USD')
                            WHEN NEW.salary_max IS NOT NULL
                            THEN NEW.salary_max || ' ' || COALESCE(NEW.salary_currency, 'USD')
                            ELSE ''
                        END
                    WHERE job_id = NEW.job_id;
                END
                """)

            // Trigger: After INSERT on job_technologies
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS job_fts_tech_insert AFTER INSERT ON job_technologies
                BEGIN
                    UPDATE job_fts SET
                        technologies = COALESCE((
                            SELECT GROUP_CONCAT(technology, ' ')
                            FROM job_technologies
                            WHERE job_id = NEW.job_id
                        ), '')
                    WHERE job_id = NEW.job_id;
                END
                """)

            // Trigger: After DELETE on job_technologies
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS job_fts_tech_delete AFTER DELETE ON job_technologies
                BEGIN
                    UPDATE job_fts SET
                        technologies = COALESCE((
                            SELECT GROUP_CONCAT(technology, ' ')
                            FROM job_technologies
                            WHERE job_id = OLD.job_id
                        ), '')
                    WHERE job_id = OLD.job_id;
                END
                """)
        }

        // Migration 10: Add user_resume table for storing uploaded resume PDFs
        migrator.registerMigration("010_AddUserResume") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS "user_resume" (
                    "id" INTEGER PRIMARY KEY AUTOINCREMENT,
                    "file_name" TEXT NOT NULL,
                    "pdf_data" BLOB NOT NULL,
                    "file_size" INTEGER NOT NULL,
                    "uploaded_at" TEXT NOT NULL DEFAULT (datetime('now')),
                    "created_at" TEXT NOT NULL DEFAULT (datetime('now')),
                    "updated_at" TEXT NOT NULL DEFAULT (datetime('now'))
                )
                """)
        }

        // Run all migrations
        try migrator.migrate(dbQueue)
    }

    /// Get the database path for debugging
    func getDatabasePath() async throws -> String {
        let fileManager = FileManager.default
        let appSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        return appSupportURL
            .appendingPathComponent("JobScout")
            .appendingPathComponent("jobscout.sqlite")
            .path
    }
}
