// The "Toggle VOHover" AppleScript, for binding to a VoiceOver command
// (VoiceOver Utility > Commands > Custom Commands > Run AppleScript Script).
// The app writes it on launch when it's missing, so installs that only copy
// VOHover.app (such as Homebrew) still get it.

import Foundation

enum ToggleScript {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Scripts/VOHover/Toggle VOHover.scpt")

    /// Sends SIGUSR1, which the app handles as "toggle hover speech".
    private static let source = #"do shell script "pkill -USR1 -x VOHover || true""#

    /// Compiles the script to `url` unless it already exists. Runs in the background.
    static func installIfNeeded() {
        guard !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        DispatchQueue.global(qos: .utility).async {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")
                p.arguments = ["-o", url.path(percentEncoded: false), "-e", source]
                try p.run()
                p.waitUntilExit()
                if p.terminationStatus == 0 {
                    logger.info("Installed toggle script at \(url.path(percentEncoded: false), privacy: .public)")
                } else {
                    logger.error("osacompile failed with status \(p.terminationStatus)")
                }
            } catch {
                logger.error("Toggle script install failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
