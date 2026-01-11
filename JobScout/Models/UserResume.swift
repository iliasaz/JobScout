//
//  UserResume.swift
//  JobScout
//
//  Created by Claude on 1/11/26.
//

import Foundation
import GRDB

/// Represents a user's uploaded resume stored in the database
struct UserResume: Identifiable, Sendable {
    let id: Int
    let fileName: String
    let pdfData: Data
    let fileSize: Int
    let uploadedAt: Date
    let createdAt: Date
    let updatedAt: Date

    /// Formatted file size for display (e.g., "1.2 MB")
    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(fileSize))
    }

    /// Create from database row
    static func from(row: Row) -> UserResume {
        UserResume(
            id: row["id"],
            fileName: row["file_name"],
            pdfData: row["pdf_data"],
            fileSize: row["file_size"],
            uploadedAt: row["uploaded_at"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }
}
