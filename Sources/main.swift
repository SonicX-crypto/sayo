import AppKit
import ApplicationServices
import AVFoundation

private final class DraggableEffectView: NSVisualEffectView {
    override var mouseDownCanMoveWindow: Bool { true }
}

private final class RecordingHUD {
    private let panel: NSPanel
    private let glyph = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let badge = NSTextField(labelWithString: "")
    private var timer: Timer?
    private var startedAt: Date?
    private var hasPositioned = false
    private var moveObserver: NSObjectProtocol?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 410, height: 88),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isMovable = true
        panel.isMovableByWindowBackground = true

        let background = DraggableEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 24
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = 0.6
        background.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        background.toolTip = "Перетащите панель в удобное место"
        panel.contentView = background

        glyph.translatesAutoresizingMaskIntoConstraints = false
        glyph.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 34, weight: .medium)
        glyph.imageScaling = .scaleProportionallyUpOrDown

        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.textColor = .labelColor

        detail.translatesAutoresizingMaskIntoConstraints = false
        detail.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        detail.textColor = .secondaryLabelColor

        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.alignment = .center
        badge.font = .systemFont(ofSize: 10, weight: .bold)
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 9
        badge.layer?.masksToBounds = true

        background.addSubview(glyph)
        background.addSubview(title)
        background.addSubview(detail)
        background.addSubview(badge)
        NSLayoutConstraint.activate([
            glyph.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 20),
            glyph.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            glyph.widthAnchor.constraint(equalToConstant: 40),
            glyph.heightAnchor.constraint(equalToConstant: 40),
            title.leadingAnchor.constraint(equalTo: glyph.trailingAnchor, constant: 14),
            title.topAnchor.constraint(equalTo: background.topAnchor, constant: 21),
            title.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -14),
            detail.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 5),
            detail.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -14),
            badge.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -18),
            badge.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 56),
            badge.heightAnchor.constraint(equalToConstant: 20)
        ])

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.savePosition()
        }
    }

    deinit {
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
    }

    func showRecording() {
        startedAt = Date()
        setAppearance(symbol: "waveform.circle.fill", color: .systemRed, badgeText: "REC")
        title.stringValue = "Слушаю…"
        detail.stringValue = "00:00  ·  правый ⌘ — готово  ·  Esc — отмена"
        show()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.updateDuration()
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func showProcessing() {
        timer?.invalidate()
        timer = nil
        setAppearance(symbol: "ellipsis.circle.fill", color: .systemPurple, badgeText: "LOCAL")
        title.stringValue = "Распознаю на M4 Pro…"
        detail.stringValue = "Whisper Large · Metal GPU · полностью локально"
        show()
    }

    func showSuccess(autoPasted: Bool) {
        setAppearance(symbol: "checkmark.circle.fill", color: .systemGreen, badgeText: "ГОТОВО")
        title.stringValue = autoPasted ? "Текст вставлен" : "Текст скопирован"
        detail.stringValue = "Сохранено в истории и буфере обмена"
        show()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.35) { [weak self] in self?.hide() }
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        startedAt = nil
        panel.orderOut(nil)
    }

    private func updateDuration() {
        guard let startedAt else { return }
        let seconds = Int(Date().timeIntervalSince(startedAt))
        detail.stringValue = String(
            format: "%02d:%02d  ·  правый ⌘ — готово  ·  Esc — отмена",
            seconds / 60,
            seconds % 60
        )
    }

    private func setAppearance(symbol: String, color: NSColor, badgeText: String) {
        glyph.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title.stringValue)
        glyph.contentTintColor = color
        badge.stringValue = "  \(badgeText)  "
        badge.textColor = color
        badge.layer?.backgroundColor = color.withAlphaComponent(0.13).cgColor
    }

    private func show() {
        if !hasPositioned {
            restorePositionOrUseDefault()
            hasPositioned = true
        }
        panel.orderFrontRegardless()
    }

    private func restorePositionOrUseDefault() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "hudOriginX") != nil,
           defaults.object(forKey: "hudOriginY") != nil {
            let saved = NSPoint(
                x: defaults.double(forKey: "hudOriginX"),
                y: defaults.double(forKey: "hudOriginY")
            )
            let proposedFrame = NSRect(origin: saved, size: panel.frame.size)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(proposedFrame) }) {
                panel.setFrameOrigin(saved)
                return
            }
        }

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(
                x: visible.midX - panel.frame.width / 2,
                y: visible.minY + 54
            ))
        }
    }

    private func savePosition() {
        UserDefaults.standard.set(panel.frame.origin.x, forKey: "hudOriginX")
        UserDefaults.standard.set(panel.frame.origin.y, forKey: "hudOriginY")
    }
}

