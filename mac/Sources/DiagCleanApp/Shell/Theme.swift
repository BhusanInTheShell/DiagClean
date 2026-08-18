import SwiftUI

/// The whole visual vocabulary, in one file.
///
/// The brief for this app is an appliance rather than a utility: low glare, few
/// colours, no motion that isn't communicating something. Colour is spent only where it
/// carries meaning — the one accent marks what is selected, and the one warning colour
/// marks the moment before something is deleted. Everything else is greyscale.
enum Theme {
    // MARK: Colour

    static let accent = Color(red: 0.36, green: 0.68, blue: 0.75)
    static let destructive = Color(red: 0.85, green: 0.42, blue: 0.38)

    static let windowBackground = Color(nsColor: .underPageBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let separator = Color(nsColor: .separatorColor)

    static let primaryText = Color(nsColor: .labelColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let tertiaryText = Color(nsColor: .tertiaryLabelColor)

    // MARK: Metrics

    /// A single spacing scale. Padding that isn't on it tends to be padding that was
    /// nudged until it looked right in one place and wrong everywhere else.
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    static let cornerRadius: CGFloat = 8
}

extension View {
    /// A plain card. No shadow and no gradient — depth here would be decoration, and
    /// the row's own contents are what should be drawing the eye.
    func cardSurface() -> some View {
        background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .stroke(Theme.separator, lineWidth: 0.5)
            )
    }
}

/// Monospaced digits everywhere a size is shown, so a column of figures doesn't shuffle
/// sideways as it updates during a clean.
extension Text {
    func sizeStyle() -> Text {
        monospacedDigit()
    }
}

enum PathDisplay {
    /// `~/Library/Caches/…` rather than `/Users/someone/Library/Caches/…`. Shorter, and
    /// it keeps somebody's account name out of a screenshot pasted into a ticket.
    static func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
