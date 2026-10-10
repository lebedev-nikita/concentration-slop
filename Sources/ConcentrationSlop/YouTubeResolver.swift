import Foundation

struct ResolvedVideo: Decodable, Sendable {
    let title: String
    let url: URL
    let isLive: Bool?
    let headers: [String: String]?
    var width: Double? = nil
    var height: Double? = nil

    enum CodingKeys: String, CodingKey {
        case title, url, width, height
        case isLive = "is_live"
        case headers = "http_headers"
    }
}

struct YouTubeResolver: Sendable {
    func resolve(_ link: YouTubeLink) async throws -> ResolvedVideo {
        guard let executable = Self.findExecutable("yt-dlp") else {
            throw ResolveError.missingDependency
        }
        var arguments = [
            "--ignore-config", "--no-playlist", "--no-warnings", "--skip-download",
            "--dump-single-json", "--socket-timeout", "15", "--retries", "1",
            "--extractor-retries", "1", "--format", "bv[ext=mp4][vcodec^=avc1][height<=720][protocol=https]/bv[ext=mp4][vcodec^=avc1][height<=720]/bv[ext=mp4][vcodec^=avc1]/b[ext=mp4]"
        ]
        if let deno = Self.findExecutable("deno") {
            arguments += ["--js-runtimes", "deno:\(deno.path)"]
        } else if let node = Self.findExecutable("node") {
            arguments += ["--js-runtimes", "node:\(node.path)"]
        }
        arguments += ["--", link.url.absoluteString]
        let job = ExtractionJob(executable: executable, arguments: arguments)
        let data = try await withTaskCancellationHandler {
            let output = try await Task.detached { try job.run() }.value
            try Task.checkCancellation()
            return output
        } onCancel: {
            job.cancel()
        }
        let video: ResolvedVideo
        do {
            video = try JSONDecoder().decode(ResolvedVideo.self, from: data)
        } catch {
            throw ResolveError.unavailable
        }
        guard video.url.scheme == "https" else { throw ResolveError.unavailable }
        guard video.isLive != true else { throw ResolveError.liveVideo }
        return video
    }

    static func findExecutable(_ name: String) -> URL? {
        let directories = ["/opt/homebrew/bin", "/usr/local/bin"]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return directories.lazy.map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    enum ResolveError: LocalizedError {
        case missingDependency, unavailable, liveVideo, timedOut

        var errorDescription: String? {
            switch self {
            case .missingDependency:
                "Установите yt-dlp и Deno: brew install yt-dlp deno. Затем попробуйте снова."
            case .unavailable:
                "Не удалось открыть видео. Проверьте интернет и доступность ролика. Если ошибка повторяется: brew upgrade yt-dlp deno."
            case .liveVideo:
                "Для повтора нужна запись, а не прямая трансляция. Выберите другое видео."
            case .timedOut:
                "YouTube не ответил вовремя. Проверьте интернет и попробуйте снова."
            }
        }
    }
}

// Process cancellation can arrive before launch, during extraction or after exit.
// The lock keeps those races away from Foundation's Process lifecycle.
private final class ExtractionJob: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private var cancelled = false
    private var timedOut = false

    init(executable: URL, arguments: [String]) {
        process.executableURL = executable
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (environment["PATH"] ?? "/usr/bin:/bin")
        process.environment = environment
    }

    func cancel() {
        lock.withLock {
            cancelled = true
            if process.isRunning { process.terminate() }
        }
    }

    func run() throws -> Data {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("output.json")
        let errorURL = directory.appendingPathComponent("error.txt")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputURL)
        let errors = try FileHandle(forWritingTo: errorURL)
        defer { try? output.close(); try? errors.close() }
        process.standardOutput = output
        process.standardError = errors
        try lock.withLock {
            if cancelled { throw CancellationError() }
            try process.run()
        }
        let deadline = DispatchWorkItem { [self] in
            lock.withLock {
                if process.isRunning {
                    timedOut = true
                    process.terminate()
                }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: deadline)
        defer { deadline.cancel() }
        process.waitUntilExit()
        try lock.withLock {
            if cancelled { throw CancellationError() }
            if timedOut { throw YouTubeResolver.ResolveError.timedOut }
        }
        guard process.terminationStatus == 0 else { throw YouTubeResolver.ResolveError.unavailable }
        return try Data(contentsOf: outputURL)
    }
}
