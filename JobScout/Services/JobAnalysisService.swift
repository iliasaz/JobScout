//
//  JobAnalysisService.swift
//  JobScout
//
//  Created by Ilia Sazonov on 12/30/25.
//

import Foundation
import Logging
import Combine

private let log = Logger(label: "JobScout.JobAnalysisService")

/// Service that manages background job description analysis
@MainActor
final class JobAnalysisService: ObservableObject {
    static let shared = JobAnalysisService()

    // Published state for UI observation
    @Published private(set) var processingJobIds: Set<Int> = []
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var pendingCount: Int = 0
    @Published private(set) var completedCount: Int = 0

    // Configuration
    private var maxParallelJobs: Int = 3
    private var isEnabled: Bool = true

    // Internal state
    private var activeTaskCount: Int = 0
    private var processingTask: Task<Void, Never>?

    private let repository = JobRepository()
    private let keychainService = KeychainService.shared
    private var analyzer: JobDescriptionAnalyzerAgent?

    /// UserDefaults key for enabling background analysis
    static let enabledKey = "enableBackgroundAnalysis"
    /// UserDefaults key for max parallel jobs
    static let maxParallelKey = "maxParallelAnalysis"

    private init() {
        loadSettings()
    }

    /// Load settings from UserDefaults
    private func loadSettings() {
        // Default to enabled if not explicitly set
        if UserDefaults.standard.object(forKey: Self.enabledKey) != nil {
            isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        } else {
            isEnabled = true
        }

        maxParallelJobs = UserDefaults.standard.integer(forKey: Self.maxParallelKey)
        if maxParallelJobs == 0 {
            maxParallelJobs = 3
        }

        log.info("JobAnalysisService settings loaded", metadata: [
            "enabled": "\(isEnabled)",
            "maxParallel": "\(maxParallelJobs)"
        ])
    }

    /// Update settings
    func updateSettings(enabled: Bool, maxParallel: Int) {
        isEnabled = enabled
        maxParallelJobs = max(1, min(10, maxParallel))

        UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
        UserDefaults.standard.set(maxParallelJobs, forKey: Self.maxParallelKey)

        log.info("JobAnalysisService settings updated", metadata: [
            "enabled": "\(isEnabled)",
            "maxParallel": "\(maxParallelJobs)"
        ])

        if isEnabled && !isRunning {
            start()
        } else if !isEnabled && isRunning {
            stop()
        }
    }

    /// Start background processing
    func start() {
        guard isEnabled else {
            log.info("Background analysis is disabled")
            return
        }

        guard !isRunning else {
            log.debug("Background analysis already running")
            return
        }

        isRunning = true
        log.info("Starting background analysis service")

        processingTask = Task {
            await initializeAnalyzer()
            await processQueue()
        }
    }

    /// Stop processing
    func stop() {
        log.info("Stopping background analysis service")
        isRunning = false
        processingTask?.cancel()
        processingTask = nil
    }

    /// Queue specific jobs for analysis
    func queueJobs(_ jobIds: [Int]) async {
        guard isEnabled else { return }

        do {
            try await repository.queueJobsForAnalysis(jobIds: jobIds)
            pendingCount = try await repository.getPendingAnalysisCount()
            log.info("Queued \(jobIds.count) jobs for analysis")

            // Start processing if not already running
            if !isRunning {
                start()
            }
        } catch {
            log.error("Failed to queue jobs: \(error)")
        }
    }

    /// Queue all unanalyzed jobs
    func queueAllUnanalyzed() async {
        guard isEnabled else { return }

        do {
            let count = try await repository.queueUnanalyzedJobs()
            pendingCount = try await repository.getPendingAnalysisCount()
            log.info("Queued \(count) unanalyzed jobs")

            if !isRunning && count > 0 {
                start()
            }
        } catch {
            log.error("Failed to queue unanalyzed jobs: \(error)")
        }
    }

    // MARK: - Private Methods

