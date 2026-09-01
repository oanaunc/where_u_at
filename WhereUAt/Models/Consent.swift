import Foundation

/// The consent the person gives before Where U At processes anything about them.
///
/// Under GDPR consent must be freely given, specific, informed and unambiguous —
/// so it is its own screen with its own affirmative action, never bundled into
/// another step, and never pre-ticked. Withdrawing it has to be as easy as
/// giving it, which is why the You tab carries a one-tap withdrawal.
enum Consent {

    /// Bump this when the policy changes materially. A person whose stored
    /// version doesn't match is asked again rather than silently carried over.
    static let currentVersion = "2026-09-01"

    static let privacyPolicyURL = URL(string: "https://oanarinaldi.com/whereuatprivacy.html")!
    static let supportURL = URL(string: "https://oanarinaldi.com/whereuatsupport.html")!

    /// What the person is actually agreeing to, in the order it matters.
    static let points: [(symbol: String, title: String, detail: String)] = [
        ("location.fill",
         "Your location is shared with people you accept",
         "Only with them. Never with us — we have no server and no way to look at it."),
        ("clock.arrow.circlepath",
         "Only your latest position is kept",
         "Each new reading replaces the last. No history of where you've been exists anywhere."),
        ("hand.raised.fill",
         "You can stop at any time",
         "Pause for everyone or one person, or withdraw this agreement entirely in Settings.")
    ]
}
