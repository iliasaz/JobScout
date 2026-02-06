//
//  Logger.swift
//  JobScout
//
//  Created by Ilia Sazonov on 12/29/25.
//

import Foundation
import Logging

/// Global loggers for JobScout using swift-log
/// Access via JobScoutLogger.main, .database, .harmonization, .parser, .api
enum JobScoutLogger {
    /// Main application logger
    static let main = Logger(label: "com.jobscout.main")
    
    /// Database operations logger
    static let database = Logger(label: "com.jobscout.database")
    
    /// Harmonization-specific logger
    static let harmonization = Logger(label: "com.jobscout.harmonization")
    
    /// Parser-specific logger
    static let parser = Logger(label: "com.jobscout.parser")
    
    /// API-specific logger
    static let api = Logger(label: "com.jobscout.api")
}
