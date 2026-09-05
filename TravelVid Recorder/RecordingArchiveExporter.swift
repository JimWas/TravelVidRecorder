import Foundation
import ZIPFoundation

enum RecordingArchiveExportError: LocalizedError {
    case noRecordings
    case recordingInProgress
    case missingRecording(String)
    case cannotStageRecording(String)

    var errorDescription: String? {
        switch self {
        case .noRecordings:
            return "There are no completed recordings to archive."
        case .recordingInProgress:
            return "Stop the current recording before creating a ZIP export."
        case .missingRecording(let name):
            return "The recording “\(name)” is no longer available."
        case .cannotStageRecording(let name):
            return "TravelVid could not prepare “\(name)” for the ZIP export."
        }
    }
}

enum RecordingArchiveExporter {
    private static let fileManager = FileManager.default

    static func createArchive(
        sessions: [RecordingSession],
        archiveProgress: Progress,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        guard sessions.contains(where: { !$0.segments.isEmpty }) else {
            throw RecordingArchiveExportError.noRecordings
        }

        return try await Task.detached(priority: .userInitiated) {
            try createArchiveSynchronously(
                sessions: sessions,
                archiveProgress: archiveProgress,
                onProgress: onProgress
            )
        }.value
    }

    static func removeArchive(at url: URL?) {
        guard let url else { return }
        try? fileManager.removeItem(at: url)
    }

