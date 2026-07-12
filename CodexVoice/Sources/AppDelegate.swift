import AppKit
import AVFoundation
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let speaker = VoiceOutputController()
    private let keyNavigationMonitor = CodexKeyNavigationMonitor()
    private var watcher: TranscriptWatcher!
    private var statusItem: NSStatusItem!
    private var enabledItem: NSMenuItem!
    private var commentaryItem: NSMenuItem!
    private var includeTextInLogsItem: NSMenuItem!
    private var statusMenuItem: NSMenuItem!
    private var lastMessageMenuItem: NSMenuItem!
    private var engineMenu: NSMenu!
    private var voiceMenu: NSMenu!
    private var rateMenu: NSMenu!
    private var historyCursor: Int?

    private var isEnabled = true {
        didSet {
            watcher.isEnabled = isEnabled
            enabledItem.state = isEnabled ? .on : .off
            updateStatus(idleStatus)
        }
    }

    private var shouldReadCommentary = UserDefaults.standard.object(forKey: "readCommentary") as? Bool ?? true {
        didSet {
            commentaryItem.state = shouldReadCommentary ? .on : .off
            UserDefaults.standard.set(shouldReadCommentary, forKey: "readCommentary")
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()
        _ = PronunciationDictionary.ensureUserFileExists()

        watcher = TranscriptWatcher()
        watcher.onEvent = { [weak self] event in
            DispatchQueue.main.async { self?.handle(event) }
        }

        buildMenuBar()
        configureSpeech()
        configureKeyNavigationMonitor()
        watcher.start()
        AudioDebugLogger.log("app_started", fields: [
            "bundleIdentifier": Bundle.main.bundleIdentifier ?? "unknown",
            "engine": speaker.selectedEngine.rawValue,
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "voxtralVoice": speaker.selectedVoxtralVoice,
            "includesTextContent": AudioDebugLogger.includesTextContent
        ])
        updateStatus(idleStatus)
    }

    func applicationWillTerminate(_ notification: Notification) {
        AudioDebugLogger.log("app_terminating", fields: ["engine": speaker.selectedEngine.rawValue])
        speaker.shutdown()
    }

    private var idleStatus: String {
        guard isEnabled else { return AppStrings.text("status.monitoringPaused") }
        guard keyNavigationMonitor.isMonitoringAvailable else {
            return AppStrings.text("status.monitoringShortcutsUnavailable")
        }
        return speaker.selectedEngine == .macOS
            ? AppStrings.text("status.monitoringActive")
            : AppStrings.text("status.monitoringVoxtral")
    }

    private func installEditMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let editMenuItem = NSMenuItem()

        let appMenu = NSMenu(title: "Codex Voice 2")
        appMenu.addItem(withTitle: AppStrings.text("app.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        let editMenu = NSMenu(title: AppStrings.text("menu.edit"))
        editMenu.addItem(withTitle: AppStrings.text("menu.undo"), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: AppStrings.text("menu.redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: AppStrings.text("menu.cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: AppStrings.text("menu.copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: AppStrings.text("menu.paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: AppStrings.text("menu.selectAll"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        mainMenu.addItem(appMenuItem)
        mainMenu.addItem(editMenuItem)
        NSApp.mainMenu = mainMenu
    }

    private func handle(_ event: TranscriptEvent) {
        switch event {
        case .taskStarted:
            break
        case .userMessage:
            if speaker.isSpeaking {
                AudioDebugLogger.log("speech_stop", fields: ["reason": "new_codex_event"])
                speaker.stop(reason: "new_codex_event")
                updateStatus(AppStrings.text("status.speechInterrupted"))
            }
        case .commentary(let message):
            logReceivedMessage(kind: "commentary", message: message)
            guard isEnabled, shouldReadCommentary else {
                AudioDebugLogger.log("message_skipped", fields: ["kind": "commentary", "reason": "disabled"])
                return
            }
            guard let prepared = ContentFilter.prepareDetailedForCommentary(message) else {
                AudioDebugLogger.log("message_skipped", fields: ["kind": "commentary", "reason": "technical_or_empty"])
                updateStatus(AppStrings.text("status.technicalMessageSkipped"))
                return
            }
            AudioDebugLogger.logPreparedSpeech(kind: "commentary", raw: message, prepared: prepared)
            speaker.speak(prepared.text, sourceKind: "commentary", rawText: message)
            updateStatus(AppStrings.text("status.readingLiveUpdate"))
        case .taskComplete(let message, _):
            guard isEnabled else { return }
            logReceivedMessage(kind: "final", message: message)
            let prepared = ContentFilter.prepareDetailedForSpeech(message)
            AudioDebugLogger.logPreparedSpeech(kind: "final", raw: message, prepared: prepared)
            guard !prepared.text.isEmpty else {
                AudioDebugLogger.log("message_skipped", fields: ["kind": "final", "reason": "technical_or_empty"])
                return
            }
            speaker.speak(prepared.text, sourceKind: "final", rawText: message)
            historyCursor = nil
            lastMessageMenuItem.isEnabled = true
            updateStatus(AppStrings.text("status.readingLatestReply"))
        case .foundLatest(let message):
            logReceivedMessage(kind: "replay", message: message)
            let prepared = ContentFilter.prepareDetailedForSpeech(message)
            AudioDebugLogger.logPreparedSpeech(kind: "replay", raw: message, prepared: prepared)
            guard !prepared.text.isEmpty else {
                AudioDebugLogger.log("message_skipped", fields: ["kind": "replay", "reason": "technical_or_empty"])
                return
            }
            speaker.speak(prepared.text, sourceKind: "replay", rawText: message)
            lastMessageMenuItem.isEnabled = true
            updateStatus(AppStrings.text("status.replayingLatestReply"))
        case .watchError(let message):
            AudioDebugLogger.log("watch_error", fields: ["message": message])
            updateStatus(message)
        }
    }

    private func buildMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Codex Voice 2"
        statusItem.button?.image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: "Codex Voice 2")

        let menu = NSMenu()
        statusMenuItem = NSMenuItem(title: AppStrings.text("menu.initializing"), action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        enabledItem = NSMenuItem(title: AppStrings.text("menu.automaticReading"), action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.target = self
        enabledItem.state = .on
        menu.addItem(enabledItem)

        commentaryItem = NSMenuItem(title: AppStrings.text("menu.readLiveUpdates"), action: #selector(toggleCommentary), keyEquivalent: "")
        commentaryItem.target = self
        commentaryItem.state = shouldReadCommentary ? .on : .off
        menu.addItem(commentaryItem)

        includeTextInLogsItem = NSMenuItem(title: AppStrings.text("menu.includeSpokenText"), action: #selector(toggleTextInLogs), keyEquivalent: "")
        includeTextInLogsItem.target = self
        includeTextInLogsItem.state = AudioDebugLogger.includesTextContent ? .on : .off
        menu.addItem(includeTextInLogsItem)

        let replay = NSMenuItem(title: AppStrings.text("menu.readLatestReply"), action: #selector(replayLatest), keyEquivalent: "r")
        replay.target = self
        replay.keyEquivalentModifierMask = [.control, .option]
        lastMessageMenuItem = replay
        menu.addItem(replay)

        let previous = NSMenuItem(title: AppStrings.text("menu.readPreviousBlock"), action: #selector(replayPreviousHistoryItem), keyEquivalent: "\u{F702}")
        previous.target = self
        previous.keyEquivalentModifierMask = []
        menu.addItem(previous)

        let next = NSMenuItem(title: AppStrings.text("menu.readNextBlock"), action: #selector(replayNextHistoryItem), keyEquivalent: "\u{F703}")
        next.target = self
        next.keyEquivalentModifierMask = []
        menu.addItem(next)

        let stop = NSMenuItem(title: AppStrings.text("menu.stopSpeaking"), action: #selector(stopSpeaking), keyEquivalent: ".")
        stop.target = self
        stop.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(stop)
        menu.addItem(.separator())

        let engineItem = NSMenuItem(title: AppStrings.text("menu.engine"), action: nil, keyEquivalent: "")
        engineMenu = NSMenu()
        engineItem.submenu = engineMenu
        menu.addItem(engineItem)
        rebuildEngineMenu()

        let voiceItem = NSMenuItem(title: AppStrings.text("menu.voice"), action: nil, keyEquivalent: "")
        voiceMenu = NSMenu()
        voiceItem.submenu = voiceMenu
        menu.addItem(voiceItem)
        rebuildVoiceMenu()

        let rateItem = NSMenuItem(title: AppStrings.text("menu.speed"), action: nil, keyEquivalent: "")
        rateMenu = NSMenu()
        rateItem.submenu = rateMenu
        menu.addItem(rateItem)
        rebuildRateMenu()

        menu.addItem(.separator())
        let openSessions = NSMenuItem(title: AppStrings.text("menu.openTranscripts"), action: #selector(openSessionsFolder), keyEquivalent: "")
        openSessions.target = self
        menu.addItem(openSessions)

        let openAudioLog = NSMenuItem(title: AppStrings.text("menu.openAudioLog"), action: #selector(openAudioLog), keyEquivalent: "")
        openAudioLog.target = self
        menu.addItem(openAudioLog)

        let clearAudioLogs = NSMenuItem(title: AppStrings.text("menu.clearAudioLogs"), action: #selector(clearAudioLogs), keyEquivalent: "")
        clearAudioLogs.target = self
        menu.addItem(clearAudioLogs)

        let openPronunciationDictionary = NSMenuItem(title: AppStrings.text("menu.openPronunciationDictionary"), action: #selector(openPronunciationDictionary), keyEquivalent: "")
        openPronunciationDictionary.target = self
        menu.addItem(openPronunciationDictionary)

        let importPronunciationDictionary = NSMenuItem(title: AppStrings.text("menu.importPronunciationDictionary"), action: #selector(importPronunciationDictionary), keyEquivalent: "")
        importPronunciationDictionary.target = self
        menu.addItem(importPronunciationDictionary)

        let exportPronunciationDictionary = NSMenuItem(title: AppStrings.text("menu.exportPronunciationDictionary"), action: #selector(exportPronunciationDictionary), keyEquivalent: "")
        exportPronunciationDictionary.target = self
        menu.addItem(exportPronunciationDictionary)

        menu.addItem(.separator())
        menu.addItem(withTitle: AppStrings.text("app.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func configureSpeech() {
        speaker.onFinish = { [weak self] in
            AudioDebugLogger.log("speech_finish")
            self?.updateStatus(self?.idleStatus ?? AppStrings.text("status.monitoringActive"))
        }
        speaker.onFirstAudio = { [weak self] in
            guard let self else { return }
            self.updateStatus(self.speaker.selectedEngine == .macOS ? AppStrings.text("status.readingMacOS") : AppStrings.text("status.readingVoxtral"))
        }
        speaker.onError = { [weak self] error in
            AudioDebugLogger.log("speech_error_status", fields: ["message": error])
            self?.updateStatus(AppStrings.text("status.voxtralError"))
        }
        speaker.onVoxtralStateChange = { [weak self] state in
            guard let self, self.speaker.selectedEngine == .voxtralStreaming else { return }
            switch state {
            case .starting: self.updateStatus(AppStrings.text("status.preparingVoxtral"))
            case .ready: self.updateStatus(self.idleStatus)
            case .unavailable: self.updateStatus(AppStrings.text("status.voxtralUnavailable"))
            case .stopped: self.updateStatus(self.idleStatus)
            }
        }

        speaker.voiceIdentifier = UserDefaults.standard.string(forKey: "voiceIdentifier")
        speaker.rate = UserDefaults.standard.object(forKey: "speechRate") as? Float ?? 0.48
        speaker.selectedVoxtralVoice = UserDefaults.standard.string(forKey: "voxtralVoice") ?? "fr_female"
        if let value = UserDefaults.standard.string(forKey: "selectedEngine"), let engine = VoiceEngineKind(rawValue: value) {
            speaker.selectEngine(engine)
        }
        rebuildEngineMenu()
        rebuildVoiceMenu()
        rebuildRateMenu()
    }

    private func logReceivedMessage(kind: String, message: String) {
        var fields: [String: Any] = ["kind": kind, "rawLength": message.count]
        AudioDebugLogger.addTextField(message, named: "raw", to: &fields)
        AudioDebugLogger.log("message_received", fields: fields)
    }

    private func configureKeyNavigationMonitor() {
        keyNavigationMonitor.onPrevious = { [weak self] in DispatchQueue.main.async { self?.replayHistory(direction: -1) } }
        keyNavigationMonitor.onNext = { [weak self] in DispatchQueue.main.async { self?.replayHistory(direction: 1) } }
        keyNavigationMonitor.onRightOptionPressed = { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.speaker.isSpeaking else { return }
                AudioDebugLogger.log("speech_stop", fields: ["reason": "right_option_push_to_talk"])
                self.speaker.stop(reason: "right_option_push_to_talk")
                self.updateStatus(AppStrings.text("status.speechStoppedRightOption"))
            }
        }
        keyNavigationMonitor.start()
    }

    private func rebuildEngineMenu() {
        engineMenu.removeAllItems()
        for engine in VoiceEngineKind.allCases {
            let item = NSMenuItem(title: engine.rawValue, action: #selector(selectEngine(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = engine.rawValue
            item.state = engine == speaker.selectedEngine ? .on : .off
            engineMenu.addItem(item)
        }
    }

    private func rebuildVoiceMenu() {
        voiceMenu.removeAllItems()
        if speaker.selectedEngine == .macOS {
            let voices = VoiceOutputController.availableFrenchVoices()
            if voices.isEmpty {
                let item = NSMenuItem(title: AppStrings.text("voice.noFrenchMacOSVoices"), action: nil, keyEquivalent: "")
                item.isEnabled = false
                voiceMenu.addItem(item)
                return
            }
            let recommended = addRecommendedMacVoiceSection(from: voices)
            let others = voices.filter { voice in !recommended.contains { $0.identifier == voice.identifier } }
            if !others.isEmpty {
                voiceMenu.addItem(.separator())
                addMacVoiceSection(AppStrings.text("voice.other"), voices: others)
            }
            return
        }

        addVoiceSection(AppStrings.text("voice.recommended"), voices: VoxtralVoiceCatalog.recommended)
        voiceMenu.addItem(.separator())
        addVoiceSection(AppStrings.text("voice.other"), voices: VoxtralVoiceCatalog.others)
    }

    private func addRecommendedMacVoiceSection(from voices: [SpeechController.Voice]) -> [SpeechController.Voice] {
        let label = NSMenuItem(title: AppStrings.text("voice.recommended"), action: nil, keyEquivalent: "")
        label.isEnabled = false
        voiceMenu.addItem(label)

        let recommendations = [("Thomas", "thomas"), ("Aurélie", "aurelie")]
        var installed: [SpeechController.Voice] = []
        for (displayName, matchKey) in recommendations {
            if let voice = voices.first(where: {
                let name = $0.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                return name.contains(matchKey) && isDownloadedQualityMacVoice($0)
            }) {
                addMacVoiceItem(voice)
                installed.append(voice)
            } else {
                let unavailable = NSMenuItem(
                    title: AppStrings.format("voice.unavailable", displayName),
                    action: nil,
                    keyEquivalent: ""
                )
                unavailable.isEnabled = false
                voiceMenu.addItem(unavailable)
            }
        }
        return installed
    }

    private func addMacVoiceSection(_ title: String, voices: [SpeechController.Voice]) {
        let label = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        label.isEnabled = false
        voiceMenu.addItem(label)
        for voice in voices {
            addMacVoiceItem(voice)
        }
    }

    private func addMacVoiceItem(_ voice: SpeechController.Voice) {
        let item = NSMenuItem(title: macVoiceMenuTitle(voice), action: #selector(selectMacVoice(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = voice.identifier
        item.state = voice.identifier == speaker.voiceIdentifier ? .on : .off
        voiceMenu.addItem(item)
    }

    private func isDownloadedQualityMacVoice(_ voice: SpeechController.Voice) -> Bool {
        voice.name.localizedCaseInsensitiveContains("enhanced") || voice.name.localizedCaseInsensitiveContains("premium")
    }

    private func macVoiceMenuTitle(_ voice: SpeechController.Voice) -> String {
        voice.name
    }

    private func addVoiceSection(_ title: String, voices: [VoxtralVoicePreset]) {
        let label = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        label.isEnabled = false
        voiceMenu.addItem(label)
        for voice in voices {
            let item = NSMenuItem(title: voice.name, action: #selector(selectVoxtralVoice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = voice.identifier
            item.state = voice.identifier == speaker.selectedVoxtralVoice ? .on : .off
            voiceMenu.addItem(item)
        }
    }

    private func rebuildRateMenu() {
        rateMenu.removeAllItems()
        guard speaker.selectedEngine == .macOS else {
            let item = NSMenuItem(title: AppStrings.text("rate.voxtralNative"), action: nil, keyEquivalent: "")
            item.isEnabled = false
            rateMenu.addItem(item)
            return
        }
        let rates: [(String, Float)] = [
            (AppStrings.text("rate.slow"), 0.38),
            (AppStrings.text("rate.normal"), 0.48),
            (AppStrings.text("rate.fast"), 0.53),
            (AppStrings.text("rate.veryFast"), 0.58)
        ]
        for (title, rate) in rates {
            let item = NSMenuItem(title: title, action: #selector(selectRate(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = rate
            item.state = abs(rate - speaker.rate) < 0.01 ? .on : .off
            rateMenu.addItem(item)
        }
    }

    private func updateStatus(_ message: String) {
        statusMenuItem?.title = message
    }

    @objc private func toggleEnabled() { isEnabled.toggle() }
    @objc private func toggleCommentary() { shouldReadCommentary.toggle() }

    @objc private func replayLatest() {
        if let message = watcher.latestCompletedMessage() {
            handle(.foundLatest(message))
        } else {
            updateStatus(AppStrings.text("status.noFinalReply"))
        }
    }

    @objc private func stopSpeaking() {
        AudioDebugLogger.log("speech_stop", fields: ["reason": "manual_menu"])
        speaker.stop(reason: "manual_menu")
        updateStatus(idleStatus)
    }

    @objc private func replayPreviousHistoryItem() { replayHistory(direction: -1) }
    @objc private func replayNextHistoryItem() { replayHistory(direction: 1) }

    private func replayHistory(direction: Int) {
        let history = watcher.assistantHistory()
        guard !history.isEmpty else {
            updateStatus(AppStrings.text("status.noAssistantBlocks"))
            AudioDebugLogger.log("history_navigation_empty")
            return
        }
        let current = historyCursor ?? history.count
        let nextIndex = historyCursor == nil ? history.count - 1 : max(0, min(history.count - 1, current + direction))
        guard nextIndex != current else {
            updateStatus(direction < 0 ? AppStrings.text("status.startOfConversation") : AppStrings.text("status.endOfConversation"))
            AudioDebugLogger.log("history_navigation_boundary", fields: ["direction": direction, "historyCount": history.count, "cursor": current])
            return
        }
        let item = history[nextIndex]
        let prepared = ContentFilter.prepareDetailedForSpeech(item.message)
        guard !prepared.text.isEmpty else {
            historyCursor = nextIndex
            updateStatus(AppStrings.text("status.technicalBlockSkipped"))
            AudioDebugLogger.log("history_navigation_skipped", fields: ["index": nextIndex, "historyCount": history.count, "kind": item.kind])
            return
        }
        historyCursor = nextIndex
        AudioDebugLogger.logPreparedSpeech(kind: "history_\(item.kind)", raw: item.message, prepared: prepared)
        AudioDebugLogger.log("history_navigation", fields: ["direction": direction, "index": nextIndex, "historyCount": history.count, "kind": item.kind])
        speaker.speak(prepared.text, sourceKind: "history_\(item.kind)", rawText: item.message)
        updateStatus(AppStrings.format("status.readingBlock", nextIndex + 1, history.count))
    }

    @objc private func selectEngine(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let engine = VoiceEngineKind(rawValue: value) else { return }
        speaker.selectEngine(engine)
        UserDefaults.standard.set(engine.userDefaultsValue, forKey: "selectedEngine")
        rebuildEngineMenu()
        rebuildVoiceMenu()
        rebuildRateMenu()
        updateStatus(engine == .macOS ? idleStatus : AppStrings.text("status.preparingVoxtral"))
    }

    @objc private func selectMacVoice(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String else { return }
        speaker.voiceIdentifier = identifier
        UserDefaults.standard.set(identifier, forKey: "voiceIdentifier")
        if let voice = VoiceOutputController.availableFrenchVoices().first(where: { $0.identifier == identifier }) {
            let quality = isDownloadedQualityMacVoice(voice) ? "enhanced_downloaded" : "standard"
            AudioDebugLogger.log("mac_voice_selected", fields: ["voice": voice.name, "quality": quality])
            updateStatus(AppStrings.format("status.macOSVoice", macVoiceMenuTitle(voice)))
        }
        rebuildVoiceMenu()
    }

    @objc private func selectVoxtralVoice(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String else { return }
        speaker.selectedVoxtralVoice = identifier
        UserDefaults.standard.set(identifier, forKey: "voxtralVoice")
        rebuildVoiceMenu()
    }

    @objc private func selectRate(_ sender: NSMenuItem) {
        guard let rate = sender.representedObject as? Float else { return }
        speaker.rate = rate
        UserDefaults.standard.set(rate, forKey: "speechRate")
        rebuildRateMenu()
    }

    @objc private func openSessionsFolder() { NSWorkspace.shared.open(TranscriptWatcher.sessionsRoot) }

    @objc private func openAudioLog() {
        let url = AudioDebugLogger.logURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        AudioDebugLogger.log("log_opened_from_menu")
        openInTextEdit(url, failureStatus: AppStrings.text("status.openLogFailed"))
    }

    @objc private func toggleTextInLogs() {
        let enabled = !AudioDebugLogger.includesTextContent
        AudioDebugLogger.setIncludesTextContent(enabled)
        includeTextInLogsItem.state = enabled ? .on : .off
        AudioDebugLogger.log("content_logging_changed", fields: ["enabled": enabled])
    }

    @objc private func clearAudioLogs() {
        let alert = NSAlert()
        alert.messageText = AppStrings.text("alert.clearAudioLogsTitle")
        alert.informativeText = AppStrings.text("alert.clearAudioLogsMessage")
        alert.addButton(withTitle: AppStrings.text("alert.clear"))
        alert.addButton(withTitle: AppStrings.text("alert.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        speaker.clearDiagnosticLogs()
        AudioDebugLogger.log("diagnostic_logs_cleared", fields: [
            "includesTextContent": AudioDebugLogger.includesTextContent
        ])
        updateStatus(AppStrings.text("status.audioLogCleared"))
    }

    @objc private func openPronunciationDictionary() {
        let dictionaryURL = PronunciationDictionary.ensureUserFileExists()
        openInTextEdit(dictionaryURL, failureStatus: AppStrings.text("status.openDictionaryFailed"))
    }

    @objc private func importPronunciationDictionary() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

        do {
            try PronunciationDictionary.importUserFile(from: sourceURL)
            AudioDebugLogger.log("pronunciation_dictionary_imported")
            updateStatus(AppStrings.text("status.dictionaryImported"))
        } catch {
            updateStatus(AppStrings.format("status.importFailed", error.localizedDescription))
        }
    }

    @objc private func exportPronunciationDictionary() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "pronunciations.csv"
        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        do {
            let content = try String(contentsOf: PronunciationDictionary.ensureUserFileExists(), encoding: .utf8)
            try content.write(to: destinationURL, atomically: true, encoding: .utf8)
            AudioDebugLogger.log("pronunciation_dictionary_exported")
            updateStatus(AppStrings.text("status.dictionaryExported"))
        } catch {
            updateStatus(AppStrings.format("status.exportFailed", error.localizedDescription))
        }
    }

    private func openInTextEdit(_ url: URL, failureStatus: String) {
        guard let textEditURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") else {
            NSWorkspace.shared.open(url)
            return
        }

        NSWorkspace.shared.open(
            [url],
            withApplicationAt: textEditURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { [weak self] _, error in
            guard error != nil else { return }
            NSWorkspace.shared.open(url)
            self?.updateStatus(failureStatus)
        }
    }
}

private extension AudioDebugLogger {
    static func logPreparedSpeech(kind: String, raw: String, prepared: ContentFilter.PreparedSpeech) {
        var fields: [String: Any] = [
            "kind": kind,
            "rawLength": raw.count,
            "spokenLength": prepared.text.count,
            "omittedCodeBlocks": prepared.omittedCodeBlocks,
            "omittedTechnicalLines": prepared.omittedTechnicalLines
        ]
        addTextField(prepared.text, named: "spoken", to: &fields)
        log("speech_prepared", fields: fields)
    }
}
