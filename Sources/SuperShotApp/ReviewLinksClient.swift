import Foundation

struct ReviewLinksEndpoint: Equatable, Sendable {
    let url: URL

    init(_ input: String) throws {
        guard var parts = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = parts.scheme?.lowercased(),
              let host = parts.host?.lowercased(), !host.isEmpty,
              parts.path.isEmpty || parts.path == "/",
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              scheme == "https" || (scheme == "http" && ["localhost", "127.0.0.1"].contains(host))
        else { throw ReviewLinksError.endpoint }
        parts.scheme = scheme
        parts.host = host
        parts.path = ""
        guard let url = parts.url else { throw ReviewLinksError.endpoint }
        self.url = url
    }

    func publicURL(_ id: String) -> URL { url.appendingPathComponent("s").appendingPathComponent(id) }
    func endpoint(_ id: String) -> URL {
        url.appendingPathComponent("api").appendingPathComponent("shares").appendingPathComponent(id)
    }
}

struct ReviewLinkReceipt: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var server: String
    var token: String
    var title: String
    var date: Date
    var uploaded: Bool

    init(server: ReviewLinksEndpoint, title: String) {
        id = Self.identifier()
        token = Self.identifier() + Self.identifier()
        self.server = server.url.absoluteString
        self.title = title
        date = .now
        uploaded = false
    }

    var publicURL: URL? { (try? ReviewLinksEndpoint(server))?.publicURL(id) }

    private static func identifier() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
}

struct ReviewLinksConfiguration: Codable, Equatable {
    var address = ""
    var uploadKey = ""
    var receipts: [ReviewLinkReceipt] = []
}

@MainActor enum ReviewLinksStore {
    private static var folder: URL {
        URL.applicationSupportDirectory.appending(path: "SuperShot/ReviewLinks", directoryHint: .isDirectory)
    }

    static func load() throws -> ReviewLinksConfiguration {
        do {
            let data = try Data(contentsOf: folder.appendingPathComponent("links.json"))
            return try JSONDecoder().decode(ReviewLinksConfiguration.self, from: data)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return ReviewLinksConfiguration()
        }
    }

    static func update(_ change: (inout ReviewLinksConfiguration) -> Void) throws {
        let files = FileManager.default
        var configuration = try load()
        change(&configuration)
        try files.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        let destination = folder.appendingPathComponent("links.json")
        try JSONEncoder().encode(configuration).write(to: destination, options: .atomic)
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }
}

enum ReviewLinksError: LocalizedError {
    case endpoint, uploadKey, asset, size, unexpectedReply, rejected(String)

    var errorDescription: String? {
        switch self {
        case .endpoint: "Enter the HTTPS address of your review server, with no path. Loopback HTTP works for local testing."
        case .uploadKey: "Enter the review server’s upload key."
        case .asset: "Choose a PNG screenshot or an MP4 or MOV recording."
        case .size: "The capture exceeds the 64 MB limit for review links."
        case .unexpectedReply: "The service did not return a valid SuperShot review response."
        case .rejected(let message): message
        }
    }
}

struct ReviewLinksClient: Sendable {
    static let mediaLimit = 64 * 1024 * 1024

    func create(_ receipt: ReviewLinkReceipt, key: String, data: Data, mime: String) async throws {
        guard !key.isEmpty, key.unicodeScalars.allSatisfy({ 33...126 ~= $0.value }) else {
            throw ReviewLinksError.uploadKey
        }
        guard data.count <= Self.mediaLimit else { throw ReviewLinksError.size }
        let server = try ReviewLinksEndpoint(receipt.server)
        var request = URLRequest(url: server.endpoint(receipt.id))
        request.httpMethod = "PUT"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue(mime, forHTTPHeaderField: "Content-Type")
        request.setValue(Data(receipt.title.utf8).base64EncodedString(), forHTTPHeaderField: "X-Share-Title-B64")
        request.setValue(receipt.token, forHTTPHeaderField: "X-Revocation-Token")
        request.httpBody = data
        let (response, body) = try await send(request)
        guard response == 200 || response == 201 else { throw rejection(response, body) }
        let payload = try? JSONDecoder().decode(UploadResponse.self, from: body)
        guard payload?.path == "/s/\(receipt.id)" else { throw ReviewLinksError.unexpectedReply }
    }

    func revoke(_ receipt: ReviewLinkReceipt) async throws {
        let server = try ReviewLinksEndpoint(receipt.server)
        var request = URLRequest(url: server.endpoint(receipt.id))
        request.httpMethod = "DELETE"
        request.setValue(receipt.token, forHTTPHeaderField: "X-Revocation-Token")
        let (response, body) = try await send(request)
        guard response == 204 else { throw rejection(response, body) }
    }

    private struct UploadResponse: Decodable { let path: String }
    private struct ErrorResponse: Decodable { let error: String }

    private func send(_ request: URLRequest) async throws -> (Int, Data) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        let session = URLSession(configuration: configuration, delegate: ReviewLinksRedirectBlocker(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (sequence, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw ReviewLinksError.unexpectedReply }
        var data = Data()
        for try await byte in sequence {
            guard data.count < 8192 else { throw ReviewLinksError.unexpectedReply }
            data.append(byte)
        }
        return (http.statusCode, data)
    }

    private func rejection(_ status: Int, _ data: Data) -> ReviewLinksError {
        let detail = try? JSONDecoder().decode(ErrorResponse.self, from: data).error
        return .rejected(detail.map { String($0.prefix(250)) } ?? "The review server returned HTTP \(status).")
    }
}

private final class ReviewLinksRedirectBlocker: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? { nil }
}
