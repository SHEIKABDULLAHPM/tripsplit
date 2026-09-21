/// Legal copy served to clients.
///
/// Effective, versioned legal text. If anything changes, bump
/// [LegalBundle.termsVersion] and each document's effectiveVersion on the
/// app and the server together so clients always accept the current terms.
library;

/// A single section within a legal document.
class LegalSection {
  final String heading;
  final String body;

  const LegalSection(this.heading, this.body);
}

/// A versioned legal document.
class LegalDocument {
  final String name;
  final String title;
  final String? jurisdiction;
  final String? effectiveVersion;
  final bool draft;
  final List<LegalSection> sections;

  const LegalDocument({
    required this.name,
    required this.title,
    required this.sections,
    this.jurisdiction,
    this.effectiveVersion,
    this.draft = true,
  });
}

/// The full legal bundle. Mutable data — edit here, never in Flutter code,
/// so clients always render whatever the server currently declares.
class LegalBundle {
  final String termsVersion;
  final String jurisdiction;
  final String contactEmail;
  final List<LegalDocument> documents;

  const LegalBundle({
    required this.termsVersion,
    required this.jurisdiction,
    required this.contactEmail,
    required this.documents,
  });

/// The effective, current legal bundle.
  static LegalBundle defaults() => const LegalBundle(
        termsVersion: '2026-09-21',
    jurisdiction: 'India',
    contactEmail: 'support@tripsplit.in',
    documents: [
      LegalDocument(
        name: 'overview',
        title: 'Funding Overview',
        jurisdiction: 'India',
effectiveVersion: '2026-09-21',
            draft: false,
        sections: [
          LegalSection(
            'What this is',
            'Funding is an optional, voluntary transfer of money to '
                'support the TripSplit project. It is not a subscription, '
                'a membership, a wallet, or a prepaid credit. It does not '
                'unlock any feature, change how TripSplit works, or store '
                'money on the app.',
          ),
          LegalSection(
            'What funding is not',
            'Funding does not alter trip calculations, balances, '
                'settlements, teams, or budgets. Funding records are kept '
                'separately from your trip data and are not synced to your '
                'device except for your own order history.',
          ),
        ],
      ),
      LegalDocument(
        name: 'terms',
        title: 'Funding Terms',
        jurisdiction: 'India',
effectiveVersion: '2026-09-21',
            draft: false,
        sections: [
          LegalSection(
            '1. Agreement',
            'By funding TripSplit you agree to these terms. The amount you '
                'pay is exactly the amount shown at checkout; no '
                'subscription or recurring charge is created.',
          ),
          LegalSection(
            '2. No goods or services',
            'Funding is a voluntary contribution. No product, stock, '
                'share, or membership is issued in return.',
          ),
          LegalSection(
            '3. Acceptance',
            'By tapping the payment button you confirm you have read these '
                'terms (version 2026-09-21) and the privacy and refund '
                'notices.',
          ),
        ],
      ),
      LegalDocument(
        name: 'privacy',
        title: 'Privacy Notice',
        jurisdiction: 'India',
effectiveVersion: '2026-09-21',
            draft: false,
        sections: [
          LegalSection(
            '1. Data collected',
            'When you fund, the payment provider receives your payment '
                'details. We receive a reference, the amount, and the '
                'payment confirmation only. We never receive or store card '
                'numbers or bank account details.',
          ),
          LegalSection(
            '2. Trip data',
            'Your trip, expense, and settlement data never leaves your '
                'device. Funding records are the only online data and they '
                'are separate from your trips.',
          ),
          LegalSection(
            '3. Retention',
            'Order records are kept for accounting and reconciliation and '
                'are held no longer than required by applicable law.',
          ),
        ],
      ),
      LegalDocument(
        name: 'refund',
        title: 'Refund Policy',
        jurisdiction: 'India',
effectiveVersion: '2026-09-21',
            draft: false,
        sections: [
          LegalSection(
            '1. Contributions are final',
            'Funding is a voluntary contribution and is generally not '
                'refundable.',
          ),
          LegalSection(
            '2. Exception',
            'If a payment was charged twice, or was captured in error '
                '(for example a failed checkout billed anyway), contact '
                'support@tripsplit.in and the payment will be refunded '
                'in full within a reasonable time.',
          ),
          LegalSection(
            '3. Contact',
            'Refund requests must identify the order reference shown on '
                'the receipt.',
          ),
        ],
      ),
      LegalDocument(
        name: 'payment',
        title: 'Payment Information',
        jurisdiction: 'India',
effectiveVersion: '2026-09-21',
            draft: false,
        sections: [
          LegalSection(
            '1. Currency',
            'Payments are processed in Indian Rupees (INR).',
          ),
          LegalSection(
            '2. Processor',
            'Payments are handled by the configured payment provider. '
                'See their own terms and privacy notice for how they '
                'process payments.',
          ),
          LegalSection(
            '3. Confirmation',
            'A confirmed payment is recorded against your order reference '
                'and shown on your receipt.',
          ),
        ],
      ),
    ],
  );
}
