import AVFoundation
import Combine
import Foundation

@MainActor
final class AudioRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    private var recorder: AVAudioRecorder?
    private(set) var recordingURL: URL?

    func start(at url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        guard recorder.record() else {
            throw NSError(domain: "LokalKIWorkspace.AudioRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Aufnahme konnte nicht gestartet werden."])
        }
        self.recorder = recorder
        recordingURL = url
        isRecording = true
    }

    @discardableResult
    func stop() -> URL? {
        recorder?.stop()
        isRecording = false
        recorder = nil
        return recordingURL
    }

}
