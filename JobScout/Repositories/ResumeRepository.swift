//
//  ResumeRepository.swift
//  JobScout
//
//  Created by Claude on 1/11/26.
//

import Foundation
import GRDB

/// Repository for managing user resume storage
actor ResumeRepository {
    static let shared = ResumeRepository()

    private let dbManager: DatabaseManager

    init(dbManager: DatabaseManager = .shared) {
        self.dbManager = dbManager
    }

    /// Get the current resume if one exists
    /// Only one resume is stored at a time (the most recent one)
    func getCurrentResume() async throws -> UserResume? {
        let db = try await dbManager.getDatabase()

        return try await db.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT * FROM user_resume ORDER BY uploaded_at DESC LIMIT 1
                """) else {
                return nil
            }
            return UserResume.from(row: row)
        }
    }

    /// Save a new resume, replacing any existing one
    /// - Parameters:
    ///   - fileName: Original file name of the PDF
    ///   - pdfData: The PDF file data
    /// - Returns: The saved UserResume
    @discardableResult
    func saveResume(fileName: String, pdfData: Data) async throws -> UserResume {
        let db = try await dbManager.getDatabase()

        return try await db.write { db in
            // Delete any existing resume (we only keep one)
            try db.execute(sql: "DELETE FROM user_resume")

            // Insert the new resume
            try db.execute(sql: """
                INSERT INTO user_resume (file_name, pdf_data, file_size, uploaded_at, created_at, updated_at)
                VALUES (?, ?, ?, datetime('now'), datetime('now'), datetime('now'))
                """, arguments: [fileName, pdfData, pdfData.count])

            let id = db.lastInsertedRowID

            // Fetch and return the inserted record
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM user_resume WHERE id = ?", arguments: [id]) else {
                throw ResumeError.saveFailed
            }

            return UserResume.from(row: row)
        }
    }

    /// Update the existing resume with new data
    /// - Parameters:
    ///   - fileName: New file name of the PDF
    ///   - pdfData: The new PDF file data
    /// - Returns: The updated UserResume
    @discardableResult
    func updateResume(fileName: String, pdfData: Data) async throws -> UserResume {
        // Since we only keep one resume, updating is the same as saving
        return try await saveResume(fileName: fileName, pdfData: pdfData)
    }

    /// Delete the current resume
    func deleteResume() async throws {
        let db = try await dbManager.getDatabase()

        try await db.write { db in
            try db.execute(sql: "DELETE FROM user_resume")
        }
    }

    /// Check if a resume exists
    func hasResume() async throws -> Bool {
        let db = try await dbManager.getDatabase()

        return try await db.read { db in
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM user_resume") ?? 0
            return count > 0
        }
    }
}

/// Errors specific to resume operations
enum ResumeError: LocalizedError {
    case saveFailed
    case invalidPDF
    case fileTooLarge(maxSize: Int)

    var errorDescription: String? {
        switch self {
        case .saveFailed:
            return "Failed to save the resume to the database."
        case .invalidPDF:
            return "The selected file is not a valid PDF."
        case .fileTooLarge(let maxSize):
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            let maxSizeStr = formatter.string(fromByteCount: Int64(maxSize))
            return "The file is too large. Maximum allowed size is \(maxSizeStr)."
        }
    }
}
