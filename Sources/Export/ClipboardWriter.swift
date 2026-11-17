import AppKit

/// Commits asynchronously encoded data only if this remains the latest copy request
/// and the user has not copied something else in the meantime.
@MainActor public final class ClipboardWriter {
    public struct Request {
        fileprivate let generation: UInt64
        fileprivate let changeCount: Int
    }
    private let pasteboard: NSPasteboard
    private var generation: UInt64 = 0
    public init(pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }
    public func begin() -> Request {
        generation &+= 1
        return Request(generation: generation, changeCount: pasteboard.changeCount)
    }
    @discardableResult public func write(_ data: Data, type: String, for request: Request) throws -> Bool {
        guard request.generation == generation, request.changeCount == pasteboard.changeCount else { return false }
        guard !data.isEmpty else { throw ClipboardError.writeFailed }
        let item = NSPasteboardItem()
        guard item.setData(data, forType: NSPasteboard.PasteboardType(type)) else { throw ClipboardError.writeFailed }
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { throw ClipboardError.writeFailed }
        return true
    }
    public enum ClipboardError: LocalizedError {
        case writeFailed
        public var errorDescription: String? { "The image could not be copied to the clipboard. Try copying it again." }
    }
}
