import AVFoundation
import Observation
import Speech

/// Push-to-talk listener for the voice copilot: one tap starts listening, the order ends when
/// the pilot stops talking (or after a few seconds) and the text goes to `onOrder`. Listening is
/// never continuous, so the copilot cannot hear its own read-backs or the cabin announcements.
@MainActor
@Observable
final class VoiceCopilot {
    enum State: Equatable {
        case idle
        case listening
        case unavailable(String)
    }

    private(set) var state: State = .idle
    /// What is being heard, live.
    private(set) var heard = ""
    @ObservationIgnored var onOrder: ((String) -> Void)?

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var silenceTimer: Task<Void, Never>?
    @ObservationIgnored private var deadline: Task<Void, Never>?
    @ObservationIgnored private var previousCategory: AVAudioSession.Category?
    @ObservationIgnored private var previousOptions: AVAudioSession.CategoryOptions = []

    var isListening: Bool { state == .listening }

    func toggle(language: String) {
        if isListening { finish() } else { Task { await start(language: language) } }
    }

    func start(language: String) async {
        guard !isListening else { return }
        guard await Self.authorize() else {
            state = .unavailable("Permite el micrófono y el reconocimiento de voz en Ajustes del iPad.")
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)), recognizer.isAvailable else {
            state = .unavailable("El reconocimiento de voz no está disponible para este idioma.")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            previousCategory = session.category
            previousOptions = session.categoryOptions
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .mixWithOthers, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            // On the device when it can: faster, and works without internet at the sim.
            if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
            request.taskHint = .confirmation
            request.contextualStrings = Self.vocabulary
            self.request = request

            let input = engine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                request.append(buffer)
            }
            engine.prepare()
            try engine.start()
        } catch {
            cleanUp()
            state = .unavailable("No se pudo usar el micrófono: \(error.localizedDescription)")
            return
        }

        guard let request else { return }
        heard = ""
        state = .listening
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            Task { @MainActor [weak self] in
                guard let self, self.isListening else { return }
                if let text { self.heard = text }
                if isFinal || error != nil {
                    self.finish()
                } else {
                    self.restartSilenceTimer()
                }
            }
        }
        // An order is short: stop after six seconds whatever happens.
        deadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    /// Stops listening and hands over what was heard.
    func finish() {
        guard isListening else { return }
        let text = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        cleanUp()
        state = .idle
        if !text.isEmpty { onOrder?(text) }
    }

    /// The order is over once the pilot has been quiet for a moment.
    private func restartSilenceTimer() {
        silenceTimer?.cancel()
        silenceTimer = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    private func cleanUp() {
        silenceTimer?.cancel()
        deadline?.cancel()
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        // Back to what the app used before, so read-backs and callouts sound as usual.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(previousCategory ?? .soloAmbient, options: previousOptions)
    }

    private static func authorize() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    /// Words the recogniser should prefer: aviation terms it would otherwise misspell.
    private static let vocabulary = [
        "gear up", "gear down", "flaps", "flaps full", "landing lights", "nose light", "strobe", "beacon",
        "seat belts", "spoilers", "autopilot", "autothrust", "APU", "APU bleed", "TCAS", "TA RA", "anti ice",
        "after takeoff", "after landing", "after start", "before start", "line up", "parking",
    ]
}
