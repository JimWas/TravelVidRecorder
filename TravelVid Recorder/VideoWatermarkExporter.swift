@preconcurrency import AVFoundation
import CoreImage
import Foundation
import UIKit

enum VideoWatermarkExportError: LocalizedError {
    case missingVideoTrack
    case invalidVideoSize
    case cannotCreateWriter
    case cannotCreateCompositionTrack
    case cannotCreateExporter
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingVideoTrack:
            return "TravelVid could not find a video track for the end card."
        case .invalidVideoSize:
            return "TravelVid could not determine the video's dimensions."
        case .cannotCreateWriter:
            return "TravelVid could not create the end-card video."
        case .cannotCreateCompositionTrack:
            return "TravelVid could not append the end card to this video."
        case .cannotCreateExporter:
            return "TravelVid could not prepare the end-card export."
        case .exportFailed(let message):
            return message
        }
    }
}

private final class WatermarkExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}

enum VideoWatermarkExporter {
    private static let endCardDuration = CMTime(seconds: 1.5, preferredTimescale: 600)
    private static let frameRate: Int32 = 30

    /// Appends a short branded card while copying the original encoded samples unchanged.
    /// The caller owns and must delete the returned temporary URL.
    static func export(inputURL: URL) async throws -> URL {
        let sourceAsset = AVURLAsset(url: inputURL)
        let sourceDuration = try await sourceAsset.load(.duration)
        guard let sourceVideoTrack = try await sourceAsset.loadTracks(withMediaType: .video).first else {
            throw VideoWatermarkExportError.missingVideoTrack
        }

        let naturalSize = try await sourceVideoTrack.load(.naturalSize)
        let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let displaySize = CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))
        guard naturalSize.width > 0, naturalSize.height > 0,
              displaySize.width > 0, displaySize.height > 0 else {
            throw VideoWatermarkExportError.invalidVideoSize
        }

        var displayTransform = preferredTransform
        displayTransform.tx -= transformedRect.minX
        displayTransform.ty -= transformedRect.minY

        let endCardURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TravelVid-end-card-\(UUID().uuidString).mov")
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TravelVid-branded-\(UUID().uuidString).mov")

        do {
            let codec = try await preferredCodec(for: sourceVideoTrack)
            try await createEndCard(
                at: endCardURL,
                naturalSize: naturalSize,
                displaySize: displaySize,
                displayTransform: displayTransform,
                preferredTransform: preferredTransform,
                codec: codec
            )

            let endCardAsset = AVURLAsset(url: endCardURL)
            guard let endCardTrack = try await endCardAsset.loadTracks(withMediaType: .video).first else {
                throw VideoWatermarkExportError.missingVideoTrack
            }
            let generatedEndCardDuration = try await endCardAsset.load(.duration)

            let composition = AVMutableComposition()
            guard let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw VideoWatermarkExportError.cannotCreateCompositionTrack
            }

            try compositionVideoTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: sourceDuration),
                of: sourceVideoTrack,
                at: .zero
            )
            try compositionVideoTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: generatedEndCardDuration),
                of: endCardTrack,
                at: sourceDuration
            )
            compositionVideoTrack.preferredTransform = preferredTransform

            if let sourceAudioTrack = try await sourceAsset.loadTracks(withMediaType: .audio).first,
               let compositionAudioTrack = composition.addMutableTrack(
                   withMediaType: .audio,
                   preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                try compositionAudioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: sourceDuration),
                    of: sourceAudioTrack,
                    at: .zero
                )
            }

            guard let exporter = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetPassthrough
            ) else {
                throw VideoWatermarkExportError.cannotCreateExporter
            }

            exporter.outputURL = outputURL
            exporter.outputFileType = .mov
            exporter.shouldOptimizeForNetworkUse = true
            let exporterBox = WatermarkExportSessionBox(exporter)

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                exporter.exportAsynchronously {
                    let completedExporter = exporterBox.session
                    switch completedExporter.status {
                    case .completed:
                        continuation.resume()
                    case .failed:
                        continuation.resume(throwing: VideoWatermarkExportError.exportFailed(
                            completedExporter.error?.localizedDescription ?? "The end-card export failed."
                        ))
                    case .cancelled:
                        continuation.resume(throwing: CancellationError())
                    default:
                        continuation.resume(throwing: VideoWatermarkExportError.exportFailed(
                            "The end-card export ended unexpectedly."
                        ))
                    }
                }
            }

            try? FileManager.default.removeItem(at: endCardURL)
            return outputURL
        } catch {
            try? FileManager.default.removeItem(at: endCardURL)
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    private static func preferredCodec(for track: AVAssetTrack) async throws -> AVVideoCodecType {
        let descriptions = try await track.load(.formatDescriptions)
        guard let description = descriptions.first else { return .h264 }
        let subtype = CMFormatDescriptionGetMediaSubType(description)
        return subtype == kCMVideoCodecType_HEVC ? .hevc : .h264
    }

    private static func createEndCard(
        at url: URL,
        naturalSize: CGSize,
        displaySize: CGSize,
        displayTransform: CGAffineTransform,
        preferredTransform: CGAffineTransform,
        codec: AVVideoCodecType
    ) async throws {
        try? FileManager.default.removeItem(at: url)

        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else {
            throw VideoWatermarkExportError.cannotCreateWriter
        }

        let width = max(2, Int(naturalSize.width.rounded()) & ~1)
        let height = max(2, Int(naturalSize.height.rounded()) & ~1)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: codec,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 1_200_000,
                    AVVideoMaxKeyFrameIntervalKey: Int(frameRate)
                ]
            ]
        )
        input.expectsMediaDataInRealTime = false
        input.transform = preferredTransform

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )

        guard writer.canAdd(input) else {
            throw VideoWatermarkExportError.cannotCreateWriter
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw VideoWatermarkExportError.exportFailed(
                writer.error?.localizedDescription ?? "The end-card encoder could not start."
            )
        }
        writer.startSession(atSourceTime: .zero)

        guard let pixelBufferPool = adaptor.pixelBufferPool else {
            writer.cancelWriting()
            throw VideoWatermarkExportError.cannotCreateWriter
        }

        let displayImage = makeEndCardImage(size: displaySize)
        guard let cgImage = displayImage.cgImage else {
            writer.cancelWriting()
            throw VideoWatermarkExportError.cannotCreateWriter
        }
        let rawImage = CIImage(cgImage: cgImage).transformed(by: displayTransform.inverted())
        let ciContext = CIContext(options: [.cacheIntermediates: false])
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let frameCount = Int(ceil(endCardDuration.seconds * Double(frameRate)))

        for frameIndex in 0..<frameCount {
            try Task.checkCancellation()
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 2_000_000)
                try Task.checkCancellation()
            }

            var optionalBuffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &optionalBuffer)
            guard status == kCVReturnSuccess, let pixelBuffer = optionalBuffer else {
                writer.cancelWriting()
                throw VideoWatermarkExportError.cannotCreateWriter
            }

            ciContext.render(
                rawImage,
                to: pixelBuffer,
                bounds: CGRect(x: 0, y: 0, width: width, height: height),
                colorSpace: colorSpace
            )
            let presentationTime = CMTime(value: CMTimeValue(frameIndex), timescale: frameRate)
            guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                writer.cancelWriting()
                throw VideoWatermarkExportError.exportFailed(
                    writer.error?.localizedDescription ?? "The end-card frame could not be written."
                )
            }
        }

        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }

        guard writer.status == .completed else {
            throw VideoWatermarkExportError.exportFailed(
                writer.error?.localizedDescription ?? "The end-card video could not be completed."
            )
        }
    }

    private static func makeEndCardImage(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let bounds = CGRect(origin: .zero, size: size)
            UIColor.black.setFill()
            context.fill(bounds)

            let shortEdge = min(size.width, size.height)
            let titleSize = min(110, max(42, shortEdge * 0.085))
            let titleFont = UIFont(name: "Nasalization", size: titleSize)
                ?? UIFont.systemFont(ofSize: titleSize, weight: .semibold)
            let title = "TravelVid Recorder"
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph,
                .kern: titleSize * 0.025
            ]
            let titleHeight = ceil((title as NSString).size(withAttributes: attributes).height * 1.3)
            let titleRect = CGRect(
                x: size.width * 0.08,
                y: (size.height - titleHeight) / 2,
                width: size.width * 0.84,
                height: titleHeight
            )
            (title as NSString).draw(in: titleRect, withAttributes: attributes)
        }
    }
}
