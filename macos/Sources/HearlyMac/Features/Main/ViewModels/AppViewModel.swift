import Combine
import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    static let shared = AppViewModel()
    @Published var page: HearlyPage = .home
    @Published var inputDevices: [HearlyAudioDevice] = []
    @Published var selectedInputDeviceID: UInt32?
    @Published var isVoiceIsolationEnabled = true
    @Published var telemetryOptIn = false
    @Published private(set) var isSignedIn = false
    @Published private(set) var signedInEmail: String?
    @Published var authErrorMessage: String?
    @Published var authEmail = ""
    @Published var authPassword = ""
    @Published var authCode = ""
    @Published var codeSent = false
    @Published var busy = false
    @Published var notice: String?
    @Published var profile: VoiceProfile?
    @Published var profileName = ""
    @Published var trainingStep = 1
    @Published var phraseIndex = 0
    @Published var phraseCaptured = false
    @Published var lastCapturedDuration: Double = 0
    @Published var isTestingMicrophone = false
    @Published private(set) var recognizedPhrase = ""
    @Published private(set) var phraseMatchedWords = 0
    @Published private(set) var phraseRecognitionProgress: Double = 0
    @Published var transcriptEnabled = false
    @Published var transcripts: [TranscriptRecord] = []
    @Published var liveTranscript = ""
    @Published var threshold: Float = 0.55
    @Published var verificationScore: Float?
    @Published var testing = false
    @Published var logs: [String] = []
    @Published var newVersionAlerts = false
    @Published var productEmails = false
    @Published var autoStartInMeetings = true
    @Published var isAuditionActive = false
    @Published var auditionFeed: AuditionFeed = .filtered
    @Published var auditionVolume: Float = 0.85
    @Published var isHeadphonesConnected = false

    let audio = AudioEngineController()
    let virtualMicrophone = VirtualMicrophoneMonitor()
    let meetingDetector = MeetingDetector()
    let hardwareWatcher = AudioHardwareWatcher()
    var hotkeyManager = GlobalHotkeyManager()
    private let driverInstaller = DriverInstallerService()
    private var autoStartedByMeeting = false
    private var auditionStartedAudio = false
    private var database: LocalDatabase?
    private var embeddings: [[Float]] = []
    private var subscriptions = Set<AnyCancellable>()
    private var owner = "local"
    private let speech = TranscriptService()
    private let enrollmentSpeech = EnrollmentSpeechRecognizer()
    private var lastTranscriptID: UUID?
    @Published private(set) var phraseIsRecognized = false
    private var enrollmentOperation = UUID()
    private var recordingTimeout: Task<Void, Never>?
    private var authOperation = UUID()

    init(preview: Bool = false) {
        // Snapshot fixtures never restore accounts, request permissions or open storage.
        if preview { return }
        audio.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
        virtualMicrophone.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
        meetingDetector.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
        hardwareWatcher.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
        hotkeyManager.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
        hotkeyManager.onTrigger = { [weak self] in
            guard let self else { return }
            self.toggleAudioFromHotkey()
        }
        hardwareWatcher.onDevicesChanged = { [weak self] in
            guard let self else { return }
            self.log("Hardware configuration updated.")
            self.refresh()
        }
        meetingDetector.onMeetingStarted = { [weak self] platform in
            guard let self else { return }
            self.log("Meeting detected: \(platform).")
            if self.autoStartInMeetings && self.profile != nil && self.virtualMicrophone.status == .installed {
                if !self.audio.isRunning && !self.audio.isStarting {
                    self.autoStartedByMeeting = true
                    self.log("Auto-starting Voice Focus for \(platform).")
                    Task {
                        await self.audio.start(inputDeviceID: self.selectedInputDeviceID, profile: self.profile, threshold: self.threshold)
                        if self.audio.isRunning && self.transcriptEnabled { await self.startTranscript() }
                    }
                }
            }
        }
        meetingDetector.onMeetingEnded = { [weak self] in
            guard let self else { return }
            self.log("Meeting ended.")
            if self.autoStartedByMeeting && self.audio.isRunning {
                self.log("Auto-stopping Voice Focus (meeting ended).")
                self.stopAudio()
                self.autoStartedByMeeting = false
            }
        }
        audio.onFilteredSamples = { [weak self] samples in self?.speech.append(samples) }
        audio.onCaptureSamples = { [weak self] samples in
            guard let self, self.page == .training, self.trainingStep == 2, !self.testing else { return }
            self.enrollmentSpeech.append(samples)
        }
        enrollmentSpeech.onProgress = { [weak self] progress in
            guard let self, self.audio.isCapturing, self.page == .training, !self.testing else { return }
            self.recognizedPhrase = progress.recognizedText
            self.phraseMatchedWords = progress.matchedWordCount
            self.phraseRecognitionProgress = progress.fraction
            self.phraseIsRecognized = progress.isComplete
        }
        enrollmentSpeech.onError = { [weak self] message in
            guard let self, self.page == .training, !self.phraseCaptured else { return }
            self.notice = "Phrase checking is unavailable, but recording can continue. Read the phrase and click the microphone when finished. (\(message))"
        }
        speech.onText = { [weak self] text in
            guard let self else { return }
            self.liveTranscript = text
            if let id = self.lastTranscriptID, let index = self.transcripts.firstIndex(where: { $0.id == id }) {
                self.transcripts[index].text = text
            } else if !text.isEmpty {
                let record = TranscriptRecord(text: text)
                self.transcripts.insert(record, at: 0)
                self.lastTranscriptID = record.id
            }
            self.saveHistory()
        }
        speech.onError = { [weak self] message in self?.notice = message }
        refresh()
        // Local-only: no account restoration, analytics, or network service.
        useLocalWorkspace()
    }

    var statusTitle: String { audio.isRunning ? "Hearly is listening" : "Hearly is inactive" }
    var driverInstallerAvailable: Bool { driverInstaller.isAvailable }
    var phrases: [String] { [
        "Hey Hearly, this is \(profileName). I am training my voice profile.",
        "Hearly should recognize my voice clearly in quiet and noisy moments.",
        "This is my natural speaking voice. Keep my voice clear and let the conversation flow."
    ] }
    var currentPhrase: String { phrases[min(phraseIndex, 2)] }
    var trainingProgress: Double { min(1, (Double(phraseIndex) + (phraseCaptured ? 1 : phraseRecognitionProgress)) / 3) }
    var initials: String { String((profile?.name ?? signedInEmail ?? "R").prefix(1)).uppercased() }

    var selectedDeviceName: String {
        if let selectedInputDeviceID, let dev = inputDevices.first(where: { $0.id == selectedInputDeviceID }) {
            return dev.name
        }
        return CoreAudioDeviceManager.defaultInputDeviceName()
    }

    var selectedDeviceIcon: String {
        CoreAudioDeviceManager.iconName(for: selectedDeviceName)
    }

    func openDriverInstaller() {
        do {
            try driverInstaller.open()
        } catch {
            notice = error.localizedDescription
        }
    }

    func refresh() {
        inputDevices = CoreAudioDeviceManager.inputDevices()
        if let savedUID = UserDefaults.standard.string(forKey: "hearly.selectedInputUID"), selectedInputDeviceID == nil {
            if let matched = inputDevices.first(where: { $0.uid == savedUID }) {
                selectedInputDeviceID = matched.id
            }
        }
        if let selectedInputDeviceID, !inputDevices.contains(where: { $0.id == selectedInputDeviceID }) {
            self.selectedInputDeviceID = nil
            UserDefaults.standard.removeObject(forKey: "hearly.selectedInputUID")
            notice = "The selected microphone disconnected. Switched to system default."
            if audio.isRunning {
                Task {
                    await self.audio.switchInputDevice(to: nil, profile: self.profile, threshold: self.threshold)
                }
            }
        }
        isHeadphonesConnected = CoreAudioDeviceManager.isHeadphonesConnected()
        virtualMicrophone.refresh()
        meetingDetector.refresh()
    }

    func selectInputDevice(_ id: UInt32?) {
        guard selectedInputDeviceID != id else { return }
        selectedInputDeviceID = id
        if let id, let dev = inputDevices.first(where: { $0.id == id }) {
            UserDefaults.standard.set(dev.uid, forKey: "hearly.selectedInputUID")
            log("Selected microphone: \(dev.name).")
        } else {
            UserDefaults.standard.removeObject(forKey: "hearly.selectedInputUID")
            log("Selected microphone: System default.")
        }
        if audio.isRunning {
            Task {
                await audio.switchInputDevice(to: id, profile: profile, threshold: threshold)
            }
        }
    }

    func emailContinue() {
        useLocalWorkspace()
    }
    func oauth(_ provider: String) {
        authErrorMessage = "Hearly is local-only. No online accounts or sign-in are used."
    }
    // An explicit local mode is available while account configuration is being completed.
    func useLocalWorkspace() {
        do {
            authOperation = UUID()
            stopAudio()
            owner = "local"
            try loadData()
            isSignedIn = true
            signedInEmail = nil
        } catch { authErrorMessage = error.localizedDescription }
    }
    private func loadData() throws {
        database = try LocalDatabase()
        profile = try database?.load(VoiceProfile.self, id: owner + ".voice")
        transcripts = try database?.load([TranscriptRecord].self, id: owner + ".transcripts") ?? []
        profileName = profile?.name ?? ""
        if let profile { log("Loaded \(profile.embedding.count)-dimension enrolled voiceprint.") }
    }
    func signOut() {
        stopAudio()
        authOperation = UUID()
        isSignedIn = false
        signedInEmail = nil
        profile = nil
        transcripts = []
        embeddings = []
        page = .home
        codeSent = false
        authCode = ""
        liveTranscript = ""
        transcriptEnabled = false
        verificationScore = nil
        database = nil
        busy = false
    }
    func beginTraining() {
        stopMicrophoneTest()
        stopAudio()
        embeddings = []
        trainingStep = 1
        phraseIndex = 0
        phraseCaptured = false
        lastCapturedDuration = 0
        resetPhraseRecognition()
        page = .training
        notice = nil
    }
    func prepareTraining() {
        stopMicrophoneTest()
        profileName = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !profileName.isEmpty, profileName.count <= 100 else { notice = "Enter a name between 1 and 100 characters."; return }
        trainingStep = 2
    }
    func restartPreparation() {
        // Returning to the name step discards the incomplete enrollment consistently.
        beginTraining()
    }
    func toggleMicrophoneTest() {
        if isTestingMicrophone { stopMicrophoneTest() }
        else { startMicrophoneTest() }
    }
    func startMicrophoneTest() {
        guard !audio.isRunning, !audio.isStarting, page == .training, trainingStep == 1 else { return }
        isTestingMicrophone = true
        notice = nil
        Task { [weak self] in
            guard let self else { return }
            await self.audio.start(inputDeviceID: self.selectedInputDeviceID, monitorOnly: true)
            if !self.audio.isRunning { self.isTestingMicrophone = false }
        }
    }
    func stopMicrophoneTest() {
        isTestingMicrophone = false
        if audio.isRunning && audio.isMonitoring { audio.stop() }
    }
    func recordPhrase() {
        guard !busy, !audio.isRunning, !audio.isStarting, page == .training, trainingStep == 2, !phraseCaptured else { return }
        notice = nil
        resetPhraseRecognition()
        let operation = UUID()
        enrollmentOperation = operation
        busy = true
        Task { [weak self] in
            guard let self else { return }
            defer { if self.enrollmentOperation == operation { self.busy = false } }
            do {
                try await self.enrollmentSpeech.start(expectedPhrase: self.currentPhrase)
            } catch is CancellationError {
                guard self.enrollmentOperation == operation else { return }
            } catch {
                guard self.enrollmentOperation == operation else { return }
                self.notice = "Phrase checking is unavailable, but recording can continue. Read the phrase and click the microphone when finished."
            }
            guard self.enrollmentOperation == operation else { return }
            await self.audio.start(inputDeviceID: self.selectedInputDeviceID, capture: true)
            guard self.enrollmentOperation == operation else { return }
            guard self.audio.isCapturing else { self.enrollmentSpeech.stop(); return }
            self.recordingTimeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled, let self, self.enrollmentOperation == operation, self.audio.isCapturing else { return }
                self.cancelPhrase()
                self.notice = "Recording timed out. Read the phrase naturally and click the microphone when you finish."
            }
        }
    }
    private func resetPhraseRecognition() {
        recognizedPhrase = ""
        phraseMatchedWords = 0
        phraseRecognitionProgress = 0
        phraseIsRecognized = false
    }
    func cancelPhrase() {
        stopAudio()
        resetPhraseRecognition()
        notice = nil
    }
    func capturePhrase() {
        guard !busy, audio.isCapturing, page == .training, trainingStep == 2, !phraseCaptured else { return }
        guard audio.voicedSeconds >= 2.0 else {
            notice = "Keep reading the phrase in your normal voice for at least two seconds before continuing."
            return
        }
        let operation = enrollmentOperation
        busy = true
        recordingTimeout?.cancel()
        recordingTimeout = nil
        enrollmentSpeech.stop()
        let voiced = audio.voicedSeconds
        Task {
            defer { if enrollmentOperation == operation { busy = false } }
            do {
                let embedding = try await audio.finishCapture()
                guard enrollmentOperation == operation else { return }
                if embeddings.contains(where: { SpeakerModel.similarity($0, embedding) < 0.45 }) {
                    throw HearlyFailure.message("This phrase sounds different from the first. Please record it again in your normal voice.")
                }
                embeddings.append(embedding)
                lastCapturedDuration = voiced
                phraseCaptured = true
                log(String(format: "Captured phrase %d of 3 (%.1fs voiced speech).", embeddings.count, voiced))
            } catch { if enrollmentOperation == operation { resetPhraseRecognition(); notice = error.localizedDescription } }
        }
    }
    func rerecordCurrentPhrase() {
        guard phraseCaptured, !embeddings.isEmpty else { return }
        embeddings.removeLast()
        phraseCaptured = false
        lastCapturedDuration = 0
        resetPhraseRecognition()
        stopAudio()
    }
    func nextPhrase() {
        guard phraseCaptured else { return }
        if embeddings.count == 3 { finishEnrollment(); return }
        phraseIndex = embeddings.count
        phraseCaptured = false
        resetPhraseRecognition()
    }
    private func finishEnrollment() {
        guard embeddings.count == 3, let first = embeddings.first, !first.isEmpty else { return }
        let combined = SpeakerModel.normalized(first.indices.map { index in embeddings.reduce(Float(0)) { $0 + $1[index] } / 3 })
        let enrolled = VoiceProfile(name: profileName, embedding: combined, model: SpeakerModel.identifier)
        do {
            guard let database else { throw HearlyFailure.message("The local database is unavailable.") }
            try database.save(enrolled, id: owner + ".voice")
            profile = enrolled
            trainingStep = 3
            embeddings = []
            log("Voice enrollment saved securely on this Mac.")
        } catch { notice = error.localizedDescription }
    }
    func removeVoice() {
        stopAudio()
        do {
            try database?.remove(id: owner + ".voice")
            profile = nil
            profileName = ""
            embeddings = []
            log("Removed voice profile from this Mac.")
        } catch { notice = error.localizedDescription }
    }
    func toggleAudio() {
        autoStartedByMeeting = false
        if audio.isRunning { stopAudio(); return }
        guard profile != nil else { beginTraining(); return }
        refresh()
        guard virtualMicrophone.status == .installed else { notice = "Install the Hearly microphone driver before using voice focus in meetings. Open Audio Setup for instructions."; return }
        Task {
            await audio.start(inputDeviceID: selectedInputDeviceID, profile: profile, threshold: threshold)
            if audio.isRunning && transcriptEnabled { await startTranscript() }
        }
    }
    func toggleAudioFromHotkey() {
        if audio.isRunning {
            stopAudio()
            HUDOverlayController.shared.show(isActive: false)
        } else {
            toggleAudio()
            HUDOverlayController.shared.show(isActive: true)
        }
    }
    func toggleAudition() async {
        if isAuditionActive {
            stopAudition()
        } else {
            await startAudition()
        }
    }

    func setAuditionFeed(_ feed: AuditionFeed) {
        auditionFeed = feed
        audio.setAuditionFeed(feed)
        log("Audition feed switched to \(feed.rawValue).")
    }

    func setAuditionVolume(_ volume: Float) {
        auditionVolume = volume
        audio.setAuditionVolume(volume)
    }

    func startAudition() async {
        isAuditionActive = true
        isHeadphonesConnected = CoreAudioDeviceManager.isHeadphonesConnected()
        audio.setAuditionFeed(auditionFeed)
        audio.setAuditionVolume(auditionVolume)
        audio.setAuditionActive(true)
        log("Audition active: monitoring \(auditionFeed.rawValue).")
        if !audio.isRunning && !audio.isStarting {
            auditionStartedAudio = true
            if profile != nil && virtualMicrophone.status == .installed {
                await audio.start(inputDeviceID: selectedInputDeviceID, profile: profile, threshold: threshold)
            } else {
                await audio.start(inputDeviceID: selectedInputDeviceID, profile: profile, threshold: threshold, monitorOnly: true)
            }
        }
    }

    func stopAudition() {
        isAuditionActive = false
        audio.setAuditionActive(false)
        log("Audition stopped.")
        if auditionStartedAudio && audio.isRunning && !autoStartedByMeeting {
            auditionStartedAudio = false
            audio.stop()
        }
    }

    func stopAudio() {
        autoStartedByMeeting = false
        isTestingMicrophone = false
        isAuditionActive = false
        auditionStartedAudio = false
        audio.setAuditionActive(false)
        enrollmentOperation = UUID()
        recordingTimeout?.cancel()
        recordingTimeout = nil
        enrollmentSpeech.stop()
        busy = false
        audio.stop()
        speech.stop()
        saveHistory()
        lastTranscriptID = nil
        testing = false
    }
    func setTranscript(_ enabled: Bool) {
        transcriptEnabled = enabled
        if !enabled { speech.stop(); saveHistory(); lastTranscriptID = nil }
        else if audio.isRunning && !audio.isCapturing { Task { await startTranscript() } }
    }
    private func startTranscript() async {
        do { try await speech.start() }
        catch { notice = error.localizedDescription; transcriptEnabled = false }
    }
    private func saveHistory() {
        do { try database?.save(transcripts, id: owner + ".transcripts") }
        catch { notice = error.localizedDescription }
    }
    func toggleVerification() {
        guard profile != nil else { notice = "Enroll your voice before running verification."; return }
        if testing {
            busy = true
            Task {
                defer { busy = false; testing = false }
                do {
                    let embedding = try await audio.finishCapture()
                    verificationScore = SpeakerModel.similarity(embedding, profile?.embedding ?? [])
                    log(String(format: "Speaker verification score %.3f (threshold %.2f).", verificationScore ?? 0, threshold))
                } catch { notice = error.localizedDescription }
            }
        } else {
            stopAudio()
            verificationScore = nil
            Task {
                await audio.start(inputDeviceID: selectedInputDeviceID, capture: true)
                testing = audio.isRunning
            }
        }
    }
    func log(_ message: String) {
        logs.append("[\(Date().formatted(date: .omitted, time: .standard))]  " + message)
        if logs.count > 100 { logs.removeFirst() }
    }
}
