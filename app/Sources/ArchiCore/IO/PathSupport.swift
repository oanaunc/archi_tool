// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// File-system path helpers that work on macOS, Linux and Windows.
public enum PathSupport {
    /// True for absolute paths: "/…" (Unix), "\…" (Windows root or UNC), "C:…" (Windows drive letter) and "~" (home).
    public static func isAbsolute(_ p: String) -> Bool {
        if p.hasPrefix("/") || p.hasPrefix("\\") || p.hasPrefix("~") { return true }
        let c = Array(p.prefix(2))
        return c.count == 2 && c[1] == ":" && c[0].isLetter
    }
}
