import CryptoKit
import Document
import Export
import Foundation
import Render

/// Local associations for automatic exports. The output path never travels in a project file.
public actor LinkedExports {
    public struct Format: Codable, Sendable {
        public let type: String
        public let scaleFactor: Double
        public let sRGB: Bool
        public let quality: Double

        public init(type: String, scaleFactor: Double, sRGB: Bool, quality: Double) {
            self.type = type
            self.scaleFactor = scaleFactor
            self.sRGB = sRGB
            self.quality = quality
        }
    }

    public enum Refresh: Equatable, Sendable { case unchanged, updated, detached }

    private struct Link: Codable {
        let url: URL
        let format: Format
        var size: Int
        var digest: Data
    }

    private let index: URL
    private var links: [UUID: Link]?
    private var latestRevision: [UUID: UInt64] = [:]

    public init(folder: URL) {
        index = folder.appendingPathComponent("linked-exports.json")
    }

    public func link(id: UUID, url: URL, bytes: Data, format: Format) throws {
        let resolved = url.resolvingSymlinksInPath()
        let link = Link(url: resolved, format: format, size: bytes.count, digest: Self.digest(bytes))
        guard Self.matches(link) else { return }
        var records = try load()
        records[id] = link
        try save(records)
    }

    public func contains(_ id: UUID) throws -> Bool { try load()[id] != nil }

    public func refresh(_ document: CaptureDocument, revision: UInt64) throws -> Refresh {
        var records = try load()
        guard var link = records[document.id], revision > (latestRevision[document.id] ?? 0) else { return .unchanged }
        latestRevision[document.id] = revision
        guard Self.matches(link) else {
            records.removeValue(forKey: document.id)
            try save(records)
            return .detached
        }
        let image = try DocumentRenderer.render(document)
        let formatted = try ImageExport.transformed(image, factor: link.format.scaleFactor, sRGB: link.format.sRGB)
        let bytes = try ImageExport.encode(formatted, type: link.format.type, quality: link.format.quality)
        let digest = Self.digest(bytes)
        guard link.digest != digest else { return .unchanged }
        // Rendering may take a moment. Recheck for external changes before the atomic replacement.
        guard Self.matches(link) else {
            records.removeValue(forKey: document.id)
            try save(records)
            return .detached
        }
        try bytes.write(to: link.url, options: .atomic)
        link.digest = digest
        link.size = bytes.count
        records[document.id] = link
        links = records
        try save(records)
        return .updated
    }

    private func load() throws -> [UUID: Link] {
        if let links { return links }
        guard FileManager.default.fileExists(atPath: index.path) else {
            links = [:]
            return [:]
        }
        let records = try JSONDecoder().decode([UUID: Link].self, from: Data(contentsOf: index))
        links = records
        return records
    }

    private func save(_ records: [UUID: Link]) throws {
        try FileManager.default.createDirectory(at: index.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(records).write(to: index, options: .atomic)
        links = records
    }

    private static func matches(_ link: Link) -> Bool {
        guard link.url.isFileURL, link.url.resolvingSymlinksInPath() == link.url,
              let information = try? FileManager.default.attributesOfItem(atPath: link.url.path),
              information[.type] as? FileAttributeType == .typeRegular,
              (information[.size] as? NSNumber)?.intValue == link.size,
              let bytes = try? Data(contentsOf: link.url, options: .mappedIfSafe) else { return false }
        return digest(bytes) == link.digest
    }

    private static func digest(_ bytes: Data) -> Data { Data(SHA256.hash(data: bytes)) }
}
