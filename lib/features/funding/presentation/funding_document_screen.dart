import 'package:flutter/material.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../config/funding_config.dart';
import '../config/funding_legal_bundle.dart';

/// Renders one legal/document copy of the funding feature.
///
/// Read-only and offline-capable; the document is bundled with the app and
/// also served (versioned) by the funding server.
class FundingDocumentScreen extends StatelessWidget {
  const FundingDocumentScreen({super.key, required this.documentName});

  final String documentName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final doc = FundingLegalBundle.documentFor(documentName);

    return Scaffold(
      appBar: AppBar(title: Text(doc?.title ?? 'Funding documents')),
      body: doc == null
          ? Center(
              child: Text(
                'Document not found.',
                style: theme.textTheme.bodyMuted,
              ),
            )
          : SafeArea(
              bottom: true,
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenHorizontal,
                  vertical: AppSpacing.screenVertical,
                ),
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer.withValues(
                        alpha: 0.4,
                      ),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 20,
                          color: theme.colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'DRAFT DOCUMENT — informational only. Not final '
                            'legal advice.',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(doc.title, style: theme.textTheme.screenTitle),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    [
                      if (doc.effectiveVersion != null)
                        'Version ${doc.effectiveVersion}',
                      if (doc.jurisdiction != null) doc.jurisdiction!,
                      'Terms v${FundingConfig.currentTermsVersion}',
                    ].join(' • '),
                    style: theme.textTheme.captionMuted,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  for (final section in doc.sections) ...[
                    Text(section.heading, style: theme.textTheme.sectionTitle),
                    const SizedBox(height: AppSpacing.xs),
                    Text(section.body, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  Center(
                    child: Text(
                      'Contact: ${FundingConfig.contactEmail}',
                      style: theme.textTheme.captionMuted,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
