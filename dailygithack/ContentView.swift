import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Daily Git Hack")
                .font(.largeTitle)
                .padding()
            
            Button(action: {
                appendToLocalLog()
                pushToGitHub()
            }) {
                Text("Push File to GitHub")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .frame(width: 400, height: 200)
    }
}

func appendToLocalLog() {
    let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("text-file/log.txt")
    
    let message = "\(Date()): Button clicked!\n"
    
    do {
        let folderURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let fileHandle = try FileHandle(forWritingTo: fileURL)
            fileHandle.seekToEndOfFile()
            if let data = message.data(using: .utf8) {
                fileHandle.write(data)
            }
            fileHandle.closeFile()
        } else {
            try message.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        
        print("✅ Local log updated!")
    } catch {
        print("❌ Error updating local log:", error)
    }
}

func pushToGitHub() {
    let token = "your pat"  // 🔑 replace with your token
    let owner = "SWAPN1L-code"
    let repo = "text-file"
    let path = "log.txt"
    
    let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("text-file/log.txt")
    
    guard let fileData = try? Data(contentsOf: fileURL) else {
        print("❌ Could not read file")
        return
    }
    
    let contentBase64 = fileData.base64EncodedString()
    let apiurl = URL(string: "https://api.github.com/repos/SWAPN1L-code/text-file/contents/log.txt")!

    
    // Step 1: Get the current SHA (if file exists)
    var sha: String? = nil
    let semaphore = DispatchSemaphore(value: 0)
    
    var shaRequest = URLRequest(url: apiurl)
    shaRequest.httpMethod = "GET"
    shaRequest.setValue("token \(token)", forHTTPHeaderField: "Authorization")
    
    URLSession.shared.dataTask(with: shaRequest) { data, response, error in
        if let data = data,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let currentSHA = json["sha"] as? String {
            sha = currentSHA
        }
        semaphore.signal()
    }.resume()
    
    semaphore.wait()
    
    // Step 2: Upload the file
    var request = URLRequest(url: apiurl)
    request.httpMethod = "PUT"
    request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    var json: [String: Any] = [
        "message": "Update log from SwiftUI app",
        "content": contentBase64
    ]
    if let sha = sha {
        json["sha"] = sha
    }
    
    request.httpBody = try? JSONSerialization.data(withJSONObject: json)
    
    URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            print("❌ GitHub API error:", error)
            return
        }
        
        if let response = response as? HTTPURLResponse {
            print("📡 GitHub response:", response.statusCode)
        }
        
        if let data = data, let str = String(data: data, encoding: .utf8) {
            print("🔍 Response data:", str)
        }
    }.resume()
}


