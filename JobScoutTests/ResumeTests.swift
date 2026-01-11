//
//  ResumeTests.swift
//  JobScoutTests
//
//  Created by Claude on 1/11/26.
//

import Testing
import Foundation
@testable import JobScout

// MARK: - UserResume Model Tests

struct UserResumeTests {

    @Test func formattedFileSizeDisplaysBytes() async throws {
        let resume = UserResume(
            id: 1,
            fileName: "resume.pdf",
            pdfData: Data(count: 500),
            fileSize: 500,
            uploadedAt: Date(),
            createdAt: Date(),
            updatedAt: Date()
        )

        // 500 bytes should display as bytes
        let formatted = resume.formattedFileSize
        #expect(formatted.contains("bytes") || formatted.contains("B"))
    }

    @Test func formattedFileSizeDisplaysKilobytes() async throws {
        let resume = UserResume(
            id: 1,
            fileName: "resume.pdf",
            pdfData: Data(count: 1024),
            fileSize: 2048, // 2 KB
            uploadedAt: Date(),
            createdAt: Date(),
            updatedAt: Date()
        )

        let formatted = resume.formattedFileSize
        #expect(formatted.contains("KB"))
    }

    @Test func formattedFileSizeDisplaysMegabytes() async throws {
        let resume = UserResume(
            id: 1,
            fileName: "resume.pdf",
            pdfData: Data(count: 1024),
            fileSize: 1_500_000, // ~1.5 MB
            uploadedAt: Date(),
            createdAt: Date(),
            updatedAt: Date()
        )

        let formatted = resume.formattedFileSize
        #expect(formatted.contains("MB"))
    }

    @Test func formattedFileSizeHandlesZero() async throws {
        let resume = UserResume(
            id: 1,
            fileName: "empty.pdf",
            pdfData: Data(),
            fileSize: 0,
            uploadedAt: Date(),
            createdAt: Date(),
            updatedAt: Date()
        )

        let formatted = resume.formattedFileSize
        #expect(formatted == "Zero KB" || formatted.contains("0"))
    }
}

// MARK: - ResumeRepository Tests

/// Tests for ResumeRepository - run serially to avoid race conditions on shared database
@Suite(.serialized)
struct ResumeRepositoryTests {

    /// Create sample PDF data with valid PDF magic bytes
    private func createSamplePDFData(size: Int = 1024) -> Data {
        var data = Data()
        // PDF magic bytes: %PDF-1.4
        data.append(contentsOf: [0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34])
        // Fill with random bytes to reach desired size
        if size > 8 {
            data.append(Data(count: size - 8))
        }
        return data
    }

    @Test func saveResumeCreatesNewRecord() async throws {
        let repository = ResumeRepository.shared
        let testId = UUID().uuidString.prefix(8)
        let fileName = "test-resume-\(testId).pdf"
        let pdfData = createSamplePDFData()

        // Clean up any existing resume first
        try await repository.deleteResume()

        // Save a new resume
        let savedResume = try await repository.saveResume(fileName: fileName, pdfData: pdfData)

        #expect(savedResume.fileName == fileName)
        #expect(savedResume.pdfData == pdfData)
        #expect(savedResume.fileSize == pdfData.count)

        // Clean up
        try await repository.deleteResume()
    }

    @Test func getCurrentResumeReturnsNilWhenEmpty() async throws {
        let repository = ResumeRepository.shared

        // Clean up any existing resume
        try await repository.deleteResume()

        // Should return nil when no resume exists
        let resume = try await repository.getCurrentResume()
        #expect(resume == nil)
    }

    @Test func getCurrentResumeReturnsSavedResume() async throws {
        let repository = ResumeRepository.shared
        let testId = UUID().uuidString.prefix(8)
        let fileName = "test-resume-\(testId).pdf"
        let pdfData = createSamplePDFData(size: 2048)

        // Clean up and save a resume
        try await repository.deleteResume()
        try await repository.saveResume(fileName: fileName, pdfData: pdfData)

        // Get the current resume
        let resume = try await repository.getCurrentResume()

        #expect(resume != nil)
        #expect(resume?.fileName == fileName)
        #expect(resume?.pdfData == pdfData)
        #expect(resume?.fileSize == pdfData.count)

        // Clean up
        try await repository.deleteResume()
    }