    private func initializeAnalyzer() async {
        guard analyzer == nil else { return }

        do {
            if let apiKey = try await keychainService.getOpenRouterAPIKey() {
                analyzer = try JobDescriptionAnalyzerAgent(apiKey: apiKey)
                log.info("Job description analyzer initialized")
            } else {
                log.warning("No API key found - analysis will be limited to deterministic extraction")
            }
        } catch {
            log.error("Failed to initialize analyzer: \(error)")
        }
    }

    private func processQueue() async {
        log.debug("Starting process queue loop")

        while isRunning && !Task.isCancelled {
            // Check if we can process more jobs
            if activeTaskCount < maxParallelJobs {
                do {
                    if let job = try await repository.getNextPendingAnalysis() {
                        // Start processing in parallel
                        activeTaskCount += 1
                        processingJobIds.insert(job.id)

                        Task {
                            await processJob(job)

                            await MainActor.run {
                                self.activeTaskCount -= 1
                                self.processingJobIds.remove(job.id)
                            }
                        }
                    } else {
                        // No pending jobs, check again after a delay
                        pendingCount = 0
                    }
                } catch {
                    log.error("Error getting next job: \(error)")
                }
            }

            // Brief pause to avoid spinning
            try? await Task.sleep(for: .milliseconds(200))
        }

        log.debug("Process queue loop ended")
    }

    private func processJob(_ job: PersistedJobPosting) async {
        log.info("[\(job.id)] Processing job: \(job.role) at \(job.company)")

        do {
            // Mark as processing
            try await repository.setAnalysisStatus(jobId: job.id, status: .processing)

            // Fetch job description
            log.debug("[\(job.id)] Fetching job description")
            let description = try await fetchJobDescription(for: job)
            log.debug("[\(job.id)] Fetched description: \(description.count) characters")

            // Store raw description
            try await repository.saveJobDescription(jobId: job.id, description: description)

            // Analyze
            let result: JobDescriptionAnalysisOutput
            if let analyzer = analyzer {
                result = try await analyzer.analyze(
                    description: description,
                    role: job.role,
                    company: job.company,
                    jobId: job.id
                )
            } else {
                // No analyzer available - create empty result
                log.warning("[\(job.id)] No analyzer available - skipping LLM extraction")
                result = JobDescriptionAnalysisOutput(
                    technologies: [],
                    salary: nil,
                    stock: nil,
                    summary: nil
                )
            }

            // Save results
            try await repository.saveAnalysisResult(jobId: job.id, result: result)

            // Mark complete
            try await repository.setAnalysisStatus(jobId: job.id, status: .completed)

            await MainActor.run {
                self.completedCount += 1
                if self.pendingCount > 0 {
                    self.pendingCount -= 1
                }
            }

            log.info("[\(job.id)] Completed analysis successfully")

        } catch {
            log.error("[\(job.id)] Failed to analyze: \(error)")
            try? await repository.setAnalysisStatus(
                jobId: job.id,
                status: .failed,
                error: error.localizedDescription
            )
        }
    }