    static func removeStaleArchives() {
        let directory = exportDirectory
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for file in files {
            let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if modified.map({ $0 < cutoff }) ?? false {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    private static func createArchiveSynchronously(
        sessions: [RecordingSession],
        archiveProgress: Progress,
        onProgress: @escaping @Sendable (Double) -> Void
    ) throws -> URL {
        try checkCancellation(archiveProgress)
        removeStaleArchives()

        let identifier = UUID().uuidString
        let workingDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("TravelVidArchiveWork", isDirectory: true)
            .appendingPathComponent(identifier, isDirectory: true)
        let archiveRoot = workingDirectory
            .appendingPathComponent(exportBaseName(), isDirectory: true)
        let outputURL = uniqueOutputURL()

        try fileManager.createDirectory(at: archiveRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        do {
            let manifests = try stageSessions(
                sessions,
                in: archiveRoot,
                progress: archiveProgress,
                onProgress: onProgress
            )
            try writeRootFiles(manifests: manifests, sessions: sessions, to: archiveRoot)
            try checkCancellation(archiveProgress)

            let observation = archiveProgress.observe(\.fractionCompleted, options: [.initial, .new]) { progress, _ in
                onProgress(0.10 + (progress.fractionCompleted * 0.90))
            }
            defer { observation.invalidate() }

            try fileManager.zipItem(
                at: archiveRoot,
                to: outputURL,
                shouldKeepParent: true,
                compressionMethod: .none,
                progress: archiveProgress
            )
            try checkCancellation(archiveProgress)
            onProgress(1)
            try? fileManager.removeItem(at: workingDirectory)
            return outputURL
        } catch {
            try? fileManager.removeItem(at: workingDirectory)
            try? fileManager.removeItem(at: outputURL)
            if archiveProgress.isCancelled || Task.isCancelled {
                throw CancellationError()
            }
            throw error
        }
    }

    private static func stageSessions(
        _ sessions: [RecordingSession],
        in archiveRoot: URL,
        progress: Progress,
        onProgress: @escaping @Sendable (Double) -> Void
    ) throws -> [ArchiveSessionManifest] {
        let segmentCount = max(1, sessions.reduce(0) { $0 + $1.segments.count })
        var stagedSegments = 0
        var manifests: [ArchiveSessionManifest] = []

        for (sessionOffset, session) in sessions.enumerated() {
            try checkCancellation(progress)
            let folderName = sessionFolderName(session, fallbackIndex: sessionOffset + 1)
            let sessionDirectory = archiveRoot.appendingPathComponent(folderName, isDirectory: true)
            try fileManager.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)

            for recording in session.segments.sorted(by: { $0.segmentIndex < $1.segmentIndex }) {
                try checkCancellation(progress)
                guard fileManager.fileExists(atPath: recording.url.path) else {
                    throw RecordingArchiveExportError.missingRecording(recording.name)
                }

                let segmentName = String(format: "Segment-%04d.mov", recording.segmentIndex)
                let stagedURL = sessionDirectory.appendingPathComponent(segmentName)
                do {
                    // A hard link gives the archiver the desired folder structure without making
                    // a second full-size copy of an already large video file.
                    try fileManager.linkItem(at: recording.url, to: stagedURL)
                } catch {
                    throw RecordingArchiveExportError.cannotStageRecording(recording.name)
                }

                stagedSegments += 1
                onProgress((Double(stagedSegments) / Double(segmentCount)) * 0.10)
            }

            let manifest = ArchiveSessionManifest(session: session, folderName: folderName)
            manifests.append(manifest)
            try writeJSON(manifest, to: sessionDirectory.appendingPathComponent("session.json"))

            if let route = session.sharedLocationPath, route.count >= 2 {
                let geoJSON = RouteGeoJSON(session: session, points: route)
                try writeJSON(geoJSON, to: sessionDirectory.appendingPathComponent("route.geojson"))
            }
        }

        return manifests
    }

    private static func writeRootFiles(
        manifests: [ArchiveSessionManifest],
        sessions: [RecordingSession],
        to archiveRoot: URL
    ) throws {
        let manifest = ArchiveManifest(
            exportedAt: Date(),
            sessionCount: manifests.count,
            videoCount: sessions.reduce(0) { $0 + $1.segments.count },
            totalDurationSeconds: sessions.reduce(0) { $0 + $1.totalDuration },
            totalBytes: sessions.reduce(0) { $0 + $1.totalSize },
            sessions: manifests
        )
        try writeJSON(manifest, to: archiveRoot.appendingPathComponent("manifest.json"))

        let readme = """
        TravelVid Recorder Export

        Each folder represents one recording session. Original safety segments are stored as
        Segment-0001.mov, Segment-0002.mov, and so on. session.json contains session details and
        GPS samples. When a route has at least two points, route.geojson can be opened by mapping
        software on your Mac.

        The original recordings remain in TravelVid Recorder after this archive is shared.
        """
        try readme.write(
            to: archiveRoot.appendingPathComponent("README.txt"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private static func checkCancellation(_ progress: Progress) throws {
        if progress.isCancelled || Task.isCancelled {
            throw CancellationError()
        }
    }

    private static var exportDirectory: URL {
        fileManager.temporaryDirectory.appendingPathComponent("TravelVidExports", isDirectory: true)
    }

    private static func uniqueOutputURL() -> URL {
        exportDirectory.appendingPathComponent("\(exportBaseName())-\(UUID().uuidString.prefix(6)).zip")
    }

    private static func exportBaseName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "TravelVid-Export-\(formatter.string(from: Date()))"
    }

    private static func sessionFolderName(_ session: RecordingSession, fallbackIndex: Int) -> String {
        let identifierSuffix = session.id
            .filter { $0.isLetter || $0.isNumber }
            .prefix(8)
        guard let date = session.startDate else {
            return String(format: "Session-%03d-%@", fallbackIndex, String(identifierSuffix))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "Session-\(formatter.string(from: date))-\(identifierSuffix)"
    }
}

private struct ArchiveManifest: Encodable, Sendable {
    let formatVersion = 1
    let appName = "TravelVid Recorder"
    let exportedAt: Date
    let sessionCount: Int
    let videoCount: Int
    let totalDurationSeconds: TimeInterval
    let totalBytes: Int64
    let sessions: [ArchiveSessionManifest]
}

private struct ArchiveSessionManifest: Encodable, Sendable {
    let id: String
    let folderName: String
    let startDate: Date?
    let durationSeconds: TimeInterval
    let totalBytes: Int64
    let address: String?
    let latitude: Double?
    let longitude: Double?
    let route: [LocationPoint]
    let segments: [ArchiveSegmentManifest]

    init(session: RecordingSession, folderName: String) {
        self.id = session.id
        self.folderName = folderName
        self.startDate = session.startDate
        self.durationSeconds = session.totalDuration
        self.totalBytes = session.totalSize
        self.address = session.address
        self.latitude = session.latitude
        self.longitude = session.longitude
        self.route = session.sharedLocationPath ?? []
        self.segments = session.segments
            .sorted { $0.segmentIndex < $1.segmentIndex }
            .map(ArchiveSegmentManifest.init)
    }
}

private struct ArchiveSegmentManifest: Encodable, Sendable {
    let filename: String
    let originalFilename: String
    let segmentIndex: Int
    let durationSeconds: TimeInterval
    let bytes: Int64
    let createdAt: Date?
    let latitude: Double?
    let longitude: Double?
    let address: String?

    init(recording: Recording) {
        self.filename = String(format: "Segment-%04d.mov", recording.segmentIndex)
        self.originalFilename = recording.name
        self.segmentIndex = recording.segmentIndex
        self.durationSeconds = recording.duration
        self.bytes = recording.size
        self.createdAt = recording.creation
        self.latitude = recording.latitude
        self.longitude = recording.longitude
        self.address = recording.address
    }
}

private struct RouteGeoJSON: Encodable, Sendable {
    let type = "FeatureCollection"
    let features: [Feature]

    init(session: RecordingSession, points: [LocationPoint]) {
        self.features = [
            Feature(
                properties: Properties(
                    sessionID: session.id,
                    startDate: session.startDate,
                    address: session.address
                ),
                geometry: Geometry(
                    coordinates: points.map { [$0.longitude, $0.latitude] }
                )
            )
        ]
    }

    struct Feature: Encodable, Sendable {
        let type = "Feature"
        let properties: Properties
        let geometry: Geometry
    }

    struct Properties: Encodable, Sendable {
        let sessionID: String
        let startDate: Date?
        let address: String?
    }

    struct Geometry: Encodable, Sendable {
        let type = "LineString"
        let coordinates: [[Double]]
    }
}
