import AVFoundation
import CoreVideo
import Foundation

/// Small movies written for the tests (ADR-037 §3): H.264 frames of one colour at 2 fps, and a
/// silent AAC track, so a long one stays quick to write and to export.
enum TestMovie {
    /// A `.mov` of `seconds`, `width` × `height`, with sound unless `audio` is false.
    static func make(seconds: Int, width: Int = 320, height: Int = 240, audio: Bool = true) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-movie-\(UUID()).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        video.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(video)
        let sound = audio ? AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
        ]) : nil
        if let sound {
            sound.expectsMediaDataInRealTime = false
            writer.add(sound)
        }
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)

        // Each track pulled by the writer when it is ready for more: it interleaves both, and
        // pushing one ahead of the other would stall it.
        let fps: Int32 = 2
        let pixels = adaptor
        let lastFrame = Int(fps) * seconds
        let tracks = [
            Track(input: video, queue: "test-movie.video") { frame in
                guard frame <= lastFrame, let buffer = try? pixelBuffer(width: width, height: height, shade: UInt8(frame % 200)) else {
                    return false
                }
                return pixels.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
            },
        ] + (sound.map { sound in
            [Track(input: sound, queue: "test-movie.audio") { second in
                guard second < seconds, let sample = try? silence(at: second) else { return false }
                return sound.append(sample)
            }]
        } ?? [])
        await withTaskGroup(of: Void.self) { group in
            for track in tracks {
                group.addTask { await track.run() }
            }
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        return url
    }

    private static let sampleRate = 44_100

    /// One input fed from its own queue: `append(n)` writes the n-th sample and returns false
    /// once there is none left (or the writer refused it).
    private struct Track: @unchecked Sendable {
        let input: AVAssetWriterInput
        let queue: String
        let append: (Int) -> Bool

        func run() async {
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                let next = Counter()
                input.requestMediaDataWhenReady(on: DispatchQueue(label: queue)) {
                    while input.isReadyForMoreMediaData, !next.finished {
                        if !append(next.value) {
                            next.finished = true
                            input.markAsFinished()
                            done.resume()
                            return
                        }
                        next.value += 1
                    }
                }
            }
        }
    }

    private final class Counter: @unchecked Sendable {
        var value = 0
        var finished = false
    }

    private static func pixelBuffer(width: Int, height: Int, shade: UInt8) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
        guard let buffer else { throw CocoaError(.fileWriteUnknown) }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            memset(base, Int32(shade), CVPixelBufferGetDataSize(buffer))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    /// One second of 16-bit mono silence starting at `second`.
    private static func silence(at second: Int) throws -> CMSampleBuffer {
        var description = AudioStreamBasicDescription(
            mSampleRate: Float64(sampleRate), mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1,
            mBitsPerChannel: 16, mReserved: 0
        )
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, asbd: &description, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format
        )
        let byteCount = sampleRate * 2
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: byteCount, blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil, offsetToData: 0, dataLength: byteCount, flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &block
        )
        guard let format, let block else { throw CocoaError(.fileWriteUnknown) }
        CMBlockBufferFillDataBytes(with: 0, blockBuffer: block, offsetIntoDestination: 0, dataLength: byteCount)
        var sample: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format, sampleCount: sampleRate,
            presentationTimeStamp: CMTime(value: CMTimeValue(second * sampleRate), timescale: CMTimeScale(sampleRate)),
            packetDescriptions: nil, sampleBufferOut: &sample
        )
        guard let sample else { throw CocoaError(.fileWriteUnknown) }
        return sample
    }
}
