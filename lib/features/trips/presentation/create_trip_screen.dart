import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/calculations/money.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/widgets/app_date_field.dart';
import '../../../core/widgets/app_money_field.dart';
import '../../../core/widgets/app_section_header.dart';
import '../../../injection/database_providers.dart';
import '../domain/trip_repository.dart' show NewMemberDraft;

/// Create-trip screen shown at `/trips/new`.
///
/// Collects the trip name and optional details. The goal is fast trip
/// creation — only the name is required; everything else can be added later.
class CreateTripScreen extends ConsumerStatefulWidget {
  const CreateTripScreen({super.key});

  @override
  ConsumerState<CreateTripScreen> createState() => _CreateTripScreenState();
}

class _MemberDraftController {
  final name = TextEditingController();
  final contribution = TextEditingController();
}

class _CreateTripScreenState extends ConsumerState<CreateTripScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _budgetController = TextEditingController();
  final _startLocationController = TextEditingController();
  final _members = <_MemberDraftController>[];

  bool _saving = false;
  bool _showMembers = false;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void dispose() {
    _nameController.dispose();
    _budgetController.dispose();
    _startLocationController.dispose();
    for (final member in _members) {
      member.name.dispose();
      member.contribution.dispose();
    }
    super.dispose();
  }

  void _addMember() {
    setState(() => _members.add(_MemberDraftController()));
  }

  void _openMembers() {
    setState(() {
      _showMembers = true;
      _addMember();
    });
  }

  void _removeMember(_MemberDraftController member) {
    setState(() => _members.remove(member));
    member.name.dispose();
    member.contribution.dispose();
  }

  void _skipMembers() {
    for (final member in _members) {
      member.name.dispose();
      member.contribution.dispose();
    }
    setState(() {
      _showMembers = false;
      _members.clear();
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final name = _nameController.text.trim();
    final budget = _budgetController.text.trim().isEmpty
        ? 0
        : MoneyCalculator.parseToMinor(_budgetController.text, label: 'Budget');

    final startDate = _startDate;
    final endDate = _endDate;
    if (startDate != null && endDate != null && endDate.isBefore(startDate)) {
      _showError('End date cannot be before the start date.');
      return;
    }

    final drafts = <NewMemberDraft>[];
    final seen = <String>{};
    for (final member in _members) {
      final memberName = member.name.text.trim();
      if (memberName.isEmpty) {
        continue;
      }
      if (!seen.add(memberName.toLowerCase())) {
        _showError('Members must have unique names.');
        return;
      }
      final contribution = member.contribution.text.trim().isEmpty
          ? 0
          : MoneyCalculator.parseToMinor(
              member.contribution.text,
              label: 'Contribution for $memberName',
            );
      drafts.add(
        NewMemberDraft(name: memberName, contributionMinor: contribution),
      );
    }

    setState(() => _saving = true);
    try {
      final startLocation = _startLocationController.text.trim();
      final tripId = await ref
          .read(tripRepositoryProvider)
          .createWithSetup(
            name: name,
            budgetMinor: budget,
            members: drafts,
            startLocation: startLocation,
            startDate: startDate,
            endDate: endDate,
          );
      // Seed the journey with its starting point so segment-building can
      // begin from the home city right away.
      if (startLocation.isNotEmpty) {
        await ref
            .read(journeyRepositoryProvider)
            .addLocation(tripId, startLocation);
      }
      if (!mounted) {
        return;
      }
      context.go(AppRoutes.trip(tripId));
    } on AppException catch (error) {
      if (mounted) {
        _showError(error.message);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('New trip')),
    body: SafeArea(
      bottom: true,
      child: Form(
        key: _formKey,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.xxl,
          ),
          children: [
            const SectionHeader('Trip information'),
            TextFormField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Trip name',
                hintText: 'e.g. Summer in Rome',
              ),
              validator: _required('Trip name'),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppMoneyField(
              controller: _budgetController,
              label: 'Planned group budget',
              hintText: 'e.g. 2500',
              constraint: AppMoneyConstraint.optionalNonNegative,
              negativeMessage: 'Budget cannot be negative.',
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _startLocationController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Starting from',
                hintText: 'e.g. Erode',
                helperText: 'Optional — where the journey begins',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
              maxLength: 80,
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: AppDateField(
                    label: 'Start date',
                    value: _startDate,
                    onChanged: (date) => setState(() => _startDate = date),
                    clearable: true,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppDateField(
                    label: 'End date',
                    value: _endDate,
                    onChanged: (date) => setState(() => _endDate = date),
                    clearable: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (!_showMembers) ...[
              _buildAddMembersPrompt(),
            ] else ...[
              SectionHeader(
                'Members',
                trailing: TextButton.icon(
                  onPressed: _addMember,
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Add'),
                ),
              ),
              for (final member in _members) ...[
                _MemberField(
                  member: member,
                  onRemove: () => _removeMember(member),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (_members.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Text(
                    'No members added yet — you can add them later.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _skipMembers,
                  icon: const Icon(Icons.schedule_outlined),
                  label: const Text('I\'ll add members later'),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: _saving ? null : _submit,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: const Text('Create trip'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () => context.pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildAddMembersPrompt() => Card(
    margin: EdgeInsets.zero,
    child: InkWell(
      onTap: _openMembers,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Row(
          children: [
            Icon(
              Icons.group_add_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add members',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Optional — you can add them later',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    ),
  );

  FormFieldValidator<String> _required(String label) => (value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter a $label';
    }
    return null;
  };
}

class _MemberField extends StatelessWidget {
  const _MemberField({required this.member, required this.onRemove});

  final _MemberDraftController member;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: TextFormField(
                controller: member.name,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Name required'
                    : null,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              flex: 2,
              child: AppMoneyField(
                controller: member.contribution,
                label: 'Contribution',
                hintText: 'Optional',
                constraint: AppMoneyConstraint.optionalNonNegative,
                negativeMessage: 'Contribution cannot be negative.',
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Remove member',
              onPressed: onRemove,
              icon: const Icon(Icons.close),
              color: theme.colorScheme.error,
            ),
          ],
        ),
      ),
    );
  }
}