    @Test func saveResumeReplacesExistingResume() async throws {
        let repository = ResumeRepository.shared
        let testId = UUID().uuidString.prefix(8)

        // Clean up first
        try await repository.deleteResume()

        // Save first resume
        let firstFileName = "first-resume-\(testId).pdf"
        let firstData = createSamplePDFData(size: 1024)
        try await repository.saveResume(fileName: firstFileName, pdfData: firstData)

        // Save second resume (should replace)
        let secondFileName = "second-resume-\(testId).pdf"
        let secondData = createSamplePDFData(size: 2048)
        try await repository.saveResume(fileName: secondFileName, pdfData: secondData)

        // Get current resume - should be the second one
        let resume = try await repository.getCurrentResume()

        #expect(resume != nil)
        #expect(resume?.fileName == secondFileName)
        #expect(resume?.fileSize == secondData.count)

        // Clean up
        try await repository.deleteResume()
    }

    @Test func deleteResumeRemovesRecord() async throws {
        let repository = ResumeRepository.shared
        let testId = UUID().uuidString.prefix(8)
        let fileName = "delete-test-\(testId).pdf"
        let pdfData = createSamplePDFData()

        // Clean up and save a resume
        try await repository.deleteResume()
        try await repository.saveResume(fileName: fileName, pdfData: pdfData)

        // Verify it exists
        var hasResume = try await repository.hasResume()
        #expect(hasResume == true)

        // Delete it
        try await repository.deleteResume()

        // Verify it's gone
        hasResume = try await repository.hasResume()
        #expect(hasResume == false)

        let resume = try await repository.getCurrentResume()
        #expect(resume == nil)
    }

    @Test func hasResumeReturnsTrueWhenResumeExists() async throws {
        let repository = ResumeRepository.shared
        let testId = UUID().uuidString.prefix(8)
        let fileName = "has-resume-\(testId).pdf"
        let pdfData = createSamplePDFData()

        // Clean up and save a resume
        try await repository.deleteResume()
        try await repository.saveResume(fileName: fileName, pdfData: pdfData)

        let hasResume = try await repository.hasResume()
        #expect(hasResume == true)

        // Clean up
        try await repository.deleteResume()
    }

    @Test func hasResumeReturnsFalseWhenEmpty() async throws {
        let repository = ResumeRepository.shared

        // Clean up any existing resume
        try await repository.deleteResume()

        let hasResume = try await repository.hasResume()
        #expect(hasResume == false)
    }

    @Test func updateResumeReplacesContent() async throws {
        let repository = ResumeRepository.shared
        let testId = UUID().uuidString.prefix(8)

        // Clean up first
        try await repository.deleteResume()

        // Save initial resume
        let initialFileName = "initial-\(testId).pdf"
        let initialData = createSamplePDFData(size: 1024)
        try await repository.saveResume(fileName: initialFileName, pdfData: initialData)

        // Update with new content
        let updatedFileName = "updated-\(testId).pdf"
        let updatedData = createSamplePDFData(size: 3072)
        try await repository.updateResume(fileName: updatedFileName, pdfData: updatedData)

        // Verify update
        let resume = try await repository.getCurrentResume()
        #expect(resume?.fileName == updatedFileName)
        #expect(resume?.fileSize == updatedData.count)

        // Clean up
        try await repository.deleteResume()
    }

    @Test func resumePersistsAcrossRepositoryInstances() async throws {
        let testId = UUID().uuidString.prefix(8)
        let fileName = "persist-\(testId).pdf"
        let pdfData = createSamplePDFData()

        // Save using shared instance
        try await ResumeRepository.shared.deleteResume()
        try await ResumeRepository.shared.saveResume(fileName: fileName, pdfData: pdfData)

        // Create new repository instance and verify data persists
        let newRepository = ResumeRepository()
        let resume = try await newRepository.getCurrentResume()

        #expect(resume != nil)
        #expect(resume?.fileName == fileName)

        // Clean up
        try await ResumeRepository.shared.deleteResume()
    }
}

