import AVFAudio
import Foundation
import Observation

/// A small, compact recorder for talks and spoken answers: AAC mono at
/// 32 kbps (about 14 MB an hour — a 40-minute talk still fits the 10 MB
/// transcription limit), with a live level for the bloom.
@MainActor
@Observable
final class AudioRecorder {
    private(set) var isRecording = false
    private(set) var level: Double = 0
    private(set) var elapsed: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var meterTask: Task<Void, Never>?

    func start(to url: URL) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 22_050,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else { throw RecorderError.couldNotStart }
        self.recorder = recorder
        isRecording = true
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, let recorder = self.recorder else { return }
                recorder.updateMeters()
                let db = Double(recorder.averagePower(forChannel: 0))
                let target = min(max((db + 50) / 40, 0), 1)
                self.level += (target - self.level) * (target > self.level ? 0.5 : 0.12)
                self.elapsed = recorder.currentTime
            }
        }
    }

    /// Stops and returns how long it ran.
    @discardableResult
    func stop() -> TimeInterval {
        meterTask?.cancel()
        let duration = recorder?.currentTime ?? elapsed
        recorder?.stop()
        recorder = nil
        isRecording = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return duration
    }

    enum RecorderError: LocalizedError {
        case couldNotStart
        var errorDescription: String? { "The microphone couldn't start. Close other apps using it and try again." }
    }
}
