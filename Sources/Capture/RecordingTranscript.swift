import AVFoundation
import Foundation
import Speech

public struct RecordingCue: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var text: String
    public let range: RecordingRange

    public init(id: UUID = UUID(), text: String, range: RecordingRange) {
        self.id = id
        self.text = text
        self.range = range
    }
}

public enum RecordingTranscriptFormat: String, CaseIterable, Sendable {
    case text = "txt"
    case srt
    case vtt
}

public enum RecordingTranscriptIssue: LocalizedError {
    case noAudio, unsupportedLanguage, noSpeech

    public var errorDescription: String? {
        switch self {
        case .noAudio: "Choose a recording with an audio track to make a transcript."
        case .unsupportedLanguage: "This Mac doesn’t have on-device transcription for the current language."
        case .noSpeech: "No speech was recognized in the selected track."
        }
    }
}

public enum RecordingTranscript {
    public static func transcribe(_ source: URL, trackIndex: Int, language: Locale = .current) async throws -> [RecordingCue] {
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: language) else {
            throw RecordingTranscriptIssue.unsupportedLanguage
        }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
        if let download = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await download.downloadAndInstall()
        }
        try Task.checkCancellation()

        let temporary = URL.temporaryDirectory.appending(path: UUID().uuidString).appendingPathExtension("m4a")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let offset = try await extractAudio(source, trackIndex: trackIndex, to: temporary)
        let input = try AVAudioFile(forReading: temporary)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let results = Task {
            var cues: [RecordingCue] = []
            for try await result in transcriber.results {
                try Task.checkCancellation()
                let timed = result.text.runs.compactMap { run -> RecordingCue? in
                    guard let time = run.audioTimeRange, let range = sourceRange(time, offset: offset) else { return nil }
                    let text = String(result.text[run.range].characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return nil }
                    return RecordingCue(text: text, range: range)
                }
                if !timed.isEmpty { cues.append(contentsOf: timed) }
                else if let range = sourceRange(result.range, offset: offset) {
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { cues.append(RecordingCue(text: text, range: range)) }
                }
            }
            return cues
        }
        return try await withTaskCancellationHandler {
            do {
                try await analyzer.start(inputAudioFile: input, finishAfterFile: true)
                let cues = try await results.value
                guard !cues.isEmpty else { throw RecordingTranscriptIssue.noSpeech }
                return cues.sorted { $0.range.start < $1.range.start }
            } catch {
                results.cancel()
                await analyzer.cancelAndFinishNow()
                throw error
            }
        } onCancel: {
            results.cancel()
            Task { await analyzer.cancelAndFinishNow() }
        }
    }

    private static func extractAudio(_ source: URL, trackIndex: Int, to output: URL) async throws -> TimeInterval {
        let asset = AVURLAsset(url: source)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let composition = AVMutableComposition()
        guard tracks.indices.contains(trackIndex),
              let target = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw RecordingTranscriptIssue.noAudio
        }
        let input = tracks[trackIndex]
        let range = try await input.load(.timeRange)
        try target.insertTimeRange(range, of: input, at: .zero)
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw RecordingTranscriptIssue.noAudio
        }
        try await exporter.export(to: output, as: .m4a)
        return range.start.seconds
    }

    private static func sourceRange(_ range: CMTimeRange, offset: TimeInterval) -> RecordingRange? {
        RecordingRange(start: max(0, range.start.seconds + offset), end: range.end.seconds + offset)
    }

    public static func activeCues(_ cues: [RecordingCue], in edits: RecordingEdits) -> [RecordingCue] {
        let kept = edits.kept
        return cues.sorted(by: { $0.range.start < $1.range.start }).compactMap { cue in
            let center = cue.range.start + cue.range.duration * 0.5
            guard let segment = kept.first(where: { $0.start <= center && center < $0.end }), let clip = segment.intersection(cue.range) else { return nil }
            let start = edits.editedTime(forSourceTime: clip.start)
            guard let range = RecordingRange(start: start, end: start + clip.duration) else { return nil }
            return RecordingCue(id: cue.id, text: cue.text, range: range)
        }
    }

    public static func fillerCuts(_ cues: [RecordingCue]) -> [RecordingRange] {
        let fillers: Set<String> = ["um", "uh", "erm", "umm", "uhm", "er"]
        return cues.filter { fillers.contains($0.text.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))) }
            .map(\.range)
    }

    public static func pauseCuts(_ cues: [RecordingCue]) -> [RecordingRange] {
        let sorted = cues.sorted { $0.range.start < $1.range.start }
        return zip(sorted, sorted.dropFirst()).compactMap { before, after in
            guard after.range.start - before.range.end > 0.8 else { return nil }
            return RecordingRange(start: before.range.end + 0.12, end: after.range.start - 0.12)
        }
    }

    public static func captions(_ cues: [RecordingCue], in edits: RecordingEdits) -> [RecordingCue] {
        var grouped: [RecordingCue] = []
        for cue in activeCues(cues, in: edits) {
            guard let previous = grouped.last else { grouped.append(cue); continue }
            let joined = join(previous.text, cue.text)
            guard cue.range.start - previous.range.end <= 0.55, cue.range.end - previous.range.start <= 3.5,
                  joined.count <= 58, let range = RecordingRange(start: previous.range.start, end: max(previous.range.end, cue.range.end)) else {
                grouped.append(cue)
                continue
            }
            grouped[grouped.index(before: grouped.endIndex)] = RecordingCue(id: previous.id, text: joined, range: range)
        }
        return grouped
    }

    public static func contents(_ cues: [RecordingCue], in edits: RecordingEdits, as format: RecordingTranscriptFormat) -> String {
        let captions = captions(cues, in: edits)
        switch format {
        case .text: return captions.map(\.text).joined(separator: "\n") + "\n"
        case .srt:
            return captions.enumerated().map { index, cue in
                "\(index + 1)\n\(timestamp(cue.range.start, separator: ",")) --> \(timestamp(cue.range.end, separator: ","))\n\(oneLine(cue.text))"
            }.joined(separator: "\n\n") + "\n"
        case .vtt:
            return "WEBVTT\n\n" + captions.map { cue in
                let text = oneLine(cue.text).replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                return "\(timestamp(cue.range.start, separator: ".")) --> \(timestamp(cue.range.end, separator: "."))\n\(text)"
            }.joined(separator: "\n\n") + "\n"
        }
    }

    private static func join(_ first: String, _ second: String) -> String {
        let punctuation = second.first.map { ",.!?:;…".contains($0) } ?? false
        return first + (punctuation ? "" : " ") + second
    }

    private static func oneLine(_ text: String) -> String { text.split(whereSeparator: \.isNewline).joined(separator: " ") }

    private static func timestamp(_ seconds: TimeInterval, separator: String) -> String {
        let value = Int((seconds * 1000).rounded())
        return String(format: "%02d:%02d:%02d%@%03d", value / 3_600_000, value / 60_000 % 60, value / 1000 % 60, separator, value % 1000)
    }
}
