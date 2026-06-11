/// Poll policies — one source of truth for the privacy defaults
/// (Revolution spec §3 principles 1–2, §5).
///
/// All journey machines, screens and the relayer client reference these
/// enums; the defaults are part of the product contract, not configuration.
library;

/// When voters and the public may see the tally.
enum ResultsPolicy {
  /// No tally is shown while voting is open; results appear at close.
  /// The DEFAULT (spec §5: "sealed until close" — no partial tallies).
  sealedUntilClose,

  /// Tally is visible live during voting. Explicit organizer opt-in at
  /// creation time (Slido/Mentimeter pattern).
  livePublic;

  /// The product default for new polls.
  static const ResultsPolicy defaultPolicy = ResultsPolicy.sealedUntilClose;
}

/// Whether a poll appears in the public directory.
enum PollVisibility {
  /// Discoverable only by link/QR/code. The DEFAULT (spec §5: private by
  /// default — discovery and timing are not broadcast).
  unlisted,

  /// Opted in to the public listed directory at creation time.
  listed;

  /// The product default for new polls.
  static const PollVisibility defaultVisibility = PollVisibility.unlisted;
}
