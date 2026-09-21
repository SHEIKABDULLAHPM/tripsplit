/// Bundled legal copy for the funding feature.
///
/// Versioned and effective; the server serves the same bundle and enforces
/// its terms version. Bundled so the review screen works offline. If the
/// documents change, bump [FundingLegalBundle.effectiveVersion]/termsVersion
/// on both the app and the server together.
library;

import '../domain/funding_info.dart';

/// The funding legal bundle for this build.
abstract final class FundingLegalBundle {
  FundingLegalBundle._();

  static List<FundingDocument> get documents => const [
    FundingDocument(
      name: 'overview',
      title: 'Funding Overview',
      jurisdiction: 'India',
      effectiveVersion: '2026-09-21',
      draft: false,
      sections: [
        FundingDocumentSection(
          'What this is',
          'Funding is an optional, voluntary transfer of money to support the '
              'TripSplit project. It is not a subscription, a membership, a '
              'wallet, or a prepaid credit. It does not unlock any feature, '
              'change how TripSplit works, or store money on the app.',
        ),
        FundingDocumentSection(
          'What funding is not',
          'Funding does not alter trip calculations, balances, settlements, '
              'teams, or budgets. Funding records are kept separately from '
              'your trip data and are never synced to your trip database.',
        ),
      ],
    ),
    FundingDocument(
      name: 'terms',
      title: 'Funding Terms',
      jurisdiction: 'India',
      effectiveVersion: '2026-09-21',
      draft: false,
      sections: [
        FundingDocumentSection(
          '1. Agreement',
          'By funding TripSplit you agree to these terms. The amount you pay '
              'is exactly the amount shown at checkout; no subscription or '
              'recurring charge is created.',
        ),
        FundingDocumentSection(
          '2. No goods or services',
          'Funding is a voluntary contribution. No product, stock, share, or '
              'membership is issued in return.',
        ),
        FundingDocumentSection(
          '3. Acceptance',
          'By tapping the payment button you confirm you have read these '
              'terms (version 2026-09-21) and the privacy and refund notices.',
        ),
      ],
    ),
    FundingDocument(
      name: 'privacy',
      title: 'Privacy Notice',
      jurisdiction: 'India',
      effectiveVersion: '2026-09-21',
      draft: false,
      sections: [
        FundingDocumentSection(
          '1. Data collected',
          'When you fund, the payment provider receives your payment details. '
              'We receive a reference, the amount, and the payment '
              'confirmation only. We never receive or store card numbers or '
              'bank account details.',
        ),
        FundingDocumentSection(
          '2. Trip data',
          'Your trip, expense, and settlement data never leaves your device. '
              'Funding records are the only online data and they are separate '
              'from your trips.',
        ),
        FundingDocumentSection(
          '3. Retention',
          'Order records are kept for accounting and reconciliation and are '
              'held no longer than required by applicable law.',
        ),
      ],
    ),
    FundingDocument(
      name: 'refund',
      title: 'Refund Policy',
      jurisdiction: 'India',
      effectiveVersion: '2026-09-21',
      draft: false,
      sections: [
        FundingDocumentSection(
          '1. Contributions are final',
          'Funding is a voluntary contribution and is generally not '
              'refundable.',
        ),
        FundingDocumentSection(
          '2. Exception',
          'If a payment was charged twice, or was captured in error (for '
              'example a failed checkout billed anyway), contact the support '
              'address shown on the receipt and the payment will be refunded '
              'in full within a reasonable time.',
        ),
        FundingDocumentSection(
          '3. Contact',
          'Refund requests must identify the order reference shown on the '
              'receipt.',
        ),
      ],
    ),
    FundingDocument(
      name: 'payment',
      title: 'Payment Information',
      jurisdiction: 'India',
      effectiveVersion: '2026-09-21',
      draft: false,
      sections: [
        FundingDocumentSection(
          '1. Currency',
          'Payments are processed in Indian Rupees (INR).',
        ),
        FundingDocumentSection(
          '2. Processor',
          'Payments are handled by the configured payment provider. See their '
              'own terms and privacy notice for how they process payments.',
        ),
        FundingDocumentSection(
          '3. Confirmation',
          'A confirmed payment is recorded against your order reference and '
              'shown on your receipt.',
        ),
      ],
    ),
  ];

  static FundingDocument? documentFor(String name) {
    for (final doc in documents) {
      if (doc.name == name) return doc;
    }
    return null;
  }
}
