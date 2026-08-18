import Foundation

/// One byte-formatting routine for the whole app.
///
/// Decimal units, matching Finder and macOS's own storage display. A technician
/// comparing DiagClean's "1.2 GB" against Finder's number should see the same figure —
/// if the two disagree, the tool looks wrong even when it isn't.
public enum ByteFormat {
    public static func string(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: bytes)
    }
}
