import AppKit
import ApplicationServices

final class CodexKeyNavigationMonitor {
    var isEnabled = true
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    var onRightOptionPressed: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var globalModifierMonitor: Any?
    private var isRightOptionDown = false

    var isMonitoringAvailable: Bool {
        eventTap != nil || globalMonitor != nil
    }

    func start() {
        guard eventTap == nil, globalMonitor == nil, globalModifierMonitor == nil else { return }
        AudioDebugLogger.log("key_monitor_start")
        requestAccessibilityTrustIfNeeded()

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: Self.eventTapCallback,
            userInfo: refcon
        ) else {
            AudioDebugLogger.log("key_event_tap_failed")
            startGlobalMonitorFallback()
            startGlobalModifierMonitor()
            AudioDebugLogger.log("key_monitor_availability", fields: ["available": isMonitoringAvailable])
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        AudioDebugLogger.log("key_event_tap_started")
        startGlobalModifierMonitor()
        AudioDebugLogger.log("key_monitor_availability", fields: ["available": isMonitoringAvailable])
    }

    private func startGlobalMonitorFallback() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event)
        }

        AudioDebugLogger.log("key_global_monitor_started", fields: [
            "started": globalMonitor != nil
        ])
    }

    private func startGlobalModifierMonitor() {
        guard globalModifierMonitor == nil else { return }
        globalModifierMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleKey(event)
        }

        AudioDebugLogger.log("key_global_modifier_monitor_started", fields: [
            "started": globalModifierMonitor != nil
        ])
    }

    private func requestAccessibilityTrustIfNeeded() {
        let isTrusted = AXIsProcessTrusted()
        AudioDebugLogger.log("key_accessibility_trust", fields: ["trusted": isTrusted])
    }

    deinit {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let globalModifierMonitor {
            NSEvent.removeMonitor(globalModifierMonitor)
        }
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard type == .keyDown, let refcon else {
            return Unmanaged.passUnretained(event)
        }

        let monitor = Unmanaged<CodexKeyNavigationMonitor>.fromOpaque(refcon).takeUnretainedValue()
        monitor.handleKey(event)
        return Unmanaged.passUnretained(event)
    }

    private func handleKey(_ event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isLeftArrow = keyCode == 123
        let isRightArrow = keyCode == 124
        guard isLeftArrow || isRightArrow else { return }

        DispatchQueue.main.async { [weak self] in
            self?.handleArrowKey(keyCode: keyCode, flags: event.flags)
        }
    }

    private func handleKey(_ event: NSEvent) {
        let keyCode = Int64(event.keyCode)
        if event.type == .flagsChanged {
            DispatchQueue.main.async { [weak self] in
                self?.handleModifierChange(keyCode: keyCode, flags: event.cgEvent?.flags ?? CGEventFlags(rawValue: 0))
            }
            return
        }

        let isLeftArrow = keyCode == 123
        let isRightArrow = keyCode == 124
        guard isLeftArrow || isRightArrow else { return }

        DispatchQueue.main.async { [weak self] in
            self?.handleArrowKey(keyCode: keyCode, flags: event.cgEvent?.flags ?? CGEventFlags(rawValue: 0))
        }
    }

    private func handleModifierChange(keyCode: Int64, flags: CGEventFlags) {
        let rightOptionKeyCode: Int64 = 61
        guard keyCode == rightOptionKeyCode else { return }

        let isDown = flags.contains(.maskAlternate)
        guard isDown != isRightOptionDown else { return }
        isRightOptionDown = isDown

        AudioDebugLogger.log("key_right_option_changed", fields: [
            "isDown": isDown,
            "frontmost": frontmostAppDescription()
        ])

        guard isDown else { return }
        guard isEnabled else {
            AudioDebugLogger.log("key_right_option_ignored", fields: ["reason": "monitor_disabled"])
            return
        }

        AudioDebugLogger.log("key_right_option_trigger")
        onRightOptionPressed?()
    }

    private func handleArrowKey(keyCode: Int64, flags: CGEventFlags) {
        AudioDebugLogger.log("key_arrow_seen", fields: [
            "keyCode": keyCode,
            "modifiers": flags.rawValue,
            "frontmost": frontmostAppDescription()
        ])

        guard isEnabled else {
            AudioDebugLogger.log("key_arrow_ignored", fields: ["reason": "monitor_disabled", "keyCode": keyCode])
            return
        }

        if flags.contains(.maskCommand) || flags.contains(.maskAlternate) || flags.contains(.maskControl) || flags.contains(.maskShift) {
            AudioDebugLogger.log("key_arrow_ignored", fields: ["reason": "modifier_pressed", "keyCode": keyCode])
            return
        }

        guard isLikelyCodexOrChatGPTAppActive() else {
            AudioDebugLogger.log("key_arrow_ignored", fields: [
                "reason": "frontmost_not_codex",
                "keyCode": keyCode,
                "frontmost": frontmostAppDescription()
            ])
            return
        }

        switch keyCode {
        case 123:
            AudioDebugLogger.log("key_arrow_trigger", fields: ["direction": "previous"])
            onPrevious?()
        case 124:
            AudioDebugLogger.log("key_arrow_trigger", fields: ["direction": "next"])
            onNext?()
        default:
            return
        }
    }

    private func frontmostAppDescription() -> String {
        guard let app = NSWorkspace.shared.frontmostApplication else { return "unknown" }
        let bundleID = app.bundleIdentifier ?? "no-bundle-id"
        let name = app.localizedName ?? "no-name"
        return "\(name) (\(bundleID))"
    }

    private func isLikelyCodexOrChatGPTAppActive() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let bundleID = app.bundleIdentifier?.lowercased() ?? ""
        let name = app.localizedName?.lowercased() ?? ""

        return bundleID.contains("openai")
            || bundleID.contains("chatgpt")
            || bundleID.contains("codex")
            || name.contains("chatgpt")
            || name.contains("codex")
    }
}
