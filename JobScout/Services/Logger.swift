//
//  Logger.swift
//  JobScout
//
//  Created by Ilia Sazonov on 12/29/25.
//

import Foundation
import Logging

/// Global logger for JobScout
/// Thread-safe singleton pattern for loggers
@MainActor
enum JobScoutLogger {
    private static var _main: Logger?
    private static var _harmonization: Logger?
    private static var _parser: Logger?
    private static var _api: Logger?
    private static var _logLevel: Logger.Level = .debug

    /// Main application logger
    nonisolated static var main: Logger {
        createLogger(label: "com.jobscout.main")
    }

    /// Harmonization-specific logger
    nonisolated static var harmonization: Logger {
        createLogger(label: "com.jobscout.harmonization")
    }

    /// Parser-specific logger
    nonisolated static var parser: Logger {
        createLogger(label: "com.jobscout.parser")
    }

    /// API-specific logger
    nonisolated static var api: Logger {
        createLogger(label: "com.jobscout.api")
    }

    /// Create a logger with the given label
    nonisolated private static func createLogger(label: String) -> Logger {
        var logger = Logger(label: label)
        logger.logLevel = .debug
        return logger
    }

    /// Configure all loggers to a specific level
    static func setLogLevel(_ level: Logger.Level) {
        _logLevel = level
    }
}
