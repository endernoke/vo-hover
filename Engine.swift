// Hover engine: finds the accessibility item under the pointer and speaks it
// through VoiceOver's own speech, without moving the VoiceOver cursor.

import Cocoa
import ApplicationServices
import os

let logger = Logger(subsystem: "io.github.endernoke.vohover", category: "engine")

// MARK: - VoiceOver

enum VoiceOver {
    static let bundleID = "com.apple.VoiceOver"

    /// Thread-safe (NSRunningApplication is documented as such).
    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Speaks `text` through VoiceOver's speech channel.
    static func say(_ text: String) {
        logger.debug("speak: \(text, privacy: .public)")
        send(NSAppleEventDescriptor(string: text))
    }

    /// Speaks VoiceOver's own description of the item under the mouse ("Describe Item in Mouse Pointer").
    static func sayMouseSummary() {
        send(NSAppleEventDescriptor(enumCode: fourCharCode("mosU")))
    }

    /// Speech is sent from its own serial queue: phrases stay in order, and the system's
    /// Automation consent alert (shown before the first event) never blocks the main thread.
    private static let speechQueue = DispatchQueue(label: "io.github.endernoke.vohover.speech", qos: .userInitiated)

    /// Sends VoiceOver's scripting `output` event (class 'VOAS', id 'outp') directly,
    /// so text needs no AppleScript escaping and nothing is compiled per phrase.
    private static func send(_ directObject: NSAppleEventDescriptor) {
        speechQueue.async {
            // Never send while VoiceOver is off: some send paths would launch it.
            guard isRunning else { return }
            // The first time, macOS asks the user (using NSAppleEventsUsageDescription) and
            // this waits for the answer; afterwards it returns the stored decision at once.
            guard automationPermission(askUser: true) == .granted else { return }
            let event = NSAppleEventDescriptor(
                eventClass: fourCharCode("VOAS"), eventID: fourCharCode("outp"),
                targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: bundleID),
                returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
            event.setParam(directObject, forKeyword: keyDirectObject)
            do {
                try event.sendEvent(options: [.noReply], timeout: 1)
            } catch {
                logger.error("VoiceOver output failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Asks for Automation permission (the standard system alert) without blocking the caller.
    static func requestAutomationPermission() {
        speechQueue.async { _ = automationPermission(askUser: true) }
    }

    /// Whether VOHover may send Apple Events to VoiceOver. With `askUser`, shows the system
    /// consent alert if the user hasn't decided yet and blocks until they answer.
    static func automationPermission(askUser: Bool = false) -> PermissionState {
        guard isRunning else { return .unknown }
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        switch AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, askUser) {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .notDetermined
        default: return .unknown
        }
    }
}

enum PermissionState { case granted, denied, notDetermined, unknown }

private func fourCharCode(_ s: StaticString) -> FourCharCode {
    s.withUTF8Buffer { $0.reduce(0) { $0 << 8 | FourCharCode($1) } }
}

// MARK: - Accessibility helpers

private let systemWide: AXUIElement = {
    let s = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(s, 0.25)
    return s
}()

private func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success else { return nil }
    return v
}

private func paramAttr(_ el: AXUIElement, _ name: String, _ arg: CFTypeRef) -> CFTypeRef? {
    var v: CFTypeRef?
    guard AXUIElementCopyParameterizedAttributeValue(el, name as CFString, arg, &v) == .success else { return nil }
    return v
}

/// A non-empty, trimmed string attribute.
private func str(_ el: AXUIElement, _ name: String) -> String? {
    guard let s = attr(el, name) as? String else { return nil }
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? nil : t
}

/// A numeric attribute (booleans excluded).
private func number(_ el: AXUIElement, _ name: String) -> NSNumber? {
    guard let v = attr(el, name), CFGetTypeID(v) != CFBooleanGetTypeID() else { return nil }
    return v as? NSNumber
}

/// An element-valued attribute, type-checked rather than force-cast.
private func element(_ el: AXUIElement, _ name: String) -> AXUIElement? {
    guard let v = attr(el, name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
    return (v as! AXUIElement)
}

private func cfRange(_ v: CFTypeRef?) -> CFRange? {
    guard let v, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    var range = CFRange()
    return AXValueGetValue(v as! AXValue, .cfRange, &range) ? range : nil
}

// MARK: - Describing an element

private let textValueRoles: Set<String> = ["AXStaticText", "AXTextField", "AXTextArea", "AXComboBox", "AXHeading", "AXCell"]
private let numericValueRoles: Set<String> = ["AXSlider", "AXProgressIndicator", "AXValueIndicator", "AXLevelIndicator", "AXIncrementor", "AXScrollBar"]
private let menuValueRoles: Set<String> = ["AXPopUpButton", "AXMenuButton"]
private let toggleRoles: Set<String> = ["AXCheckBox", "AXRadioButton", "AXSwitch", "AXToggle"]
private let silentRoleDescriptions: Set<String> = ["AXStaticText", "AXGroup", "AXUnknown", "AXLayoutArea", "AXLayoutItem"]
private let neverSpokenRoles: Set<String> = ["AXApplication", "AXWindow", "AXSystemWide"]
/// Roles whose value is their content, so it is read even when Verbosity > Value is off.
private let contentRoles: Set<String> = ["AXStaticText", "AXHeading"]

/// A VoiceOver-like phrase for one element, or nil if it has no name or value
/// (the caller may then try the enclosing element).
private func phrase(for el: AXUIElement) -> String? {
    let role = str(el, kAXRoleAttribute) ?? "AXUnknown"
    if neverSpokenRoles.contains(role) { return nil }

    var label = str(el, kAXTitleAttribute) ?? str(el, kAXDescriptionAttribute)
    if label == nil, let titleElement = element(el, kAXTitleUIElementAttribute) {
        label = str(titleElement, kAXValueAttribute) ?? str(titleElement, kAXTitleAttribute)
    }

    var value: String?
    if textValueRoles.contains(role) || menuValueRoles.contains(role) {
        value = str(el, kAXValueAttribute)
    } else if numericValueRoles.contains(role) {
        value = str(el, kAXValueDescriptionAttribute) ?? number(el, kAXValueAttribute)?.stringValue
    }
    if label == nil && value == nil { label = str(el, kAXPlaceholderValueAttribute) }
    if label == nil && value == nil { return nil }

    var parts: [String] = []
    if let label { parts.append(label) }
    if let value, value != label, Prefs.includeValue || contentRoles.contains(role) || label == nil {
        parts.append(value)
    }
    if Prefs.includeRole, !silentRoleDescriptions.contains(role), let rd = str(el, kAXRoleDescriptionAttribute) {
        parts.append(rd)
    }
    if Prefs.includeState {
        if toggleRoles.contains(role), let n = attr(el, kAXValueAttribute) as? NSNumber {
            parts.append(n.intValue == 0 ? "unchecked" : (n.intValue == 1 ? "checked" : "mixed"))
        }
        if attr(el, kAXEnabledAttribute) as? Bool == false { parts.append("dimmed") }
    }
    return parts.joined(separator: ", ")
}

/// The visual line at `point` in a multi-line text area (terminals, editors), if the app supports it.
private func line(in el: AXUIElement, at point: CGPoint) -> (index: Int, text: String)? {
    var pt = point
    guard let ptValue = AXValueCreate(.cgPoint, &pt),
          let charRange = cfRange(paramAttr(el, kAXRangeForPositionParameterizedAttribute, ptValue)),
          let index = (paramAttr(el, kAXLineForIndexParameterizedAttribute, charRange.location as CFNumber) as? NSNumber)?.intValue,
          index >= 0, index != NSNotFound,
          let lineRange = paramAttr(el, kAXRangeForLineParameterizedAttribute, index as CFNumber),
          let text = paramAttr(el, kAXStringForRangeParameterizedAttribute, lineRange) as? String
    else { return nil }
    // Terminals pad empty cells with NULs and spaces.
    let clean = text.replacingOccurrences(of: "\u{0}", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    return (index, clean)
}

/// What is under the pointer: an element (plus a line within it, for text areas) and what to speak.
private struct HoverTarget {
    let element: AXUIElement
    let line: Int?
    let text: String?

    func isSameItem(as other: HoverTarget?) -> Bool {
        guard let other else { return false }
        return line == other.line && CFEqual(element, other.element)
    }
}

private func target(at point: CGPoint) -> HoverTarget? {
    var hit: AXUIElement?
    guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hit) == .success,
          var el = hit else { return nil }

    if Prefs.textAreaReadsLine, str(el, kAXRoleAttribute) == "AXTextArea", let line = line(in: el, at: point) {
        return HoverTarget(element: el, line: line.index, text: line.text.isEmpty ? nil : line.text)
    }

    // Walk up past unlabeled wrappers (e.g. an icon inside a button).
    for _ in 0..<(Prefs.readContainer ? 5 : 1) {
        if let p = phrase(for: el) { return HoverTarget(element: el, line: nil, text: p) }
        guard let up = element(el, kAXParentAttribute) else { return nil }
        el = up
    }
    return nil
}

// MARK: - Pointer movement

/// Tells user pointer movement apart from other pointer motion. Mice, trackpads and
/// assistive input (Mouse Keys, Head Pointer, ...) post mouse-moved events. Zoom panning to
/// follow VoiceOver focus, and apps warping the pointer, move it without posting any event.
/// A listen-only event tap therefore sees exactly the movements the user made.
private final class PointerMoveMonitor {
    /// Whether a movement has been reported to `onMove` and not yet taken with `takeMoved()`.
    private let pending = OSAllocatedUnfairLock(initialState: false)
    private var tap: CFMachPort?
    private let onMove: () -> Void

    /// `onMove` runs on the tap's thread at the first movement after each `takeMoved()`,
    /// so a burst of events costs one call.
    init(onMove: @escaping () -> Void) { self.onMove = onMove }

    var isInstalled: Bool { tap != nil }

    /// Whether a movement is waiting to be taken.
    var hasPendingMove: Bool { pending.withLock { $0 } }

    /// Marks pending movements as handled; the next movement calls `onMove` again.
    func takeMoved() { pending.withLock { $0 = false } }

    /// Creates the event tap once Accessibility access allows it; returns whether it is running.
    func installIfNeeded() -> Bool {
        if tap != nil { return true }
        let types: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, info in
            let monitor = Unmanaged<PointerMoveMonitor>.fromOpaque(info!).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = monitor.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            } else if monitor.pending.withLock({ p in defer { p = true }; return !p }) {
                monitor.onMove()
            }
            return Unmanaged.passUnretained(event)
        }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
                                           options: .listenOnly, eventsOfInterest: mask, callback: callback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        tap = port
        // Its own thread: the main thread is busy while a menu is open.
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CFRunLoopRun()
        }
        thread.name = "io.github.endernoke.vohover.pointer"
        thread.qualityOfService = .userInteractive
        thread.start()
        logger.notice("Pointer event tap installed")
        return true
    }
}

