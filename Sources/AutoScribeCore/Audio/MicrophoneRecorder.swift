import AVFoundation
import Foundation

public final class MicrophoneRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let fileLock = NSLock()
    private var audioFile: AVAudioFile?
    private var outputURL: URL?
    private var firstBufferContinuation: CheckedContinuation<Bool, Never>?
    private var didReceiveFirstBuffer = false

    public var onAudioLevel: ((Float) -> Void)?

    public init() {}

    public func start(in directory: URL) async throws -> URL {
        guard outputURL == nil else {
            throw AudioCaptureError.alreadyRecording
        }

        guard await requestMicrophoneAccess() else {
            throw AudioCaptureError.microphonePermissionDenied
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let input = engine.inputNode
        let url = directory.appendingPathComponent("microphone.wav")

        engine.stop()
        engine.reset()
        input.removeTap(onBus: 0)

        outputURL = url
        didReceiveFirstBuffer = false
        input.installTap(onBus: 0, bufferSize: 4_096, format: nil) { [weak self] buffer, _ in
            guard let self else {
                return
            }

            do {
                let file = try self.audioFile(for: buffer, url: url)
                try file.write(from: buffer)
                self.markFirstBufferReceived()
                self.onAudioLevel?(buffer.rootMeanSquarePower)
            } catch {
                self.onAudioLevel?(0)
            }
        }

        engine.prepare()
        try engine.start()

        return url
    }

    public func waitForFirstBuffer(timeoutSeconds: TimeInterval) async -> Bool {
        if didReceiveFirstBuffer {
            return true
        }

        return await withTaskGroup(of: Bool.self) { group in
            group.addTask { [weak self] in
                guard let self else {
                    return false
                }
                return await withCheckedContinuation { continuation in
                    self.fileLock.lock()
                    if self.didReceiveFirstBuffer {
                        self.fileLock.unlock()
                        continuation.resume(returning: true)
                    } else {
                        self.firstBufferContinuation = continuation
                        self.fileLock.unlock()
                    }
                }
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                return false
            }

            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }

    public func stop() throws -> URL {
        guard let outputURL else {
            throw AudioCaptureError.notRecording
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        resumeFirstBufferContinuationIfNeeded()
        audioFile = nil
        self.outputURL = nil
        return outputURL
    }

    private func markFirstBufferReceived() {
        fileLock.lock()
        didReceiveFirstBuffer = true
        let continuation = firstBufferContinuation
        firstBufferContinuation = nil
        fileLock.unlock()
        continuation?.resume(returning: true)
    }

    private func resumeFirstBufferContinuationIfNeeded() {
        fileLock.lock()
        let continuation = firstBufferContinuation
        firstBufferContinuation = nil
        fileLock.unlock()
        continuation?.resume(returning: false)
    }

    private func audioFile(for buffer: AVAudioPCMBuffer, url: URL) throws -> AVAudioFile {
        fileLock.lock()
        defer { fileLock.unlock() }

        if let audioFile {
            return audioFile
        }

        let format = buffer.format
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioCaptureError.writerUnavailable
        }

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        audioFile = file
        return file
    }

    private func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

}

private extension AVAudioPCMBuffer {
    var rootMeanSquarePower: Float {
        guard let channelData = floatChannelData, frameLength > 0 else {
            return 0
        }

        let frameCount = Int(frameLength)
        let channelCount = Int(format.channelCount)
        let frameStride = 16
        var sum: Float = 0
        var sampledCount = 0

        for channel in 0..<channelCount {
            let samples = channelData[channel]
            var frame = 0
            while frame < frameCount {
                let sample = samples[frame]
                sum += sample * sample
                sampledCount += 1
                frame += frameStride
            }
        }

        let mean = sum / Float(max(sampledCount, 1))
        return sqrt(mean)
    }
}