private enum DictationError: LocalizedError {
    case microphoneDenied
    case noInputDevice
    case missingExecutable(String)
    case missingModel(String)
    case conversionFailed(String)
    case transcriptionFailed(String)
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "Нет доступа к микрофону"
        case .noInputDevice:
            return "Микрофон не найден"
        case .missingExecutable(let name):
            return "Не найден \(name)"
        case .missingModel(let path):
            return "Не найдена модель: \(path)"
        case .conversionFailed(let message):
            return "Не удалось подготовить аудио: \(message)"
        case .transcriptionFailed(let message):
            return "Ошибка распознавания: \(message)"
        case .emptyTranscript:
            return "Речь не распознана"
        }
    }
}

private final class DictationController: NSObject, NSApplicationDelegate {
    private let modelPath = NSString(
        string: "~/Library/Application Support/superwhisper/ggml-large.bin"
    ).expandingTildeInPath

    private var statusItem: NSStatusItem!
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var sourceAudioURL: URL?
    private var recognizerServer: Process?
    private let hud = RecordingHUD()
    private var statusLineItem: NSMenuItem!
    private var historyMenu: NSMenu!
    private var autoPasteItem: NSMenuItem!
    private var transcriptHistory: [String] = []
    private var autoPasteEnabled = UserDefaults.standard.object(forKey: "autoPaste") as? Bool ?? true
    private var isRecording = false
    private var isTranscribing = false
    private var lastRightCommandDown = false

    private let idleIcon = "waveform"
    private let recordingIcon = "record.circle.fill"
    private let workingIcon = "ellipsis.circle"

    func applicationDidFinishLaunching(_ notification: Notification) {
        transcriptHistory = UserDefaults.standard.stringArray(forKey: "transcriptHistory") ?? []
        configureMenuBar()
        requestAccessibilityPermission()
        installRightCommandTap()
        requestMicrophonePermission()
        startRecognizerServer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopRecordingWithoutTranscription()
        stopRecognizerServer()
    }

    private func configureMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        setStatus(icon: idleIcon, title: "Готово — нажмите правый ⌘")

        let menu = NSMenu()
        statusLineItem = NSMenuItem(title: "● Готово", action: nil, keyEquivalent: "")
        statusLineItem.isEnabled = false
        menu.addItem(statusLineItem)
        menu.addItem(.separator())

        let toggle = NSMenuItem(
            title: "Начать диктовку",
            action: #selector(toggleFromMenu),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        autoPasteItem = NSMenuItem(
            title: "Вставлять текст автоматически",
            action: #selector(toggleAutoPaste),
            keyEquivalent: ""
        )
        autoPasteItem.target = self
        autoPasteItem.state = autoPasteEnabled ? .on : .off
        menu.addItem(autoPasteItem)

        let historyRoot = NSMenuItem(title: "Последние фразы", action: nil, keyEquivalent: "")
        historyMenu = NSMenu(title: "Последние фразы")
        historyRoot.submenu = historyMenu
        menu.addItem(historyRoot)
        rebuildHistoryMenu()
        menu.addItem(.separator())

