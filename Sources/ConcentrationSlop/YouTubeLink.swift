import Foundation

struct YouTubeLink: Equatable, Sendable {
    let videoID: String

    var url: URL { URL(string: "https://www.youtube.com/watch?v=\(videoID)")! }

    init(_ input: String) throws {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: candidate),
              ["https", "http"].contains(components.scheme?.lowercased() ?? ""),
              components.user == nil, components.password == nil,
              components.port == nil,
              let host = components.host?.lowercased() else {
            throw LinkError.invalid
        }
        let parts = components.path.split(separator: "/").map(String.init)
        let id: String?
        if ["youtu.be", "www.youtu.be"].contains(host), parts.count == 1 {
            id = parts[0]
        } else if ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"].contains(host) {
            if components.path == "/watch" {
                id = components.queryItems?.first(where: { $0.name == "v" })?.value
            } else if parts.count == 2, ["shorts", "embed", "live"].contains(parts[0]) {
                id = parts[1]
            } else {
                id = nil
            }
        } else {
            id = nil
        }
        guard let id, id.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil else {
            throw LinkError.invalid
        }
        videoID = id
    }

    enum LinkError: LocalizedError {
        case invalid
        var errorDescription: String? {
            "Вставьте ссылку на конкретное видео YouTube: youtube.com/watch, youtu.be или Shorts."
        }
    }
}
