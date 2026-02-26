import AVFoundation
import Foundation

final class AudioPlaybackService {
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private(set) var isPlaying = false
    private var playbackFormat: AVAudioFormat?

    private static let sampleRate: Double = 24_000
    private static let channels: AVAudioChannelCount = 1

    init() {
        audioEngine.attach(playerNode)

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: Self.channels,
            interleaved: false
        ) else { return }

        playbackFormat = format
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
    }

    func start() throws {
        guard !audioEngine.isRunning else { return }
        audioEngine.prepare()
        try audioEngine.start()
        playerNode.play()
        isPlaying = true
    }

    func enqueueAudio(base64: String) {
        guard let data = Data(base64Encoded: base64),
              let format = playbackFormat else { return }

        let int16Count = data.count / MemoryLayout<Int16>.size
        guard int16Count > 0 else { return }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(int16Count)
        ) else { return }

        buffer.frameLength = AVAudioFrameCount(int16Count)

        let floatPtr = buffer.floatChannelData![0]
        data.withUnsafeBytes { rawBuffer in
            let int16Ptr = rawBuffer.bindMemory(to: Int16.self)
            for i in 0..<int16Count {
                floatPtr[i] = Float(int16Ptr[i]) / Float(Int16.max)
            }
        }

        playerNode.scheduleBuffer(buffer)

        if !isPlaying {
            do {
                try start()
            } catch {
                print("[AudioPlayback] Start error: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        playerNode.stop()
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        isPlaying = false
    }
}