// MARK: - Engine

/// Speaks the item under the pointer once it has rested there for the dwell delay. Driven by
/// the user's pointer movements (see `PointerMoveMonitor`), so it does nothing while the mouse
/// is still, and Zoom dragging the pointer along as VoiceOver moves focus doesn't make it speak.
///
/// Accessibility queries must not run on the main thread: VOHover's own windows and menus
/// are answered by the main thread, which is also busy while a menu is open. All state
/// below is confined to `queue`.
final class HoverEngine {
    /// At most one lookup per interval while the pointer moves: events arrive at 60-120+ Hz
    /// and a lookup can block for up to the messaging timeout.
    private static let lookupInterval: DispatchTimeInterval = .milliseconds(50)
    /// How often to retry until Accessibility access allows the event tap.
    private static let setupRetryInterval: DispatchTimeInterval = .seconds(1)

    private let queue = DispatchQueue(label: "io.github.endernoke.vohover.engine", qos: .userInteractive)
    private lazy var moves = PointerMoveMonitor { [weak self] in
        guard let self else { return }
        queue.async { self.scheduleLookup() }
    }
    private var setupTimer: DispatchSourceTimer?
    private var lookupScheduled = false
    private var lastLookup: DispatchTime?
    /// Where the pointer was at the last lookup.
    private var lastMouse: CGPoint?
    private var candidate: HoverTarget?
    private var candidateSince = ContinuousClock.now
    private var dwellTimer: DispatchWorkItem?
    private var spoken: HoverTarget?
    private var promptedForAccess = false

