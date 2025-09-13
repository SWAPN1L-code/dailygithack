import SwiftUI
import Foundation
import Combine

//  - Models
struct GitHubConfig: Codable {
    var token: String
    var owner: String
    var repo: String
    var branch: String
    var commitMessage: String
    
    static let `default` = GitHubConfig(
        token: "your token here",
        owner: "SWAPN1L-code",
        repo: "text-file",
        branch: "main",
        commitMessage: "Update from SwiftUI app"
    )
}

struct ContributionEntry: Codable, Identifiable {
    var id = UUID()
    let timestamp: Date
    let message: String
    let fileSize: Int
    let success: Bool
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}

struct ContributionStats {
    var totalCommits: Int = 0
    var successfulCommits: Int = 0
    var failedCommits: Int = 0
    var totalFileSize: Int = 0
    var longestStreak: Int = 0
    var currentStreak: Int = 0
    
    var successRate: Double {
        guard totalCommits > 0 else { return 0 }
        return Double(successfulCommits) / Double(totalCommits) * 100
    }
}

//  GitHub Service
class GitHubService: ObservableObject {
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var config = GitHubConfig.default
    
    private let session = URLSession.shared
    
    func updateFile(content: String, path: String, completion: @escaping (Bool, String?) -> Void) {
        guard !config.token.isEmpty else {
            completion(false, "GitHub token is required")
            return
        }
        
        isLoading = true
        lastError = nil
        
        let apiURL = URL(string: "https://api.github.com/repos/\(config.owner)/\(config.repo)/contents/\(path)")!
        
        // Step 1: Get current SHA
        getCurrentSHA(for: apiURL) { [weak self] sha in
            // Step 2: Update file
            self?.uploadFile(content: content, sha: sha, to: apiURL, completion: completion)
        }
    }
    
    private func getCurrentSHA(for url: URL, completion: @escaping (String?) -> Void) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("token \(config.token)", forHTTPHeaderField: "Authorization")
        
        session.dataTask(with: request) { data, response, error in
            var sha: String? = nil
            
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let currentSHA = json["sha"] as? String {
                sha = currentSHA
            }
            
            DispatchQueue.main.async {
                completion(sha)
            }
        }.resume()
    }
    
    private func uploadFile(content: String, sha: String?, to url: URL, completion: @escaping (Bool, String?) -> Void) {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("token \(config.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let contentBase64 = Data(content.utf8).base64EncodedString()
        
        var json: [String: Any] = [
            "message": config.commitMessage,
            "content": contentBase64,
            "branch": config.branch
        ]
        
        if let sha = sha {
            json["sha"] = sha
        }
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: json)
        
        session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    let errorMsg = "Network error: \(error.localizedDescription)"
                    self?.lastError = errorMsg
                    completion(false, errorMsg)
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    let success = httpResponse.statusCode == 200 || httpResponse.statusCode == 201
                    
                    if !success {
                        let errorMsg = "HTTP \(httpResponse.statusCode)"
                        self?.lastError = errorMsg
                        completion(false, errorMsg)
                    } else {
                        completion(true, nil)
                    }
                }
            }
        }.resume()
    }
}

//   Log Manager
class LogManager: ObservableObject {
    @Published var entries: [ContributionEntry] = []
    @Published var stats = ContributionStats()
    
    private let logFileName = "contribution_log.json"
    private var logFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(logFileName)
    }
    
    init() {
        loadEntries()
        calculateStats()
    }
    
    func addEntry(_ entry: ContributionEntry) {
        entries.insert(entry, at: 0) // Add to beginning for reverse chronological order
        saveEntries()
        calculateStats()
    }
    
    func clearHistory() {
        entries.removeAll()
        saveEntries()
        calculateStats()
    }
    
    private func loadEntries() {
        guard let data = try? Data(contentsOf: logFileURL),
              let decodedEntries = try? JSONDecoder().decode([ContributionEntry].self, from: data) else {
            return
        }
        entries = decodedEntries
    }
    
    private func saveEntries() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: logFileURL)
    }
    
    private func calculateStats() {
        stats.totalCommits = entries.count
        stats.successfulCommits = entries.filter { $0.success }.count
        stats.failedCommits = entries.filter { !$0.success }.count
        stats.totalFileSize = entries.reduce(0) { $0 + $1.fileSize }
        
        // Calculate streaks
        calculateStreaks()
    }
    
    private func calculateStreaks() {
        let sortedEntries = entries.sorted { $0.timestamp > $1.timestamp }
        var currentStreak = 0
        var longestStreak = 0
        var tempStreak = 0
        
        let calendar = Calendar.current
        
        for (index, entry) in sortedEntries.enumerated() {
            guard entry.success else { continue }
            
            if index == 0 {
                currentStreak = 1
                tempStreak = 1
            } else {
                let prevEntry = sortedEntries[index - 1]
                let daysDiff = calendar.dateComponents([.day], from: entry.timestamp, to: prevEntry.timestamp).day ?? 0
                
                if daysDiff <= 1 {
                    tempStreak += 1
                    if index < 7 { // Only count as current streak if within last week
                        currentStreak = tempStreak
                    }
                } else {
                    longestStreak = max(longestStreak, tempStreak)
                    tempStreak = 1
                    currentStreak = index < 7 ? 1 : 0
                }
            }
        }
        
        stats.longestStreak = max(longestStreak, tempStreak)
        stats.currentStreak = currentStreak
    }
    
    func generateLogContent() -> String {
        var content = "# Contribution Log\n\n"
        content += "Generated on: \(Date())\n\n"
        content += "## Statistics\n"
        content += "- Total Commits: \(stats.totalCommits)\n"
        content += "- Success Rate: \(String(format: "%.1f", stats.successRate))%\n"
        content += "- Current Streak: \(stats.currentStreak) days\n"
        content += "- Longest Streak: \(stats.longestStreak) days\n\n"
        content += "## Recent Activity\n\n"
        
        for entry in entries.prefix(20) {
            let status = entry.success ? "✅" : "❌"
            content += "- \(status) \(entry.formattedDate): \(entry.message)\n"
        }
        
        return content
    }
}