        let model = NSMenuItem(
            title: FileManager.default.fileExists(atPath: modelPath)
                ? "Модель: Whisper Large · Metal GPU"
                : "Модель не найдена",
            action: nil,
            keyEquivalent: ""
        )
        model.isEnabled = false
        menu.addItem(model)

        let permissions = NSMenuItem(
            title: "Открыть настройки доступа…",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        permissions.target = self
        menu.addItem(permissions)
        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Завершить",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func setStatus(icon: String, title: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.statusItem.button?.image = NSImage(
                systemSymbolName: icon,
                accessibilityDescription: title
            )
            self.statusItem.button?.contentTintColor = icon == self.recordingIcon ? .systemRed : nil
            self.statusItem.button?.toolTip = title
            if let statusLineItem = self.statusLineItem {
                let prefix: String
                if icon == self.recordingIcon { prefix = "● " }
                else if icon == self.workingIcon { prefix = "◌ " }
                else if icon == "exclamationmark.triangle" { prefix = "⚠︎ " }
                else { prefix = "● " }
                statusLineItem.title = prefix + title
            }
        }
    }

    private func requestAccessibilityPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func requestMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        default:
            break
        }
    }

    private func installRightCommandTap() {
        let mask = CGEventMask(
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)
        )
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<DictationController>.fromOpaque(userInfo).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = controller.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            if type == .keyDown { return controller.handleKeyDown(event) }
            if type == .flagsChanged { return controller.handleFlagsChanged(event) }
            return Unmanaged.passUnretained(event)
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else {
            showError("Не удалось включить правый ⌘. Разрешите приложению «Универсальный доступ» и перезапустите его.")
            return
        }

        eventTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func handleFlagsChanged(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        // 54 is the hardware key code of the right Command key on Apple keyboards.
        guard event.getIntegerValueField(.keyboardEventKeycode) == 54 else {
            return Unmanaged.passUnretained(event)
        }

        let isDown = event.flags.contains(.maskCommand)
        if isDown && !lastRightCommandDown {
            DispatchQueue.main.async { [weak self] in self?.toggleDictation() }
        }
        lastRightCommandDown = isDown

        // The right Command key is dedicated to dictation while the app is running.
        return nil
    }

    private func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        // Escape cancels the active recording without sending it for recognition.
        guard event.getIntegerValueField(.keyboardEventKeycode) == 53, isRecording else {
            return Unmanaged.passUnretained(event)
        }
        DispatchQueue.main.async { [weak self] in self?.cancelRecording() }
        return nil
    }

    @objc private func toggleFromMenu() {
        toggleDictation()
    }

    @objc private func toggleAutoPaste() {
        autoPasteEnabled.toggle()
        autoPasteItem.state = autoPasteEnabled ? .on : .off
        UserDefaults.standard.set(autoPasteEnabled, forKey: "autoPaste")
    }

    @objc private func copyHistoryItem(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        setStatus(icon: idleIcon, title: "Фраза скопирована")
        NSSound(named: "Glass")?.play()
    }

    @objc private func clearHistory() {
        transcriptHistory.removeAll()
        UserDefaults.standard.removeObject(forKey: "transcriptHistory")
        rebuildHistoryMenu()
    }

    private func toggleDictation() {
        if isTranscribing { return }
        if isRecording {
            finishRecordingAndTranscribe()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            showError(DictationError.microphoneDenied.localizedDescription)
            openPrivacySettings(anchor: "Privacy_Microphone")
            return
        }
        guard FileManager.default.fileExists(atPath: modelPath) else {
            showError(DictationError.missingModel(modelPath).localizedDescription)
            return
        }

        do {
            let engine = AVAudioEngine()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw DictationError.noInputDevice
            }

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("right-command-\(UUID().uuidString).caf")
            let file = try AVAudioFile(forWriting: url, settings: format.settings)

            input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
                try? file.write(from: buffer)
            }
            engine.prepare()
            try engine.start()

            audioEngine = engine
            audioFile = file
            sourceAudioURL = url
            isRecording = true
            setStatus(icon: recordingIcon, title: "Запись… правый ⌘ — готово, Esc — отмена")
            hud.showRecording()
            NSSound(named: "Tink")?.play()
        } catch {
            stopRecordingWithoutTranscription()
            showError(error.localizedDescription)
        }
    }

    private func finishRecordingAndTranscribe() {
        guard let sourceURL = sourceAudioURL else { return }
        stopAudioEngine()
        isRecording = false
        isTranscribing = true
        setStatus(icon: workingIcon, title: "Распознаю речь…")
        hud.showProcessing()
        NSSound(named: "Pop")?.play()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            defer {
                try? FileManager.default.removeItem(at: sourceURL)
                DispatchQueue.main.async {
                    self.isTranscribing = false
                    self.setStatus(icon: self.idleIcon, title: "Готово — нажмите правый ⌘")
                }
            }

            do {
                let wavURL = try self.convertToWhisperWAV(sourceURL)
                defer { try? FileManager.default.removeItem(at: wavURL) }
                let transcript = try self.transcribe(wavURL)
                DispatchQueue.main.async {
                    self.copyAndPaste(transcript)
                }
            } catch {
                DispatchQueue.main.async {
                    self.showError(error.localizedDescription)
                }
            }
        }
    }

    private func cancelRecording() {
        guard isRecording else { return }
        stopRecordingWithoutTranscription()
        hud.hide()
        setStatus(icon: idleIcon, title: "Запись отменена")
        NSSound(named: "Funk")?.play()
    }

    private func stopAudioEngine() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil
    }

    private func stopRecordingWithoutTranscription() {
        stopAudioEngine()
        if let sourceAudioURL {
            try? FileManager.default.removeItem(at: sourceAudioURL)
        }
        sourceAudioURL = nil
        isRecording = false
    }

    private func convertToWhisperWAV(_ input: URL) throws -> URL {
        guard let ffmpeg = locateExecutable(candidates: [
            "/usr/local/bin/ffmpeg",
            "/opt/homebrew/bin/ffmpeg"
        ]) else {
            throw DictationError.missingExecutable("ffmpeg")
        }

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("right-command-\(UUID().uuidString).wav")
        let result = runProcess(ffmpeg, arguments: [
            "-hide_banner", "-loglevel", "error", "-y",
            "-i", input.path,
            "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le",
            output.path
        ])
        guard result.status == 0 else {
            throw DictationError.conversionFailed(result.stderr)
        }
        return output
    }

    private func transcribe(_ input: URL) throws -> String {
        do {
            return try transcribeThroughServer(input)
        } catch {
            // If the persistent server could not start (for example, its port is
            // occupied), one-shot CPU recognition still gives the user a result.
            return try transcribeThroughCLI(input)
        }
    }

    private func startRecognizerServer() {
        guard recognizerServer == nil,
              FileManager.default.fileExists(atPath: modelPath),
              let server = locateExecutable(candidates: [
                  "/opt/homebrew/bin/whisper-server",
                  "/usr/local/bin/whisper-server"
              ]) else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: server)
        process.arguments = [
            "-m", modelPath,
            "-l", "auto",
            "-nt",
            "-t", "8",
            "--host", "127.0.0.1",
            "--port", "18080"
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            recognizerServer = process
            setStatus(icon: workingIcon, title: "Загружаю локальную модель…")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, !self.isRecording, !self.isTranscribing else { return }
                self.setStatus(icon: self.idleIcon, title: "Готово — нажмите правый ⌘")
            }
        } catch {
            recognizerServer = nil
        }
    }

    private func stopRecognizerServer() {
        guard let process = recognizerServer else { return }
        if process.isRunning { process.terminate() }
        recognizerServer = nil
    }

    private func transcribeThroughServer(_ input: URL) throws -> String {
        if recognizerServer?.isRunning != true {
            recognizerServer = nil
            startRecognizerServer()
        }

        let result = runProcess("/usr/bin/curl", arguments: [
            "--silent", "--show-error", "--fail-with-body",
            "--retry", "30", "--retry-all-errors", "--retry-delay", "1",
            "--max-time", "180",
            "http://127.0.0.1:18080/inference",
            "-F", "file=@\(input.path)",
            "-F", "response_format=json",
            "-F", "language=auto"
        ])
        guard result.status == 0 else {
            throw DictationError.transcriptionFailed(result.stderr)
        }

        guard let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawText = json["text"] as? String else {
            throw DictationError.transcriptionFailed("Некорректный ответ локального сервера")
        }
        return try cleanedTranscript(rawText)
    }

    private func transcribeThroughCLI(_ input: URL) throws -> String {
        guard let whisper = locateExecutable(candidates: [
            "/opt/homebrew/bin/whisper-cli",
            "/usr/local/bin/whisper-cli"
        ]) else {
            throw DictationError.missingExecutable("whisper-cli")
        }

        let result = runProcess(whisper, arguments: [
            "-m", modelPath,
            "-f", input.path,
            "-l", "auto",
            "-nt", "-np",
            "-bo", "2", "-bs", "2"
        ])
        guard result.status == 0 else {
            throw DictationError.transcriptionFailed(result.stderr)
        }

        return try cleanedTranscript(result.stdout)
    }

    private func cleanedTranscript(_ rawText: String) throws -> String {
        let text = rawText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("[") }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { throw DictationError.emptyTranscript }
        return text
    }

    private func copyAndPaste(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        addToHistory(text)

        guard autoPasteEnabled, AXIsProcessTrusted() else {
            setStatus(icon: idleIcon, title: "Текст скопирован в буфер")
            hud.showSuccess(autoPasted: false)
            NSSound(named: "Glass")?.play()
            return
        }

        let source = CGEventSource(stateID: .combinedSessionState)
        let commandDown = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: true)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: false)
        commandDown?.flags = .maskCommand
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        commandUp?.flags = []

        commandDown?.post(tap: .cghidEventTap)
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        commandUp?.post(tap: .cghidEventTap)
        hud.showSuccess(autoPasted: true)
        NSSound(named: "Glass")?.play()
    }

    private func addToHistory(_ text: String) {
        transcriptHistory.removeAll { $0 == text }
        transcriptHistory.insert(text, at: 0)
        transcriptHistory = Array(transcriptHistory.prefix(12))
        UserDefaults.standard.set(transcriptHistory, forKey: "transcriptHistory")
        rebuildHistoryMenu()
    }

    private func rebuildHistoryMenu() {
        guard historyMenu != nil else { return }
        historyMenu.removeAllItems()
        if transcriptHistory.isEmpty {
            let empty = NSMenuItem(title: "История пока пуста", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            historyMenu.addItem(empty)
            return
        }

        for text in transcriptHistory {
            let oneLine = text.replacingOccurrences(of: "\n", with: " ")
            let title = oneLine.count > 72 ? String(oneLine.prefix(72)) + "…" : oneLine
            let item = NSMenuItem(title: title, action: #selector(copyHistoryItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = text
            item.toolTip = text
            historyMenu.addItem(item)
        }
        historyMenu.addItem(.separator())
        let clear = NSMenuItem(title: "Очистить историю", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        historyMenu.addItem(clear)
    }

    private func locateExecutable(candidates: [String]) -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func runProcess(_ executable: String, arguments: [String]) -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (-1, "", error.localizedDescription)
        }

        let stdout = String(
            data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let stderr = String(
            data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        return (process.terminationStatus, stdout, stderr)
    }

    private func showError(_ message: String) {
        hud.hide()
        setStatus(icon: "exclamationmark.triangle", title: message)
        let alert = NSAlert()
        alert.messageText = "Локальная диктовка"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func openAccessibilitySettings() {
        openPrivacySettings(anchor: "Privacy_Accessibility")
    }

    private func openPrivacySettings(anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

let app = NSApplication.shared
private let delegate = DictationController()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
