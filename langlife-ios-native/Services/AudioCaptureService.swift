import AVFoundation
import Foundation

final class AudioCaptureService {
    private let audioEngine = AVAudioEngine()
    private var audioConverter: AVAudioConverter?
    private(set) var isCapturing = false

    var onChunk: ((String) -> Void)?
    var onChunkStats: ((AudioChunkStats) -> Void)?

    private static let targetSampleRate: Double = 24_000
    private static let targetChannels: AVAudioChannelCount = 1

    func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetooth]
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    func requestPermission() async -> Bool {
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                session.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    func startCapture() throws {
        guard !isCapturing else { return }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.targetSampleRate,
            channels: Self.targetChannels,
            interleaved: false
        ) else {
            throw AudioCaptureError.formatUnavailable
        }

        audioConverter = AVAudioConverter(from: inputFormat, to: targetFormat)
        guard audioConverter != nil else {
            throw AudioCaptureError.converterUnavailable
        }

        inputNode.installTap(onBus: 0, bufferSize: 2400, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isCapturing = true
    }

    func stopCapture() {
        guard isCapturing else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isCapturing = false
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let converter = audioConverter else { return }

        let frameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * Self.targetSampleRate / buffer.format.sampleRate
        )
        guard frameCapacity > 0 else { return }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.targetSampleRate,
            channels: Self.targetChannels,
            interleaved: false
        ),
        let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else {
            return
        }

        var error: NSError?
        var inputConsumed = false
        converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard error == nil, convertedBuffer.frameLength > 0 else { return }

        guard let int16Ptr = convertedBuffer.int16ChannelData?[0] else { return }
        let frameLength = Int(convertedBuffer.frameLength)
        guard frameLength > 0 else { return }

        let byteCount = frameLength * MemoryLayout<Int16>.size
        let stats = buildStats(samples: int16Ptr, frameLength: frameLength)
        onChunkStats?(stats)

        let data = Data(bytes: int16Ptr, count: byteCount)
        let base64 = data.base64EncodedString()
        onChunk?(base64)
    }

    private func buildStats(samples: UnsafeMutablePointer<Int16>, frameLength: Int) -> AudioChunkStats {
        var peak: Double = 0
        var sumSquares: Double = 0

        for index in 0..<frameLength {
            let value = Double(samples[index]) / Double(Int16.max)
            let magnitude = abs(value)
            if magnitude > peak {
                peak = magnitude
            }
            sumSquares += value * value
        }

        let epsilon = 0.000_000_1
        let rms = sqrt(sumSquares / Double(frameLength))
        let rmsDb = 20.0 * log10(max(rms, epsilon))
        let peakDb = 20.0 * log10(max(peak, epsilon))

        return AudioChunkStats(
            frameLength: frameLength,
            sampleRate: Self.targetSampleRate,
            rmsDb: rmsDb,
            peakDb: peakDb
        )
    }
}

struct AudioChunkStats {
    let frameLength: Int
    let sampleRate: Double
    let rmsDb: Double
    let peakDb: Double

    var durationSeconds: Double {
        guard sampleRate > 0 else { return 0 }
        return Double(frameLength) / sampleRate
    }
}

enum AudioCaptureError: Error {
    case formatUnavailable
    case converterUnavailable
    case permissionDenied
}