//  Custom Message Generator
class MessageGenerator {
    static let motivationalMessages = [
        "Keep the streak alive! 🔥",
        "Consistency is key to success! 💪",
        "Another day, another commit! 🚀",
        "Building habits, one commit at a time! 🏗️",
        "Progress over perfection! ⭐",
        "Daily grind pays off! 💎",
        "Code today, celebrate tomorrow! 🎉",
        "Small steps, big dreams! 🌟",
        "Persistence beats resistance! ⚡",
        "Every commit counts! 📈"
    ]
    
    static let techQuotes = [
        "Code is poetry written in logic",
        "Debugging is like being a detective",
        "Good code is its own documentation",
        "Premature optimization is the root of evil",
        "There are only 10 types of people...",
        "It works on my machine! 🤷‍♂️",
        "Commit early, commit often",
        "Keep it simple, stupid (KISS)",
        "Don't repeat yourself (DRY)",
        "Fail fast, learn faster"
    ]
    
    static let emojiCombos = [
        "🔥💻", "⚡🚀", "💎✨", "🌟💪", "🎯📊",
        "🏆🔧", "⭐🎨", "🚀🎯", "💡⚡", "🔥⭐"
    ]
    
    static func random() -> String {
        let type = Int.random(in: 0...2)
        switch type {
        case 0:
            return motivationalMessages.randomElement()!
        case 1:
            return techQuotes.randomElement()!
        default:
            let emoji = emojiCombos.randomElement()!
            let msg = motivationalMessages.randomElement()!
            return "\(emoji) \(msg)"
        }
    }
    
    static func withStats(_ stats: ContributionStats) -> String {
        if stats.currentStreak >= 7 {
            return "🔥 Week streak! \(stats.currentStreak) days strong!"
        } else if stats.currentStreak >= 30 {
            return "🏆 Monthly streak! Absolutely crushing it!"
        } else if stats.successRate > 95 {
            return "💎 \(String(format: "%.1f", stats.successRate))% success rate - You're unstoppable!"
        } else {
            return random()
        }
    }
}

//  Main View
struct ContentView: View {
    @StateObject private var gitHubService = GitHubService()
    @StateObject private var logManager = LogManager()
    @State private var customMessage = ""
    @State private var selectedTemplate = "Daily Log"
    @State private var showingSettings = false
    @State private var showingHistory = false
    @State private var autoGenerateMessage = true
    
    let templates = ["Daily Log", "Motivation Board", "Code Diary", "Progress Tracker", "Custom"]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                headerSection
                statsSection
                messageSection
                actionButtons
                
                if gitHubService.isLoading {
                    ProgressView("Pushing to GitHub...")
                        .frame(maxWidth: .infinity)
                }
                
                if let error = gitHubService.lastError {
                    Text("❌ \(error)")
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
            .navigationTitle("Git Contribution Hack")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("History") {
                        showingHistory = true
                    }
                    
                    Button("Settings") {
                        showingSettings = true
                    }
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(config: $gitHubService.config)
        }
        .sheet(isPresented: $showingHistory) {
            HistoryView(logManager: logManager)
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "arrow.branch")
                    .foregroundColor(.green)
                    .font(.title2)
                
