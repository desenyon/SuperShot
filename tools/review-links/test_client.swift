// Compile alongside Sources/SuperShotApp/ReviewLinksClient.swift for an end-to-end loopback test.
import Foundation

private enum SmokeFailure: Error {
    case invalidURLAccepted, unexpectedStatus(Int), wrongMedia, missingShareURL
}

@main struct ReviewLinksSmoke {
    static func main() async throws {
        let endpoint = try ReviewLinksEndpoint(CommandLine.arguments[1])
        guard endpoint.url.host == "127.0.0.1" else { throw ReviewLinksError.endpoint }
        for invalid in ["http://reviews.example.com", "https://user@reviews.example.com",
                        "https://reviews.example.com/path", "https://reviews.example.com?private=1"] {
            if (try? ReviewLinksEndpoint(invalid)) != nil { throw SmokeFailure.invalidURLAccepted }
        }
        guard let image = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==")
        else { throw ReviewLinksError.asset }
        let receipt = ReviewLinkReceipt(server: endpoint, title: "Native review link test")
        let client = ReviewLinksClient()
        let key = String(repeating: "u", count: 40)
        try await client.create(receipt, key: key, data: image, mime: "image/png")
        try await client.create(receipt, key: key, data: image, mime: "image/png")
        guard let url = receipt.publicURL else { throw SmokeFailure.missingShareURL }
        let (stored, response) = try await URLSession.shared.data(from: url.appendingPathComponent("media"))
        try check(response, status: 200)
        guard stored == image else { throw SmokeFailure.wrongMedia }
        try await client.revoke(receipt)
        try await client.revoke(receipt)
        let (_, revoked) = try await URLSession.shared.data(from: url)
        try check(revoked, status: 404)
    }

    private static func check(_ response: URLResponse, status: Int) throws {
        let actual = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard actual == status else { throw SmokeFailure.unexpectedStatus(actual) }
    }
}
