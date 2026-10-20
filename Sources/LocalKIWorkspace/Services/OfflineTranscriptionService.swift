import Foundation
import Speech

enum OfflineTranscriptionError: LocalizedError {
    case localeUnavailable
    case offlineModelUnavailable
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .localeUnavailable: return "Die deutsche Spracherkennung ist auf diesem Mac nicht verfügbar."
        case .offlineModelUnavailable: return "Für Deutsch ist kein Offline-Sprachmodell verfügbar. Es wurde keine Online-Erkennung gestartet."
        case .emptyTranscript: return "Es wurde kein verständlicher Text erkannt."
        }
    }
}

struct OfflineTranscriptionService {
    func transcribe(fileURL: URL, locale: Locale = Locale(identifier: "de-DE")) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw OfflineTranscriptionError.localeUnavailable
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw OfflineTranscriptionError.offlineModelUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.taskHint = .dictation

        return try await withCheckedThrowingContinuation { continuation in
            let gate = TranscriptionContinuation(continuation)
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    gate.finish(.failure(error))
                    return
                }
                guard let result, result.isFinal else { return }
                let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty {
                    gate.finish(.failure(OfflineTranscriptionError.emptyTranscript))
                } else {
                    gate.finish(.success(text))
                }
            }
        }
    }
}

private final class TranscriptionContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?

    init(_ continuation: CheckedContinuation<String, Error>) {
        self.continuation = continuation
    }

    func finish(_ result: Result<String, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}