                Text("Daily Contribution")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            
            Text("Build your GitHub streak with style")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var statsSection: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 15) {
            StatCard(title: "Current Streak", value: "\(logManager.stats.currentStreak)", icon: "flame", color: .orange)
            StatCard(title: "Success Rate", value: "\(String(format: "%.0f", logManager.stats.successRate))%", icon: "chart.line.uptrend.xyaxis", color: .green)
            StatCard(title: "Total Commits", value: "\(logManager.stats.totalCommits)", icon: "checkmark.circle", color: .blue)
            StatCard(title: "Best Streak", value: "\(logManager.stats.longestStreak)", icon: "crown", color: .purple)
        }
    }
    
    private var messageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Commit Message")
                    .font(.headline)
                
                Spacer()
                
                Toggle("Auto-generate", isOn: $autoGenerateMessage)
            }
            
            if autoGenerateMessage {
                Picker("Template", selection: $selectedTemplate) {
                    ForEach(templates, id: \.self) { template in
                        Text(template).tag(template)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                
                Text(generateMessage())
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                    .font(.system(.body, design: .monospaced))
            } else {
                TextField("Enter custom commit message", text: $customMessage)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
        }
    }
    
    private var actionButtons: some View {
        VStack(spacing: 15) {
            Button(action: performCommit) {
                HStack {
                    if gitHubService.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "icloud.and.arrow.up")
                    }
                    Text("Push to GitHub")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(gitHubService.isLoading ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(gitHubService.isLoading || gitHubService.config.token.isEmpty)
            
            HStack(spacing: 15) {
                Button("Clear History") {
                    logManager.clearHistory()
                }
                .font(.caption)
                .foregroundColor(.red)
                
                Spacer()
                
                Button("Test Connection") {
                    testGitHubConnection()
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
        }
    }
    
    private func generateMessage() -> String {
        switch selectedTemplate {
        case "Daily Log":
            return "📅 Daily commit - \(Date().formatted(date: .abbreviated, time: .omitted))"
        case "Motivation Board":
            return MessageGenerator.withStats(logManager.stats)
        case "Code Diary":
            return "💻 Code session #\(logManager.stats.totalCommits + 1) - Keep building!"
        case "Progress Tracker":
            return "📈 Day \(logManager.stats.totalCommits + 1) of consistent coding"
        case "Custom":
            return customMessage.isEmpty ? "Custom commit message" : customMessage
        default:
            return MessageGenerator.random()
        }
    }
    
    private func performCommit() {
        let message = autoGenerateMessage ? generateMessage() : customMessage
        let content = logManager.generateLogContent()
        
        gitHubService.updateFile(content: content, path: "log.txt") { [weak logManager] success, error in
            let entry = ContributionEntry(
                timestamp: Date(),
                message: message,
                fileSize: content.count,
                success: success
            )
            
            logManager?.addEntry(entry)
        }
    }
    
    private func testGitHubConnection() {
        gitHubService.updateFile(content: "Connection test: \(Date())", path: "test.txt") { success, error in
            // Test completed
        }
    }
}

//- Supporting Views
struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                
                Spacer()
            }
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }
}

struct SettingsView: View {
    @Binding var config: GitHubConfig
    @Environment(\.dismiss) private var dismiss
    @State private var showingTokenInfo = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("GitHub Configuration") {
                    SecureField("Personal Access Token", text: $config.token)
                    
                    Button("How to get token?") {
                        showingTokenInfo = true
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                    
                    TextField("Repository Owner", text: $config.owner)
                    TextField("Repository Name", text: $config.repo)
                    TextField("Branch", text: $config.branch)
                }
                
                Section("Default Settings") {
                    TextField("Commit Message", text: $config.commitMessage)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .alert("GitHub Token", isPresented: $showingTokenInfo) {
            Button("OK") { }
        } message: {
            Text("1. Go to GitHub.com → Settings → Developer settings → Personal access tokens\n2. Generate new token with 'repo' permissions\n3. Copy and paste it here")
        }
    }
}

struct HistoryView: View {
    @ObservedObject var logManager: LogManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section("Statistics") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Success Rate:")
                            Spacer()
                            Text("\(String(format: "%.1f", logManager.stats.successRate))%")
                                .fontWeight(.bold)
                        }
                        
                        HStack {
                            Text("Current Streak:")
                            Spacer()
                            Text("\(logManager.stats.currentStreak) days")
                                .fontWeight(.bold)
                        }
                        
                        HStack {
                            Text("Best Streak:")
                            Spacer()
                            Text("\(logManager.stats.longestStreak) days")
                                .fontWeight(.bold)
                        }
                    }
                }
                
                Section("Recent Activity") {
                    ForEach(logManager.entries.prefix(50), id: \.id) { entry in
                        HStack {
                            Image(systemName: entry.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(entry.success ? .green : .red)
                            
                            VStack(alignment: .leading) {
                                Text(entry.message)
                                    .font(.body)
                                Text(entry.formattedDate)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Text("\(entry.fileSize) bytes")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
