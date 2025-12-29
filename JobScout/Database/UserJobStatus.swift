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
    case interested = "interested"
    case applied = "applied"
    case rejected = "rejected"
    case archived = "archived"

    var displayName: String {
        switch self {
        case .new: return "New"
        case .interested: return "Interested"
        case .applied: return "Applied"
        case .rejected: return "Rejected"
        case .archived: return "Archived"
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
    @Column("applied_at")
    var appliedAt: Date?
    @Column("created_at")
    let createdAt: Date
    @Column("updated_at")
    var updatedAt: Date
}
