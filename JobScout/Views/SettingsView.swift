//
//  SettingsView.swift
//  JobScout
//
//  Created by Ilia Sazonov on 12/29/25.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Settings view for configuring API keys and app preferences
struct SettingsView: View {
    @State private var openRouterAPIKey: String = ""
    @State private var isLoading = true
    @State private var saveStatus: SaveStatus = .idle
    @State private var enableHarmonization = true
    @State private var maxRowsToIngest: Int = 0
    @State private var maxRowsText: String = ""
    @State private var enableAnalysis = true
    @State private var maxParallelAnalysis: Int = 3

    // ScrapingDog API key state
    @State private var scrapingDogAPIKey: String = ""
    @State private var scrapingDogSaveStatus: SaveStatus = .idle

    // RapidAPI key state
    @State private var rapidAPIKey: String = ""
    @State private var rapidAPISaveStatus: SaveStatus = .idle

    // LinkedIn rate limit setting (requests per minute)
    @State private var linkedInRateLimit: Int = 10

    // Resume upload state
    @State private var currentResume: UserResume?
    @State private var resumeUploadStatus: ResumeUploadStatus = .idle
    @State private var isLoadingResume = true
    @State private var chunkCount: Int = 0
    @State private var isExtracting = false

    private let keychainService = KeychainService.shared
    private let resumeRepository = ResumeRepository.shared
    private let resumeTextService = ResumeTextService.shared

    /// Maximum allowed resume file size (10 MB)
    private let maxResumeFileSize = 10 * 1024 * 1024

    enum ResumeUploadStatus: Equatable {
        case idle
        case uploading
        case success
        case error(String)
    }

    /// Key for storing max rows setting in UserDefaults
    static let maxRowsKey = "maxRowsToIngest"

    /// Key for storing LinkedIn rate limit in UserDefaults (requests per minute)
    static let linkedInRateLimitKey = "linkedInRateLimit"

    /// Default LinkedIn rate limit (10 requests per minute)
    static let defaultLinkedInRateLimit = 10

    enum SaveStatus: Equatable {
        case idle
        case saving
        case saved
        case error(String)
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SecureField("API Key", text: $openRouterAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isLoading)

                        Button(action: saveAPIKey) {
                            switch saveStatus {
                            case .saving:
                                ProgressView()
                                    .controlSize(.small)
                            case .saved:
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            default:
                                Text("Save")
                            }
                        }
                        .disabled(openRouterAPIKey.isEmpty || saveStatus == .saving)
                    }

                    Text("Get your API key from [openrouter.ai/keys](https://openrouter.ai/keys)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if case .error(let message) = saveStatus {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            } header: {
                Text("OpenRouter API")
            } footer: {
                Text("OpenRouter provides access to Claude and other AI models for intelligent data harmonization.")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SecureField("API Key", text: $scrapingDogAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isLoading)

                        Button(action: saveScrapingDogAPIKey) {
                            switch scrapingDogSaveStatus {
                            case .saving:
                                ProgressView()
                                    .controlSize(.small)
                            case .saved:
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            default:
                                Text("Save")
                            }
                        }
                        .disabled(scrapingDogAPIKey.isEmpty || scrapingDogSaveStatus == .saving)
                    }

                    Text("Get your API key from [scrapingdog.com](https://www.scrapingdog.com)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if case .error(let message) = scrapingDogSaveStatus {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            } header: {
                Text("ScrapingDog API")
            } footer: {
                Text("ScrapingDog enables LinkedIn job search directly within JobScout.")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SecureField("API Key", text: $rapidAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isLoading)

                        Button(action: saveRapidAPIKey) {
                            switch rapidAPISaveStatus {
                            case .saving:
                                ProgressView()
                                    .controlSize(.small)
                            case .saved:
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            default:
                                Text("Save")
                            }
                        }
                        .disabled(rapidAPIKey.isEmpty || rapidAPISaveStatus == .saving)
                    }

                    Text("Get your API key from [rapidapi.com](https://rapidapi.com/bebity/api/fresh-linkedin-scraper-api)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if case .error(let message) = rapidAPISaveStatus {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            } header: {
                Text("RapidAPI (Fresh LinkedIn Scraper)")
            } footer: {
                Text("RapidAPI provides enriched LinkedIn job search with salary data, Easy Apply detection, and more filters.")
            }

