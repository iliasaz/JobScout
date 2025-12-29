//
//  JobCategory.swift
//  JobScout
//
//  Created by Ilia Sazonov on 12/29/25.
//

import Foundation

/// Fixed taxonomy of job categories for data harmonization
enum JobCategory: String, CaseIterable, Codable, Sendable {
    case softwareEngineering = "Software Engineering"
    case dataScience = "Data Science"
    case machineLearning = "Machine Learning"
    case productManagement = "Product Management"
    case design = "Design"
    case devOps = "DevOps"
    case security = "Security"
    case mobile = "Mobile Development"
    case frontend = "Frontend"
    case backend = "Backend"
    case fullStack = "Full Stack"
    case embedded = "Embedded Systems"
    case gamedev = "Game Development"
    case other = "Other"

    /// Display name for UI
    var displayName: String {
        rawValue
    }

    /// Attempt to infer category from job role text
    static func infer(from role: String) -> JobCategory {
        let lowercased = role.lowercased()

        // Check specific patterns first
        if lowercased.contains("machine learning") || lowercased.contains("ml engineer") || lowercased.contains("ai engineer") {
            return .machineLearning
        }
        if lowercased.contains("data scien") || lowercased.contains("data analyst") {
            return .dataScience
        }
        if lowercased.contains("product manager") || lowercased.contains("product management") {
            return .productManagement
        }
        if lowercased.contains("devops") || lowercased.contains("site reliability") || lowercased.contains("sre") || lowercased.contains("platform engineer") {
            return .devOps
        }
        if lowercased.contains("security") || lowercased.contains("cybersecurity") || lowercased.contains("infosec") {
            return .security
        }
        if lowercased.contains("ios") || lowercased.contains("android") || lowercased.contains("mobile") {
            return .mobile
        }
        if lowercased.contains("frontend") || lowercased.contains("front-end") || lowercased.contains("front end") || lowercased.contains("ui engineer") {
            return .frontend
        }
        if lowercased.contains("backend") || lowercased.contains("back-end") || lowercased.contains("back end") {
            return .backend
        }
        if lowercased.contains("full stack") || lowercased.contains("fullstack") || lowercased.contains("full-stack") {
            return .fullStack
        }
        if lowercased.contains("embedded") || lowercased.contains("firmware") || lowercased.contains("hardware") {
            return .embedded
        }
        if lowercased.contains("game") || lowercased.contains("unity") || lowercased.contains("unreal") {
            return .gamedev
        }
        if lowercased.contains("design") || lowercased.contains("ux") || lowercased.contains("ui/ux") {
            return .design
        }

        // Generic software engineering
        if lowercased.contains("software") || lowercased.contains("engineer") || lowercased.contains("developer") || lowercased.contains("programmer") {
            return .softwareEngineering
        }

        return .other
    }
}
