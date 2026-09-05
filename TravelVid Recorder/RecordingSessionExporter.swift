@preconcurrency import AVFoundation
import Foundation

enum RecordingSessionExportError: LocalizedError {
    case noSegments
    case missingVideo(String)
    case cannotCreateCompositionTrack
    case cannotCreateExporter
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .noSegments:
            return "This recording session has no video segments."
        case .missingVideo(let filename):
            return "The video track in \(filename) could not be read."
        case .cannotCreateCompositionTrack:
            return "TravelVid could not prepare the combined video tracks."
        case .cannotCreateExporter:
            return "TravelVid could not create the combined video export."
        case .exportFailed(let message):
            return message
        }
    }
}

/// AVAssetExportSession's callback API predates Swift concurrency. The export session is only
/// read from its own completion callback, so this narrowly scoped box bridges that API safely.
private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}

enum RecordingSessionExporter {
    static func combine(_ session: RecordingSession) async throws -> URL {
        guard !session.segments.isEmpty else {
            throw RecordingSessionExportError.noSegments
        }

        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw RecordingSessionExportError.cannotCreateCompositionTrack
        }

        let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        var insertionTime = CMTime.zero
        var appliedVideoTransform = false

        for segment in session.segments {
            let asset = AVURLAsset(url: segment.url)
            let duration = try await asset.load(.duration)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let videoTrack = videoTracks.first else {
                throw RecordingSessionExportError.missingVideo(segment.name)
            }

            let timeRange = CMTimeRange(start: .zero, duration: duration)
            try compositionVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: insertionTime)

            if !appliedVideoTransform {
                compositionVideoTrack.preferredTransform = try await videoTrack.load(.preferredTransform)
                appliedVideoTransform = true
            }

            if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first,
               let compositionAudioTrack {
                try compositionAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: insertionTime)
            }

            insertionTime = CMTimeAdd(insertionTime, duration)
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TravelVid-session-\(session.id)-\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: outputURL)

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw RecordingSessionExportError.cannotCreateExporter
        }

        exporter.outputURL = outputURL
        exporter.outputFileType = .mov
        exporter.shouldOptimizeForNetworkUse = true
        let exporterBox = ExportSessionBox(exporter)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            exporter.exportAsynchronously {
                let completedExporter = exporterBox.session
                switch completedExporter.status {
                case .completed:
                    continuation.resume()
                case .failed:
                    continuation.resume(throwing: RecordingSessionExportError.exportFailed(
                        completedExporter.error?.localizedDescription ?? "The combined video export failed."
                    ))
                case .cancelled:
                    continuation.resume(throwing: RecordingSessionExportError.exportFailed("The combined video export was cancelled."))
                default:
                    continuation.resume(throwing: RecordingSessionExportError.exportFailed("The combined video export ended unexpectedly."))
                }
            }
        }

        return outputURL
    }
}