            Section {
                Stepper("Rate Limit: \(linkedInRateLimit) requests/min", value: $linkedInRateLimit, in: 1...60)
                    .onChange(of: linkedInRateLimit) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: Self.linkedInRateLimitKey)
                    }
            } header: {
                Text("LinkedIn Fetch Settings")
            } footer: {
                Text("Controls how often JobScout fetches LinkedIn pages during analysis. Lower values are safer but slower.")
            }

            Section {
                Toggle("Enable AI Harmonization", isOn: $enableHarmonization)
                    .onChange(of: enableHarmonization) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "enableHarmonization")
                    }

                if enableHarmonization {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("When enabled, JobScout will use AI to:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("  - Infer semantic job categories")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("  - Normalize date formats")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("  - Classify company vs aggregator links")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Data Harmonization")
            }

            Section {
                Toggle("Enable Background Analysis", isOn: $enableAnalysis)
                    .onChange(of: enableAnalysis) { _, newValue in
                        JobAnalysisService.shared.updateSettings(
                            enabled: newValue,
                            maxParallel: maxParallelAnalysis
                        )
                    }

                if enableAnalysis {
                    Stepper(
                        "Parallel job limit: \(maxParallelAnalysis)",
                        value: $maxParallelAnalysis,
                        in: 1...10
                    )
                    .onChange(of: maxParallelAnalysis) { _, newValue in
                        JobAnalysisService.shared.updateSettings(
                            enabled: enableAnalysis,
                            maxParallel: newValue
                        )
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("When enabled, JobScout will automatically:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("  - Fetch job descriptions from job pages")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("  - Extract technologies and skills")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("  - Extract salary and compensation info")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("  - Generate job summaries")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Job Description Analysis")
            } footer: {
                Text("Processing happens in the background after jobs are saved.")
            }

            Section {
                HStack {
                    Text("Maximum rows to ingest")
                    Spacer()
                    TextField("0", text: $maxRowsText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: maxRowsText) { _, newValue in
                            // Only allow numeric input
                            let filtered = newValue.filter { $0.isNumber }
                            if filtered != newValue {
                                maxRowsText = filtered
                            }
                            // Save to UserDefaults
                            if let value = Int(filtered) {
                                maxRowsToIngest = value
                                UserDefaults.standard.set(value, forKey: Self.maxRowsKey)
                            } else if filtered.isEmpty {
                                maxRowsToIngest = 0
                                UserDefaults.standard.set(0, forKey: Self.maxRowsKey)
                            }
                        }
                }
            } header: {
                Text("Parsing")
            } footer: {
                Text("Set to 0 for no limit. Useful for testing with large job lists.")
            }

            Section {
                if isLoadingResume {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading...")
                            .foregroundStyle(.secondary)
                    }
                } else if let resume = currentResume {
                    // Display current resume info
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundStyle(.red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(resume.fileName)
                                    .fontWeight(.medium)
                                Text(resume.formattedFileSize)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(action: selectResumeFile) {
                                Text("Replace")
                            }
                            .disabled(resumeUploadStatus == .uploading || isExtracting)

                            Button(action: deleteResume) {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                            .disabled(resumeUploadStatus == .uploading || isExtracting)
                        }

                        Text("Uploaded: \(resume.uploadedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        // Extraction status
                        HStack(spacing: 4) {
                            switch resume.extractionStatus {
                            case .pending:
                                Image(systemName: "clock")
                                    .foregroundStyle(.orange)
                                Text("Text extraction pending")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            case .processing:
                                ProgressView()
                                    .controlSize(.small)
                                Text("Extracting text...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            case .completed:
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Text extracted • \(chunkCount) chunks")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            case .failed:
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                Text(resume.extractionError ?? "Extraction failed")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }

                        // Retry button if extraction failed
                        if resume.extractionStatus == .failed || resume.extractionStatus == .pending {
                            Button(action: { extractTextFromResume(resume) }) {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text(resume.extractionStatus == .failed ? "Retry Extraction" : "Extract Text")
                                }
                                .font(.caption)
                            }
                            .disabled(isExtracting)
                        }
                    }
                } else {
                    // No resume uploaded yet
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No resume uploaded")
                                .foregroundStyle(.secondary)
                            Text("Upload a PDF file to use with job applications")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(action: selectResumeFile) {
                            HStack {
                                Image(systemName: "arrow.up.doc")
                                Text("Upload PDF")
                            }
                        }
                        .disabled(resumeUploadStatus == .uploading)
                    }
                }

                if resumeUploadStatus == .uploading {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Uploading...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if case .success = resumeUploadStatus {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Resume uploaded successfully")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                if case .error(let message) = resumeUploadStatus {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            } header: {
                Text("Resume")
            } footer: {
                Text("Your resume is stored locally and can be used when applying to jobs. Maximum file size: 10 MB.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 700)
        .onAppear {
            loadSettings()
            loadResume()
        }
    }

    private func loadSettings() {
        Task {
            do {
                if let key = try await keychainService.getOpenRouterAPIKey() {
                    await MainActor.run {
                        openRouterAPIKey = key
                    }
                }
            } catch {
                // Key not found or error - leave empty
            }

            do {
                if let key = try await keychainService.getScrapingDogAPIKey() {
                    await MainActor.run {
                        scrapingDogAPIKey = key
                    }
                }
            } catch {
                // Key not found or error - leave empty
            }

            do {
                if let key = try await keychainService.getRapidAPIKey() {
                    await MainActor.run {
                        rapidAPIKey = key
                    }
                }
            } catch {
                // Key not found or error - leave empty
            }

            await MainActor.run {
                enableHarmonization = UserDefaults.standard.bool(forKey: "enableHarmonization")
                // Default to true if not set
                if !UserDefaults.standard.bool(forKey: "enableHarmonizationSet") {
                    enableHarmonization = true
                    UserDefaults.standard.set(true, forKey: "enableHarmonization")
                    UserDefaults.standard.set(true, forKey: "enableHarmonizationSet")
                }

                // Load max rows setting
                maxRowsToIngest = UserDefaults.standard.integer(forKey: Self.maxRowsKey)
                maxRowsText = String(maxRowsToIngest)

                // Load analysis settings
                if UserDefaults.standard.object(forKey: JobAnalysisService.enabledKey) != nil {
                    enableAnalysis = UserDefaults.standard.bool(forKey: JobAnalysisService.enabledKey)
                } else {
                    enableAnalysis = true
                }

                let parallelSetting = UserDefaults.standard.integer(forKey: JobAnalysisService.maxParallelKey)
                maxParallelAnalysis = parallelSetting > 0 ? parallelSetting : 3

                // Load LinkedIn rate limit setting
                let rateLimitSetting = UserDefaults.standard.integer(forKey: Self.linkedInRateLimitKey)
                linkedInRateLimit = rateLimitSetting > 0 ? rateLimitSetting : Self.defaultLinkedInRateLimit

                isLoading = false
            }
        }
    }

    private func saveAPIKey() {
        saveStatus = .saving

        Task {
            do {
                try await keychainService.saveOpenRouterAPIKey(openRouterAPIKey)

                await MainActor.run {
                    saveStatus = .saved
                }

                // Reset status after delay
                try? await Task.sleep(for: .seconds(2))

                await MainActor.run {
                    saveStatus = .idle
                }
            } catch {
                await MainActor.run {
                    saveStatus = .error(error.localizedDescription)
                }
            }
        }
    }

    private func saveScrapingDogAPIKey() {
        scrapingDogSaveStatus = .saving

        Task {
            do {
                try await keychainService.saveScrapingDogAPIKey(scrapingDogAPIKey)

                await MainActor.run {
                    scrapingDogSaveStatus = .saved
                }

                // Reset status after delay
                try? await Task.sleep(for: .seconds(2))

                await MainActor.run {
                    scrapingDogSaveStatus = .idle
                }
            } catch {
                await MainActor.run {
                    scrapingDogSaveStatus = .error(error.localizedDescription)
                }
            }
        }
    }

    private func saveRapidAPIKey() {
        rapidAPISaveStatus = .saving

        Task {
            do {
                try await keychainService.saveRapidAPIKey(rapidAPIKey)

                await MainActor.run {
                    rapidAPISaveStatus = .saved
                }

                // Reset status after delay
                try? await Task.sleep(for: .seconds(2))

                await MainActor.run {
                    rapidAPISaveStatus = .idle
                }
            } catch {
                await MainActor.run {
                    rapidAPISaveStatus = .error(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Resume Methods

    private func loadResume() {
        Task {
            do {
                let resume = try await resumeRepository.getCurrentResume()
                let count = try await resumeRepository.getChunkCount()
                await MainActor.run {
                    currentResume = resume
                    chunkCount = count
                    isLoadingResume = false
                }

                // Auto-extract if pending and not already extracted
                if let resume = resume, resume.extractionStatus == .pending {
                    extractTextFromResume(resume)
                }
            } catch {
                await MainActor.run {
                    isLoadingResume = false
                }
            }
        }
    }

    private func selectResumeFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.pdf]
        panel.message = "Select a PDF resume to upload"
        panel.prompt = "Upload"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                uploadResume(from: url)
            }
        }
    }

    private func uploadResume(from url: URL) {
        resumeUploadStatus = .uploading

        Task {
            do {
                // Read the file data
                let data = try Data(contentsOf: url)

                // Check file size
                guard data.count <= maxResumeFileSize else {
                    await MainActor.run {
                        resumeUploadStatus = .error("File is too large. Maximum size is 10 MB.")
                    }
                    return
                }

                // Validate it's a PDF
                guard data.starts(with: [0x25, 0x50, 0x44, 0x46]) else { // %PDF magic bytes
                    await MainActor.run {
                        resumeUploadStatus = .error("The selected file is not a valid PDF.")
                    }
                    return
                }

                let fileName = url.lastPathComponent

                // Save to database
                let savedResume = try await resumeRepository.saveResume(fileName: fileName, pdfData: data)

                await MainActor.run {
                    currentResume = savedResume
                    chunkCount = 0
                    resumeUploadStatus = .success
                }

                // Reset success status after delay
                try? await Task.sleep(for: .seconds(2))

                await MainActor.run {
                    resumeUploadStatus = .idle
                }

                // Trigger text extraction
                extractTextFromResume(savedResume)
            } catch {
                await MainActor.run {
                    resumeUploadStatus = .error(error.localizedDescription)
                }
            }
        }
    }

    private func deleteResume() {
        Task {
            do {
                try await resumeRepository.deleteResume()
                await MainActor.run {
                    currentResume = nil
                    chunkCount = 0
                }
            } catch {
                await MainActor.run {
                    resumeUploadStatus = .error("Failed to delete resume: \(error.localizedDescription)")
                }
            }
        }
    }

    private func extractTextFromResume(_ resume: UserResume) {
        guard !isExtracting else { return }

        Task {
            await MainActor.run {
                isExtracting = true
            }

            // Update status to processing
            try? await resumeRepository.updateExtractionStatus(resumeId: resume.id, status: .processing)

            // Refresh the view to show processing status
            if let updatedResume = try? await resumeRepository.getCurrentResume() {
                await MainActor.run {
                    currentResume = updatedResume
                }
            }

            do {
                // Extract text and create chunks
                let (text, chunks) = try await resumeTextService.extractAndChunk(from: resume.pdfData)

                // Save to database
                try await resumeRepository.saveExtractedTextAndChunks(
                    resumeId: resume.id,
                    text: text,
                    chunks: chunks
                )

                // Refresh the view
                let updatedResume = try await resumeRepository.getCurrentResume()
                let count = try await resumeRepository.getChunkCount()

                await MainActor.run {
                    currentResume = updatedResume
                    chunkCount = count
                    isExtracting = false
                }
            } catch {
                // Update status to failed
                try? await resumeRepository.updateExtractionStatus(
                    resumeId: resume.id,
                    status: .failed,
                    error: error.localizedDescription
                )

                // Refresh the view
                if let updatedResume = try? await resumeRepository.getCurrentResume() {
                    await MainActor.run {
                        currentResume = updatedResume
                        isExtracting = false
                    }
                } else {
                    await MainActor.run {
                        isExtracting = false
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