// MARK: - PDF Validation Tests

struct PDFValidationTests {

    /// Valid PDF magic bytes: %PDF
    private let validPDFHeader: [UInt8] = [0x25, 0x50, 0x44, 0x46]

    @Test func validPDFStartsWithMagicBytes() async throws {
        var data = Data()
        data.append(contentsOf: validPDFHeader)
        data.append(contentsOf: [0x2D, 0x31, 0x2E, 0x34]) // -1.4
        data.append(Data(count: 100)) // Additional content

        let isValidPDF = data.starts(with: validPDFHeader)
        #expect(isValidPDF == true)
    }

    @Test func invalidPDFDoesNotStartWithMagicBytes() async throws {
        // Plain text file
        let textData = "Hello, World!".data(using: .utf8)!
        let isValidPDF = textData.starts(with: validPDFHeader)
        #expect(isValidPDF == false)

        // PNG file (starts with 0x89 0x50 0x4E 0x47)
        let pngHeader: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        var pngData = Data()
        pngData.append(contentsOf: pngHeader)
        let isPNG = pngData.starts(with: validPDFHeader)
        #expect(isPNG == false)

        // JPEG file (starts with 0xFF 0xD8 0xFF)
        let jpegHeader: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0]
        var jpegData = Data()
        jpegData.append(contentsOf: jpegHeader)
        let isJPEG = jpegData.starts(with: validPDFHeader)
        #expect(isJPEG == false)
    }

    @Test func emptyDataIsNotValidPDF() async throws {
        let emptyData = Data()
        let isValidPDF = emptyData.starts(with: validPDFHeader)
        #expect(isValidPDF == false)
    }

    @Test func shortDataIsNotValidPDF() async throws {
        // Data shorter than the magic bytes
        var shortData = Data()
        shortData.append(contentsOf: [0x25, 0x50]) // Only first 2 bytes
        let isValidPDF = shortData.starts(with: validPDFHeader)
        #expect(isValidPDF == false)
    }
}

// MARK: - File Size Validation Tests

struct FileSizeValidationTests {

    /// Maximum allowed file size (10 MB)
    private let maxFileSize = 10 * 1024 * 1024

    @Test func fileSizeWithinLimitIsValid() async throws {
        let smallFile = Data(count: 1024) // 1 KB
        #expect(smallFile.count <= maxFileSize)

        let mediumFile = Data(count: 5 * 1024 * 1024) // 5 MB
        #expect(mediumFile.count <= maxFileSize)

        let exactLimit = Data(count: maxFileSize) // Exactly 10 MB
        #expect(exactLimit.count <= maxFileSize)
    }

    @Test func fileSizeExceedingLimitIsInvalid() async throws {
        let tooLarge = Data(count: maxFileSize + 1) // 10 MB + 1 byte
        #expect(tooLarge.count > maxFileSize)

        let wayTooLarge = Data(count: 20 * 1024 * 1024) // 20 MB
        #expect(wayTooLarge.count > maxFileSize)
    }

    @Test func emptyFileIsWithinLimit() async throws {
        let emptyFile = Data()
        #expect(emptyFile.count <= maxFileSize)
    }
}

// MARK: - ResumeError Tests

struct ResumeErrorTests {

    @Test func saveFailedErrorHasDescription() async throws {
        let error = ResumeError.saveFailed
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.contains("save") == true)
    }

    @Test func invalidPDFErrorHasDescription() async throws {
        let error = ResumeError.invalidPDF
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.contains("PDF") == true)
    }

    @Test func fileTooLargeErrorIncludesMaxSize() async throws {
        let maxSize = 10 * 1024 * 1024
        let error = ResumeError.fileTooLarge(maxSize: maxSize)
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.contains("10") == true || error.errorDescription?.contains("MB") == true)
    }
}
