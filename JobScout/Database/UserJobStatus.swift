//
//  UserJobStatus.swift
//  JobScout
//
//  Created by Ilia Sazonov on 12/29/25.
//

import Foundation
import StructuredQueries

/// User's interaction status with a job posting
enum JobStatus: String, QueryBindable, Codable, Sendable, CaseIterable {
    case new = "new"
    case applied = "applied"
    case ignored = "ignored"

    var displayName: String {
        switch self {
        case .new: return "New"
        case .applied: return "Applied"
        case .ignored: return "Ignored"
        }
    }

    var symbol: String {
        switch self {
        case .new: return ""
        case .applied: return "✓"
        case .ignored: return "✗"
        }
    }
}

/// Tracks user's status/interaction with a specific job posting
@Table("user_job_status")
struct UserJobStatus: Identifiable, Sendable {
    let id: Int
    @Column("job_id")
    var jobId: Int
    var status: JobStatus
    var notes: String?
    @Column("status_changed_at")
    var statusChangedAt: Date?
    @Column("created_at")
    let createdAt: Date
    @Column("updated_at")
    var updatedAt: Date
}
