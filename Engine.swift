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

// MARK: - Engine

/// Polls the pointer on a background queue. Accessibility queries must not run on the
/// main thread: VOHover's own windows and menus are answered by the main thread, which
/// is also busy while a menu is open. All state below is confined to `queue`.
final class HoverEngine {
    private let queue = DispatchQueue(label: "io.github.endernoke.vohover.engine", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var lastMouse: CGPoint?
    private var candidate: HoverTarget?
    private var candidateSince = ContinuousClock.now
    private var spoken: HoverTarget?
    private var promptedForAccess = false

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(50), leeway: .milliseconds(10))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    /// Forget the last item so the next one under the pointer is spoken again.
    func reset() {
        queue.async { [self] in spoken = nil; candidate = nil; lastMouse = nil }
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

    private func tick() {
        guard Prefs.enabled, VoiceOver.isRunning, checkTrust(),
              let mouse = CGEvent(source: nil)?.location   // global, top-left origin
        else { return }

        if mouse != lastMouse {
            lastMouse = mouse
            let hit = target(at: mouse)
            let unchanged = hit.map { $0.isSameItem(as: candidate) } ?? (candidate == nil)
            if !unchanged {
                candidate = hit
                candidateSince = .now
            }
        }

        guard let c = candidate, !c.isSameItem(as: spoken),
              ContinuousClock.now - candidateSince >= .seconds(Prefs.dwell)
        else { return }
        spoken = c
        if Prefs.useVOSummary && c.line == nil {
            VoiceOver.sayMouseSummary()
        } else if let text = c.text {
            VoiceOver.say(text)
        }
    }
}
