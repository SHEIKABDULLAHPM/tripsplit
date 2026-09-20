/// Funding types recognized by the backend.
///
/// The canonical amount for each funding type lives here — the server is the
/// sole authority for the price, and a client can never dictate how much it
/// actually pays. Amounts are expressed in minor units (paise) and never in
/// floating point.
library;

/// The two supported funding plans.
enum FundingType {
  support49(
    wire: 'SUPPORT_49',
    displayName: 'Support Funding',
    amountMinor: 4900,
    currency: 'INR',
    purpose: 'Support the ongoing maintenance and development of TripSplit.',
  ),
  future199(
    wire: 'FUTURE_199',
    displayName: 'Future Funding',
    amountMinor: 19900,
    currency: 'INR',
    purpose:
        'Support future development, infrastructure, and the continuing '
        'evolution of TripSplit.',
  );

  /// Stable value serialized over the wire.
  final String wire;

  /// Human-friendly label shown to users.
  final String displayName;

  /// Price in minor units (paise). Server-authoritative.
  final int amountMinor;

  /// ISO 4217 currency code.
  final String currency;

  /// Purpose text presented on the checkout screen.
  final String purpose;

  const FundingType({
    required this.wire,
    required this.displayName,
    required this.amountMinor,
    required this.currency,
    required this.purpose,
  });

  /// Returns the type for a wire value, or null when unknown.
  static FundingType? fromWire(String? value) {
    for (final type in values) {
      if (type.wire == value) return type;
    }
    return null;
  }
}