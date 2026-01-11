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

    // MARK: - Resume CRUD Operations

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
            // Delete any existing chunks first (foreign key constraint)
            try db.execute(sql: "DELETE FROM resume_chunks")

            // Delete any existing resume (we only keep one)
            try db.execute(sql: "DELETE FROM user_resume")

            // Insert the new resume with pending extraction status
            try db.execute(sql: """
                INSERT INTO user_resume (file_name, pdf_data, file_size, extraction_status, uploaded_at, created_at, updated_at)
                VALUES (?, ?, ?, 'pending', datetime('now'), datetime('now'), datetime('now'))
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

    /// Delete the current resume and its chunks
    func deleteResume() async throws {
        let db = try await dbManager.getDatabase()

        try await db.write { db in
            // Delete chunks first (foreign key constraint)
            try db.execute(sql: "DELETE FROM resume_chunks")
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

    // MARK: - Text Extraction Operations

    /// Update the extraction status for a resume
    func updateExtractionStatus(resumeId: Int, status: ExtractionStatus, error: String? = nil) async throws {
        let db = try await dbManager.getDatabase()

        try await db.write { db in
            if let error = error {
                try db.execute(sql: """
                    UPDATE user_resume SET
                        extraction_status = ?,
                        extraction_error = ?,
                        updated_at = datetime('now')
                    WHERE id = ?
                    """, arguments: [status.rawValue, error, resumeId])
            } else {
                try db.execute(sql: """
                    UPDATE user_resume SET
                        extraction_status = ?,
                        extraction_error = NULL,
                        updated_at = datetime('now')
                    WHERE id = ?
                    """, arguments: [status.rawValue, resumeId])
            }
        }
    }

    /// Save extracted text for a resume
    func saveExtractedText(resumeId: Int, text: String) async throws {
        let db = try await dbManager.getDatabase()

        try await db.write { db in
            try db.execute(sql: """
                UPDATE user_resume SET
                    extracted_text = ?,
                    extraction_status = 'completed',
                    extraction_error = NULL,
                    updated_at = datetime('now')
                WHERE id = ?
                """, arguments: [text, resumeId])
        }
    }

    /// Get the extracted text for the current resume
    func getExtractedText() async throws -> String? {
        let db = try await dbManager.getDatabase()

        return try await db.read { db in
            try String.fetchOne(db, sql: """
                SELECT extracted_text FROM user_resume ORDER BY uploaded_at DESC LIMIT 1
                """)
        }
    }

    // MARK: - Chunk Operations

    /// Save chunks for a resume, replacing any existing chunks
    func saveChunks(resumeId: Int, chunks: [TextChunk]) async throws {
        let db = try await dbManager.getDatabase()

        try await db.write { db in
            // Delete existing chunks for this resume
            try db.execute(sql: "DELETE FROM resume_chunks WHERE resume_id = ?", arguments: [resumeId])

            // Insert new chunks
            for chunk in chunks {
                try db.execute(sql: """
                    INSERT INTO resume_chunks (resume_id, chunk_index, content, character_count, word_count, created_at)
                    VALUES (?, ?, ?, ?, ?, datetime('now'))
                    """, arguments: [
                        resumeId,
                        chunk.index,
                        chunk.content,
                        chunk.characterCount,
                        chunk.wordCount
                    ])
            }
        }
    }

    /// Get all chunks for the current resume
    func getChunks() async throws -> [ResumeChunk] {
        let db = try await dbManager.getDatabase()

        return try await db.read { db in
            // First get the current resume ID
            guard let resumeId = try Int.fetchOne(db, sql: """
                SELECT id FROM user_resume ORDER BY uploaded_at DESC LIMIT 1
                """) else {
                return []
            }

            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM resume_chunks WHERE resume_id = ? ORDER BY chunk_index ASC
                """, arguments: [resumeId])

            return rows.map { ResumeChunk.from(row: $0) }
        }
    }

    /// Get chunks for a specific resume
    func getChunks(forResumeId resumeId: Int) async throws -> [ResumeChunk] {
        let db = try await dbManager.getDatabase()

        return try await db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM resume_chunks WHERE resume_id = ? ORDER BY chunk_index ASC
                """, arguments: [resumeId])

            return rows.map { ResumeChunk.from(row: $0) }
        }
    }

    /// Get the count of chunks for the current resume
    func getChunkCount() async throws -> Int {
        let db = try await dbManager.getDatabase()

        return try await db.read { db in
            guard let resumeId = try Int.fetchOne(db, sql: """
                SELECT id FROM user_resume ORDER BY uploaded_at DESC LIMIT 1
                """) else {
                return 0
            }

            return try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM resume_chunks WHERE resume_id = ?
                """, arguments: [resumeId]) ?? 0
        }
    }

    // MARK: - Combined Operations

    /// Save extracted text and chunks in a single transaction
    func saveExtractedTextAndChunks(resumeId: Int, text: String, chunks: [TextChunk]) async throws {
        let db = try await dbManager.getDatabase()

        try await db.write { db in
            // Update resume with extracted text
            try db.execute(sql: """
                UPDATE user_resume SET
                    extracted_text = ?,
                    extraction_status = 'completed',
                    extraction_error = NULL,
                    updated_at = datetime('now')
                WHERE id = ?
                """, arguments: [text, resumeId])

            // Delete existing chunks
            try db.execute(sql: "DELETE FROM resume_chunks WHERE resume_id = ?", arguments: [resumeId])

            // Insert new chunks
            for chunk in chunks {
                try db.execute(sql: """
                    INSERT INTO resume_chunks (resume_id, chunk_index, content, character_count, word_count, created_at)
                    VALUES (?, ?, ?, ?, ?, datetime('now'))
                    """, arguments: [
                        resumeId,
                        chunk.index,
                        chunk.content,
                        chunk.characterCount,
                        chunk.wordCount
                    ])
            }
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
