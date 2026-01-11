//
//  UserResume.swift
//  JobScout
//
//  Created by Claude on 1/11/26.
//

import Foundation
import GRDB

/// Status of text extraction from the resume PDF
enum ExtractionStatus: String, Sendable, Codable {
    case pending = "pending"
    case processing = "processing"
    case completed = "completed"
    case failed = "failed"
}

/// Represents a user's uploaded resume stored in the database
struct UserResume: Identifiable, Sendable {
    let id: Int
    let fileName: String
    let pdfData: Data
    let fileSize: Int
    let uploadedAt: Date
    let createdAt: Date
    let updatedAt: Date

    // Text extraction fields
    let extractedText: String?
    let extractionStatus: ExtractionStatus
    let extractionError: String?

    /// Formatted file size for display (e.g., "1.2 MB")
    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(fileSize))
    }

    /// Whether text has been successfully extracted
    var hasExtractedText: Bool {
        extractionStatus == .completed && extractedText != nil && !extractedText!.isEmpty
    }

    /// Create from database row
    static func from(row: Row) -> UserResume {
        let statusString: String = row["extraction_status"] ?? "pending"
        let extractionStatus = ExtractionStatus(rawValue: statusString) ?? .pending

        return UserResume(
            id: row["id"],
            fileName: row["file_name"],
            pdfData: row["pdf_data"],
            fileSize: row["file_size"],
            uploadedAt: row["uploaded_at"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"],
            extractedText: row["extracted_text"],
            extractionStatus: extractionStatus,
            extractionError: row["extraction_error"]
        )
    }
}

/// Represents a chunk of text extracted from a resume
struct ResumeChunk: Identifiable, Sendable {
    let id: Int
    let resumeId: Int
    let chunkIndex: Int
    let content: String
    let characterCount: Int
    let wordCount: Int
    let createdAt: Date

    /// Create from database row
    static func from(row: Row) -> ResumeChunk {
        ResumeChunk(
            id: row["id"],
            resumeId: row["resume_id"],
            chunkIndex: row["chunk_index"],
            content: row["content"],
            characterCount: row["character_count"],
            wordCount: row["word_count"],
            createdAt: row["created_at"]
        )
    }
}
