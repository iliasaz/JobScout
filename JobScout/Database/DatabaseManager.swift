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
                    "date_posted" TEXT,
                    "notes" TEXT,
                    "is_faang" INTEGER NOT NULL DEFAULT 0,
                    "created_at" TEXT NOT NULL DEFAULT (datetime('now')),
                    "updated_at" TEXT NOT NULL DEFAULT (datetime('now')),
                    UNIQUE("source_id", "company", "role", "location", "company_link")
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