    func start() {
        queue.async { [self] in
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now(), repeating: Self.setupRetryInterval, leeway: .milliseconds(250))
            t.setEventHandler { [weak self] in self?.trySetUp() }
            t.resume()
            setupTimer = t
        }
    }

    /// Forget the last item and speak the one under the pointer again.
    func reset() {
        queue.async { [self] in
            spoken = nil
            setCandidate(nil)
            scheduleLookup()
        }
    }

    /// Installs the event tap once hover speech needs it and Accessibility access allows it,
    /// then stops retrying and reads the item under the pointer.
    private func trySetUp() {
        guard Prefs.enabled, VoiceOver.isRunning, checkTrust(), moves.installIfNeeded() else { return }
        setupTimer?.cancel()
        setupTimer = nil
        scheduleLookup()
    }

    /// Asks for Accessibility access once per launch, when hover speech
    /// first needs it: macOS shows its alert offering to open Privacy & Security settings.
    /// Until access is granted the engine stays idle; Settings > General shows the status.
    private func checkTrust() -> Bool {
        if AXIsProcessTrusted() { return true }
        if !promptedForAccess {
            promptedForAccess = true
            logger.notice("Requesting Accessibility permission")
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
        return false
    }

    private var isActive: Bool {
        moves.isInstalled && Prefs.enabled && (!Prefs.onlyWhenZoomed || UAZoomEnabled()) && VoiceOver.isRunning
    }

    /// Looks up the item under the pointer now, or when the lookup interval allows.
    private func scheduleLookup() {
        guard !lookupScheduled else { return }
        lookupScheduled = true
        let deadline = max(.now(), lastLookup.map { $0 + Self.lookupInterval } ?? .now())
        queue.asyncAfter(deadline: deadline) { [weak self] in self?.lookUp() }
    }

    private func lookUp() {
        lookupScheduled = false
        lastLookup = .now()
        moves.takeMoved()   // movements from here on schedule another lookup
        guard isActive, let mouse = CGEvent(source: nil)?.location else { return }   // global, top-left origin
        lastMouse = mouse
        let hit = target(at: mouse)
        let unchanged = hit.map { $0.isSameItem(as: candidate) } ?? (candidate == nil)
        if !unchanged {
            setCandidate(hit)
        } else if dwellTimer == nil {
            scheduleDwell()   // the dwell delay ran out while the pointer was moving within the item
        }
    }

    /// Sets the item to speak once the pointer has rested on it for the dwell delay.
    private func setCandidate(_ c: HoverTarget?) {
        candidate = c
        candidateSince = .now
        dwellTimer?.cancel()
        dwellTimer = nil
        scheduleDwell()
    }

    /// Calls `dwellElapsed()` when the candidate has been under the pointer for the dwell delay.
    private func scheduleDwell() {
        guard let c = candidate, !c.isSameItem(as: spoken) else { return }
        let remaining = max(0, Prefs.dwell - (ContinuousClock.now - candidateSince) / .seconds(1))
        let work = DispatchWorkItem { [weak self] in self?.dwellElapsed() }
        dwellTimer = work
        queue.asyncAfter(deadline: .now() + remaining, execute: work)
    }

    private func dwellElapsed() {
        dwellTimer = nil
        guard isActive, let c = candidate, !c.isSameItem(as: spoken) else { return }
        if CGEvent(source: nil)?.location != lastMouse {
            // A user movement since the lookup gets a lookup of its own. Otherwise something
            // else (Zoom, an app) moved the pointer, and the item may no longer be under it.
            if !moves.hasPendingMove { candidate = nil }
            return
        }
        spoken = c
        if Prefs.useVOSummary && c.line == nil {
            VoiceOver.sayMouseSummary()
        } else if let text = c.text {
            VoiceOver.say(text)
        }
    }
}
