import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../config/funding_config.dart';
import '../config/funding_legal_bundle.dart';
import '../domain/funding_info.dart';

/// Landing screen for the funding feature.
///
/// This is an app-level (non-trip) screen. It only reads funding config and
/// legal copy and never touches the trip database.
class FundingScreen extends StatelessWidget {
  const FundingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overview = FundingLegalBundle.documentFor('overview');

    return Scaffold(
      appBar: AppBar(title: const Text('Support TripSplit')),
      body: SafeArea(
        bottom: true,
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenHorizontal,
            vertical: AppSpacing.screenVertical,
          ),
          children: [
            Text('Keep TripSplit running', style: theme.textTheme.sectionTitle),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'TripSplit stays free and fully offline for your trips. '
              'Funding is a voluntary contribution that supports its '
              'development — it never changes how your trips work.',
              style: theme.textTheme.bodyMuted,
            ),
            const SizedBox(height: AppSpacing.lg),
            const _FundingOptionCard(type: FundingType.support49),
            const SizedBox(height: AppSpacing.md),
            const _FundingOptionCard(type: FundingType.future199),
            const SizedBox(height: AppSpacing.xl),
            if (overview != null) _LegalNoteCard(sections: overview.sections),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Text('Documents', style: theme.textTheme.sectionTitle),
                const Spacer(),
                Flexible(
                  child: Text(
                    'Terms v${FundingConfig.currentTermsVersion}',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.captionMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final doc in FundingLegalBundle.documents)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.description_outlined),
                title: Text(doc.title),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoutes.fundingDocument(doc.name)),
              ),
            const SizedBox(height: AppSpacing.lg),
            Center(
              child: Text(
                'Draft documentation — not final legal advice.',
                style: theme.textTheme.captionMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FundingOptionCard extends StatelessWidget {
  const _FundingOptionCard({required this.type});

  final FundingType type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        onTap: () =>
            context.push(AppRoutes.fundingCheckout(type.wire), extra: type),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                alignment: Alignment.center,
                child: Text(
                  '₹${type.displayRupees}',
                  style: theme.textTheme.titleBold.copyWith(
                    color: AppColors.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(type.displayName, style: theme.textTheme.subtitle),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(type.purpose, style: theme.textTheme.bodyMuted),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegalNoteCard extends StatelessWidget {
  const _LegalNoteCard({required this.sections});

  final List<FundingDocumentSection> sections;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Before you pay',
                  style: theme.textTheme.subtitle.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final section in sections.take(2)) ...[
            Text(section.body, style: theme.textTheme.bodyMuted),
            const SizedBox(height: AppSpacing.sm),
          ],
          TextButton(
            onPressed: () =>
                context.push(AppRoutes.fundingDocument('overview')),
            child: const Text('Read the full funding overview'),
          ),
        ],
      ),
    );
  }
}
