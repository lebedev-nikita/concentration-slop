import Foundation
import Testing
@testable import ConcentrationSlop

struct YouTubeLinkTests {
    @Test(arguments: [
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://youtu.be/dQw4w9WgXcQ?si=shared",
        " youtube.com/watch?v=dQw4w9WgXcQ&list=ignored \n",
        "https://m.youtube.com/watch?v=dQw4w9WgXcQ&t=20",
        "https://www.youtube.com/shorts/dQw4w9WgXcQ",
        "https://www.youtube.com/embed/dQw4w9WgXcQ",
        "https://www.youtube.com/live/dQw4w9WgXcQ"
    ])
    func acceptsVideoLinks(_ input: String) throws {
        let link = try YouTubeLink(input)
        #expect(link.videoID == "dQw4w9WgXcQ")
        #expect(link.url.absoluteString == "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    }

    @Test(arguments: [
        "", "not a URL", "--exec=bad", "https://example.com/watch?v=dQw4w9WgXcQ",
        "https://youtube.com.evil.example/watch?v=dQw4w9WgXcQ",
        "https://youtube.com@evil.example/watch?v=dQw4w9WgXcQ",
        "https://youtube.com/playlist?list=PL123",
        "https://youtube.com/watch?v=short", "file:///tmp/video",
        "https://youtu.be/dQw4w9WgXcQ/extra", "https://youtube.com:8080/watch?v=dQw4w9WgXcQ",
        "https://youtube.com/watch?v=%3Cscript%3E"
    ])
    func rejectsOtherInputs(_ input: String) {
        #expect(throws: YouTubeLink.LinkError.self) { try YouTubeLink(input) }
    }
}