    private func fetchJobDescription(for job: PersistedJobPosting) async throws -> String {
        // Try aggregator link first (often more standardized), then company link
        let urlString = job.aggregatorLink ?? job.companyLink
        guard let urlString = urlString, let url = URL(string: urlString) else {
            log.error("[\(job.id)] No URL available for job")
            throw AnalysisError.noURL
        }

        log.debug("[\(job.id)] Fetching from \(url.host ?? "unknown"): \(urlString)")

        // Strategy 1: Try Greenhouse API if URL contains gh_jid parameter
        if let greenhouseContent = await tryGreenhouseAPI(url: url, jobId: job.id) {
            log.info("[\(job.id)] Successfully fetched from Greenhouse API")
            return greenhouseContent
        }

        // Strategy 1b: Try ICIMS direct fetch if URL is ICIMS
        if let icimsContent = await tryICIMSDirectFetch(url: url, jobId: job.id) {
            log.info("[\(job.id)] Successfully fetched from ICIMS")
            return icimsContent
        }

        // Strategy 2: Fetch HTML and try multiple extraction methods
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            log.error("[\(job.id)] HTTP fetch failed with status: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            throw AnalysisError.fetchFailed
        }

        guard let html = String(data: data, encoding: .utf8) else {
            log.error("[\(job.id)] Failed to decode HTML as UTF-8")
            throw AnalysisError.parseFailed
        }

        // Strategy 2a: Try JSON-LD extraction (schema.org JobPosting)
        if let jsonLdContent = extractJobFromJSONLD(html, jobId: job.id) {
            log.info("[\(job.id)] Successfully extracted from JSON-LD")
            return jsonLdContent
        }

        // Strategy 2b: Try to extract content from embedded iframes (ICIMS, Lever, Workday, etc.)
        if let iframeContent = await tryIframeExtraction(html: html, baseUrl: url, jobId: job.id) {
            log.info("[\(job.id)] Successfully extracted from iframe")
            return iframeContent
        }

        // Strategy 2c: Try to find embedded Greenhouse board and fetch from API
        if let boardToken = extractGreenhouseBoardToken(from: html),
           let greenhouseJobId = extractGreenhouseJobId(from: url) ?? extractGreenhouseJobId(from: html) {
            if let greenhouseContent = await fetchFromGreenhouseAPI(board: boardToken, jobId: greenhouseJobId, logJobId: job.id) {
                log.info("[\(job.id)] Successfully fetched from embedded Greenhouse board")
                return greenhouseContent
            }
        }

        // Strategy 3: Fall back to HTML text extraction
        log.debug("[\(job.id)] Falling back to HTML text extraction")
        let extractedText = extractTextFromHTML(html)
        log.debug("[\(job.id)] Extracted \(extractedText.count) characters from HTML")
        return extractedText
    }

    // MARK: - Greenhouse API Support

    private func tryGreenhouseAPI(url: URL, jobId: Int) async -> String? {
        // Check if URL has gh_jid parameter
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let ghJobId = components.queryItems?.first(where: { $0.name == "gh_jid" })?.value else {
            return nil
        }

        log.debug("[\(jobId)] Detected Greenhouse job ID: \(ghJobId)")

        // First, fetch the page to find the board token
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let html = String(data: data, encoding: .utf8) else {
                return nil
            }

            if let boardToken = extractGreenhouseBoardToken(from: html) {
                return await fetchFromGreenhouseAPI(board: boardToken, jobId: ghJobId, logJobId: jobId)
            }
        } catch {
            log.debug("[\(jobId)] Failed to fetch page for Greenhouse detection: \(error)")
        }

