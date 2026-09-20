import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../core/calculations/money.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/widgets/app_money_field.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../injection/database_providers.dart';
import '../../contributions/domain/contribution.dart';
import '../../trips/data/trip_views.dart';

/// Record-contribution screen shown at `/trip/:tripId/contributions/new`.
///
/// Credited cash into the trip pool for a chosen member.
class AddContributionScreen extends ConsumerStatefulWidget {
  const AddContributionScreen({super.key, required this.tripId});

  final int tripId;

  @override
  ConsumerState<AddContributionScreen> createState() =>
      _AddContributionScreenState();
}

class _AddContributionScreenState extends ConsumerState<AddContributionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _noteController = TextEditingController();
  int? _memberId;
  final _amountController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _noteController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final amountMinor = MoneyCalculator.parseToMinor(
      _amountController.text,
      label: 'Contribution',
    );
    setState(() => _saving = true);
    try {
      await ref
          .read(contributionRepositoryProvider)
          .save(
            Contribution(
              id: 0,
              tripId: widget.tripId,
              memberId: _memberId!,
              amountMinor: amountMinor,
              note: _noteController.text.trim().isEmpty
                  ? null
                  : _noteController.text.trim(),
              createdAt: DateTime.now(),
            ),
          );
      if (mounted) {
        context.pop();
      }
    } on AppException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(tripViewProvider(widget.tripId));

    return Scaffold(
      appBar: AppBar(title: const Text('Record contribution')),
      body: SafeArea(
        bottom: true,
        child: AsyncValueView<TripView?>(
          value: view,
          onRetry: () => ref.invalidate(tripViewProvider(widget.tripId)),
          isEmpty: (value) => value == null || value.members.isEmpty,
          empty: const Center(child: Text('Add a member first.')),
          builder: (tripView) {
            if (tripView == null) {
              return const Center(child: Text('Add a member first.'));
            }
            _memberId ??= tripView.members.first.id;
            return Form(
              key: _formKey,
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.all(AppSpacing.xl),
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: _memberId,
                    decoration: const InputDecoration(labelText: 'Member'),
                    items: [
                      for (final member in tripView.members)
                        DropdownMenuItem(
                          value: member.id,
                          child: Text(member.name),
                        ),
                    ],
                    onChanged: (value) => setState(() => _memberId = value),
                    validator: (value) =>
                        value == null ? 'Select a member' : null,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppMoneyField(
                    controller: _amountController,
                    label: 'Amount',
                    hintText: 'e.g. 1000',
                    constraint: AppMoneyConstraint.requiredPositive,
                    errorLabel: 'Contribution',
                    autofocus: true,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextFormField(
                    controller: _noteController,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Note (optional)',
                      hintText: 'Optional',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton.icon(
                    onPressed: _saving ? null : _submit,
                    icon: const Icon(Icons.check),
                    label: const Text('Save contribution'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
