import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../core/calculations/money.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/widgets/app_money_field.dart';
import '../../../injection/database_providers.dart';
import '../../contributions/domain/contribution.dart';
import '../../members/domain/member.dart';

/// Add-member screen shown at `/trip/:tripId/members/new`.
///
/// Collects a member name and an optional first contribution, persisting both
/// together.
class AddMemberScreen extends ConsumerStatefulWidget {
  const AddMemberScreen({super.key, required this.tripId});

  final int tripId;

  @override
  ConsumerState<AddMemberScreen> createState() => _AddMemberScreenState();
}

class _AddMemberScreenState extends ConsumerState<AddMemberScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _contributionController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _contributionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final name = _nameController.text.trim();
    final contributionMinor = _contributionController.text.trim().isEmpty
        ? 0
        : MoneyCalculator.parseToMinor(
            _contributionController.text,
            label: 'Contribution',
          );

    setState(() => _saving = true);
    try {
      final memberRepository = ref.read(memberRepositoryProvider);
      final contributionRepository = ref.read(contributionRepositoryProvider);

      final member = await memberRepository.save(
        Member(
          id: 0,
          tripId: widget.tripId,
          name: name,
          createdAt: DateTime.now(),
        ),
      );
      if (contributionMinor > 0) {
        await contributionRepository.save(
          Contribution(
            id: 0,
            tripId: widget.tripId,
            memberId: member.id,
            amountMinor: contributionMinor,
            note: null,
            createdAt: DateTime.now(),
          ),
        );
      }
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Add member')),
    body: SafeArea(
      bottom: true,
      child: Form(
        key: _formKey,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            TextFormField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Priya',
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Please enter a name'
                  : null,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppMoneyField(
              controller: _contributionController,
              label: 'First contribution (optional)',
              hintText: 'e.g. 1000',
              constraint: AppMoneyConstraint.optional,
              errorLabel: 'Contribution',
              negativeMessage: 'Contribution cannot be negative.',
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: _saving ? null : _submit,
              icon: const Icon(Icons.check),
              label: const Text('Add member'),
            ),
          ],
        ),
      ),
    ),
  );
}