        return nil
    }

    private func extractGreenhouseBoardToken(from html: String) -> String? {
        // Look for patterns like:
        // boards.greenhouse.io/embed/job_board/js?for=metrostarsystems
        // boards-api.greenhouse.io/v1/boards/metrostarsystems/jobs/
        let patterns = [
            "greenhouse\\.io/embed/job_board/js\\?for=([a-zA-Z0-9_-]+)",
            "boards-api\\.greenhouse\\.io/v1/boards/([a-zA-Z0-9_-]+)/",
            "boards\\.greenhouse\\.io/([a-zA-Z0-9_-]+)/jobs/"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(html.startIndex..., in: html)
                if let match = regex.firstMatch(in: html, options: [], range: range),
                   let tokenRange = Range(match.range(at: 1), in: html) {
                    return String(html[tokenRange])
                }
            }
        }

        return nil
    }

    private func extractGreenhouseJobId(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        return components.queryItems?.first(where: { $0.name == "gh_jid" })?.value
    }

    private func extractGreenhouseJobId(from html: String) -> String? {
        // Look for job ID in various places
        let pattern = "gh_jid[\"']?\\s*[:=]\\s*[\"']?(\\d+)"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(html.startIndex..., in: html)
            if let match = regex.firstMatch(in: html, options: [], range: range),
               let idRange = Range(match.range(at: 1), in: html) {
                return String(html[idRange])
            }
        }
        return nil
    }

    private func fetchFromGreenhouseAPI(board: String, jobId: String, logJobId: Int) async -> String? {
        let apiUrl = "https://boards-api.greenhouse.io/v1/boards/\(board)/jobs/\(jobId)"
        log.debug("[\(logJobId)] Fetching from Greenhouse API: \(apiUrl)")

        guard let url = URL(string: apiUrl) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                log.debug("[\(logJobId)] Greenhouse API returned non-200 status")
                return nil
            }

            return formatGreenhouseResponse(data, logJobId: logJobId)
        } catch {
            log.debug("[\(logJobId)] Greenhouse API fetch failed: \(error)")
            return nil
        }
    }

    private func formatGreenhouseResponse(_ data: Data, logJobId: Int) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var parts: [String] = []

        // Title
        if let title = json["title"] as? String {
            parts.append("Job Title: \(title)")
        }

        // Location
        if let location = json["location"] as? [String: Any],
           let locationName = location["name"] as? String {
            parts.append("Location: \(locationName)")
        }

        // Department
        if let departments = json["departments"] as? [[String: Any]] {
            let deptNames = departments.compactMap { $0["name"] as? String }
            if !deptNames.isEmpty {
                parts.append("Department: \(deptNames.joined(separator: ", "))")
            }
        }

        // Salary - this is key!
        if let salary = json["salary_range"] as? String {
            parts.append("Salary Range: \(salary)")
            log.debug("[\(logJobId)] Found salary in Greenhouse data: \(salary)")
        }

        // Content/Description (HTML)
        if let content = json["content"] as? String {
            let cleanedContent = extractTextFromHTML(content)
            parts.append("\nJob Description:\n\(cleanedContent)")
        }

        // Metadata
        if let metadata = json["metadata"] as? [[String: Any]] {
            for item in metadata {
                if let name = item["name"] as? String,
                   let value = item["value"] as? String ?? (item["value"] as? [String])?.joined(separator: ", ") {
                    parts.append("\(name): \(value)")
                }
            }
        }

        let result = parts.joined(separator: "\n")
        log.debug("[\(logJobId)] Greenhouse response formatted: \(result.count) characters")
        return result
    }

    // MARK: - ICIMS Support

    private func tryICIMSDirectFetch(url: URL, jobId: Int) async -> String? {
        // Check if this is an ICIMS URL
        guard let host = url.host?.lowercased(), host.contains("icims.com") else {
            return nil
        }

        log.debug("[\(jobId)] Detected ICIMS URL")

        // Build the iframe URL by adding in_iframe=1 parameter
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var queryItems = components?.queryItems ?? []

        // Check if in_iframe is already present
        if !queryItems.contains(where: { $0.name == "in_iframe" }) {
            queryItems.append(URLQueryItem(name: "in_iframe", value: "1"))
            components?.queryItems = queryItems
        }

        guard let iframeUrl = components?.url else {
            return nil
        }

        log.debug("[\(jobId)] Fetching ICIMS iframe content: \(iframeUrl.absoluteString)")

        do {
            let (data, response) = try await URLSession.shared.data(from: iframeUrl)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let html = String(data: data, encoding: .utf8) else {
                log.debug("[\(jobId)] ICIMS iframe fetch failed")
                return nil
            }

            // Try JSON-LD first from the iframe content
            if let jsonLdContent = extractJobFromJSONLD(html, jobId: jobId) {
                log.debug("[\(jobId)] Extracted JSON-LD from ICIMS iframe")
                return jsonLdContent
            }

            // Fall back to HTML extraction
            let extractedText = extractTextFromHTML(html)
            if extractedText.count > 500 {  // Only return if we got substantial content
                log.debug("[\(jobId)] Extracted \(extractedText.count) characters from ICIMS iframe")
                return extractedText
            }

            return nil
        } catch {
            log.debug("[\(jobId)] ICIMS fetch error: \(error)")
            return nil
        }
    }

    // MARK: - General Iframe Extraction

    private func tryIframeExtraction(html: String, baseUrl: URL, jobId: Int) async -> String? {
        // Look for iframes that might contain job content
        // Common patterns: ICIMS, Lever, Workday, SmartRecruiters, etc.
        let iframePattern = "<iframe[^>]*src=[\"']([^\"']+)[\"'][^>]*>"
        guard let regex = try? NSRegularExpression(pattern: iframePattern, options: .caseInsensitive) else {
            return nil
        }

        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, options: [], range: range)

        for match in matches {
            guard let srcRange = Range(match.range(at: 1), in: html) else { continue }
            var iframeSrc = String(html[srcRange])

            // Skip non-job related iframes
            let skipPatterns = ["google", "facebook", "twitter", "linkedin", "youtube", "analytics", "tracking", "ads"]
            if skipPatterns.contains(where: { iframeSrc.lowercased().contains($0) }) {
                continue
            }

            // Resolve relative URLs
            if iframeSrc.hasPrefix("/") {
                if let baseScheme = baseUrl.scheme, let baseHost = baseUrl.host {
                    iframeSrc = "\(baseScheme)://\(baseHost)\(iframeSrc)"
                }
            } else if !iframeSrc.hasPrefix("http") {
                continue  // Skip non-http URLs
            }

            guard let iframeUrl = URL(string: iframeSrc) else { continue }

            // Check if this looks like a job board iframe
            let jobBoardPatterns = ["icims.com", "lever.co", "workday.com", "smartrecruiters.com",
                                    "greenhouse.io", "myworkdayjobs.com", "taleo", "brassring"]

            guard let iframeHost = iframeUrl.host?.lowercased(),
                  jobBoardPatterns.contains(where: { iframeHost.contains($0) }) else {
                continue
            }

            log.debug("[\(jobId)] Found job board iframe: \(iframeHost)")

            // Handle ICIMS specifically
            if iframeHost.contains("icims.com") {
                var components = URLComponents(url: iframeUrl, resolvingAgainstBaseURL: false)
                var queryItems = components?.queryItems ?? []
                if !queryItems.contains(where: { $0.name == "in_iframe" }) {
                    queryItems.append(URLQueryItem(name: "in_iframe", value: "1"))
                    components?.queryItems = queryItems
                }
                if let icimsUrl = components?.url {
                    if let content = await fetchIframeContent(url: icimsUrl, jobId: jobId) {
                        return content
                    }
                }
            } else {
                // Try fetching directly for other platforms
                if let content = await fetchIframeContent(url: iframeUrl, jobId: jobId) {
                    return content
                }
            }
        }

        return nil
    }

    private func fetchIframeContent(url: URL, jobId: Int) async -> String? {
        log.debug("[\(jobId)] Fetching iframe content from: \(url.absoluteString)")

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let html = String(data: data, encoding: .utf8) else {
                return nil
            }

            // Try JSON-LD first
            if let jsonLdContent = extractJobFromJSONLD(html, jobId: jobId) {
                log.debug("[\(jobId)] Extracted JSON-LD from iframe")
                return jsonLdContent
            }

            // Fall back to HTML extraction
            let extractedText = extractTextFromHTML(html)
            if extractedText.count > 500 {
                log.debug("[\(jobId)] Extracted \(extractedText.count) characters from iframe HTML")
                return extractedText
            }

            return nil
        } catch {
            log.debug("[\(jobId)] Iframe fetch error: \(error)")
            return nil
        }
    }

    // MARK: - JSON-LD Extraction

    private func extractJobFromJSONLD(_ html: String, jobId: Int) -> String? {
        // Find all JSON-LD script tags
        let pattern = "<script[^>]*type=[\"']application/ld\\+json[\"'][^>]*>([\\s\\S]*?)</script>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, options: [], range: range)

        for match in matches {
            guard let jsonRange = Range(match.range(at: 1), in: html) else { continue }
            let jsonString = String(html[jsonRange]).trimmingCharacters(in: .whitespacesAndNewlines)

            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else {
                continue
            }

            // Handle both single object and array
            let objects: [[String: Any]]
            if let array = json as? [[String: Any]] {
                objects = array
            } else if let obj = json as? [String: Any] {
                objects = [obj]
            } else {
                continue
            }

            for obj in objects {
                // Check if this is a JobPosting
                let type = obj["@type"] as? String
                if type == "JobPosting" {
                    if let content = formatJobPostingJSONLD(obj, jobId: jobId) {
                        return content
                    }
                }
            }
        }

        return nil
    }

    private func formatJobPostingJSONLD(_ json: [String: Any], jobId: Int) -> String? {
        var parts: [String] = []

        if let title = json["title"] as? String {
            parts.append("Job Title: \(title)")
        }

        if let company = json["hiringOrganization"] as? [String: Any],
           let name = company["name"] as? String {
            parts.append("Company: \(name)")
        }

        if let location = json["jobLocation"] as? [String: Any],
           let address = location["address"] as? [String: Any] {
            let locationParts = [
                address["addressLocality"] as? String,
                address["addressRegion"] as? String,
                address["addressCountry"] as? String
            ].compactMap { $0 }
            if !locationParts.isEmpty {
                parts.append("Location: \(locationParts.joined(separator: ", "))")
            }
        }

        // Salary information
        if let baseSalary = json["baseSalary"] as? [String: Any] {
            var salaryParts: [String] = []
            if let value = baseSalary["value"] as? [String: Any] {
                if let min = value["minValue"], let max = value["maxValue"] {
                    salaryParts.append("\(min) - \(max)")
                } else if let singleValue = value["value"] {
                    salaryParts.append("\(singleValue)")
                }
            }
            if let currency = baseSalary["currency"] as? String {
                salaryParts.append(currency)
            }
            if !salaryParts.isEmpty {
                let salaryString = salaryParts.joined(separator: " ")
                parts.append("Salary: \(salaryString)")
                log.debug("[\(jobId)] Found salary in JSON-LD: \(salaryString)")
            }
        }

        if let description = json["description"] as? String {
            let cleanedDescription = extractTextFromHTML(description)
            parts.append("\nJob Description:\n\(cleanedDescription)")
        }

        if let skills = json["skills"] as? String {
            parts.append("\nSkills: \(skills)")
        }

        if let qualifications = json["qualifications"] as? String {
            parts.append("\nQualifications: \(qualifications)")
        }

        if let responsibilities = json["responsibilities"] as? String {
            parts.append("\nResponsibilities: \(responsibilities)")
        }

        guard !parts.isEmpty else { return nil }

        let result = parts.joined(separator: "\n")
        log.debug("[\(jobId)] JSON-LD formatted: \(result.count) characters")
        return result
    }

    private func extractTextFromHTML(_ html: String) -> String {
        var text = html

        // Remove script and style tags with their content
        let scriptPattern = "<script[^>]*>[\\s\\S]*?</script>"
        let stylePattern = "<style[^>]*>[\\s\\S]*?</style>"

        text = text.replacingOccurrences(of: scriptPattern, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: stylePattern, with: "", options: .regularExpression)

        // Remove HTML comments
        text = text.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: "", options: .regularExpression)

        // Replace block-level tags with newlines
        let blockTags = ["</p>", "</div>", "</li>", "</tr>", "<br>", "<br/>", "<br />"]
        for tag in blockTags {
            text = text.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
        }

        // Remove all remaining HTML tags
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

        // Decode HTML entities
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&rsquo;", with: "'")
        text = text.replacingOccurrences(of: "&lsquo;", with: "'")
        text = text.replacingOccurrences(of: "&rdquo;", with: "\"")
        text = text.replacingOccurrences(of: "&ldquo;", with: "\"")
        text = text.replacingOccurrences(of: "&mdash;", with: "—")
        text = text.replacingOccurrences(of: "&ndash;", with: "–")
        text = text.replacingOccurrences(of: "&bull;", with: "•")

        // Collapse multiple whitespace
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Error Types

enum AnalysisError: Error, LocalizedError {
    case noURL
    case fetchFailed
    case parseFailed
    case noAnalyzer

    var errorDescription: String? {
        switch self {
        case .noURL: return "No URL available for job"
        case .fetchFailed: return "Failed to fetch job page"
        case .parseFailed: return "Failed to parse job description"
        case .noAnalyzer: return "API key not configured"
        }
    }
}
