// User preferences (UserDefaults domain "local.vohover"). The engine reads them live,
// from its background queue (UserDefaults is thread-safe); Settings binds them with @AppStorage.

import Foundation

enum PrefKey {
    static let enabled = "enabled"
    static let dwell = "dwell"
    static let useVOSummary = "useVOSummary"
    static let includeRole = "includeRole"
    static let includeValue = "includeValue"
    static let includeState = "includeState"
    static let readContainer = "readContainer"
    static let textAreaReadsLine = "textAreaReadsLine"
    static let showInMenuBar = "showInMenuBar"
    static let announceStartQuit = "announceStartQuit"
}

enum Prefs {
    private static let defaults = UserDefaults.standard

    static func registerDefaults() {
        defaults.register(defaults: [
            PrefKey.enabled: true,
            PrefKey.dwell: 0.15,
            PrefKey.useVOSummary: false,
            PrefKey.includeRole: true,
            PrefKey.includeValue: true,
            PrefKey.includeState: true,
            PrefKey.readContainer: true,
            PrefKey.textAreaReadsLine: true,
            PrefKey.showInMenuBar: true,
            PrefKey.announceStartQuit: true,
        ])
    }

    static var enabled: Bool {
        get { defaults.bool(forKey: PrefKey.enabled) }
        set { defaults.set(newValue, forKey: PrefKey.enabled) }
    }
    static var dwell: Double { defaults.double(forKey: PrefKey.dwell) }
    static var useVOSummary: Bool { defaults.bool(forKey: PrefKey.useVOSummary) }
    static var includeRole: Bool { defaults.bool(forKey: PrefKey.includeRole) }
    static var includeValue: Bool { defaults.bool(forKey: PrefKey.includeValue) }
    static var includeState: Bool { defaults.bool(forKey: PrefKey.includeState) }
    static var readContainer: Bool { defaults.bool(forKey: PrefKey.readContainer) }
    static var textAreaReadsLine: Bool { defaults.bool(forKey: PrefKey.textAreaReadsLine) }
    static var showInMenuBar: Bool { defaults.bool(forKey: PrefKey.showInMenuBar) }
    static var announceStartQuit: Bool { defaults.bool(forKey: PrefKey.announceStartQuit) }
}
