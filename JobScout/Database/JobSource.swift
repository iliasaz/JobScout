//
//  JobSource.swift
//  JobScout
//
//  Created by Ilia Sazonov on 12/29/25.
//

import Foundation
import StructuredQueries

/// Represents a source URL from which jobs are fetched
@Table("job_sources")
struct JobSource: Identifiable, Sendable {
    let id: Int
    var url: String
    var name: String
    @Column("source_type")
    var sourceType: String
    @Column("last_fetched_at")
    var lastFetchedAt: Date?
    @Column("created_at")
    let createdAt: Date
}
