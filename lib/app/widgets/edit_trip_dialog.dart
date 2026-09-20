import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/calculations/money.dart';
import '../../core/errors/app_exception.dart';
import '../../core/widgets/app_date_field.dart';
import '../../features/trips/domain/trip.dart';
import '../../injection/database_providers.dart';

/// Shared edit-trip dialog used by HomeScreen and TripDashboardScreen.
class EditTripDialog extends ConsumerStatefulWidget {
  const EditTripDialog({super.key, required this.trip});

  final Trip trip;

  @override
  ConsumerState<EditTripDialog> createState() => _EditTripDialogState();
}

class _EditTripDialogState extends ConsumerState<EditTripDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _budgetController;
  late final TextEditingController _locationController;
  late DateTime? _startDate;
  late DateTime? _endDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.trip.name);
    _budgetController = TextEditingController(
      text: widget.trip.totalBudgetMinor > 0
          ? MoneyCalculator.formatNoSymbol(widget.trip.totalBudgetMinor)
          : '',
    );
    _locationController = TextEditingController(
      text: widget.trip.startLocation ?? '',
    );
    _startDate = widget.trip.startDate;
    _endDate = widget.trip.endDate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _budgetController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final budget = _budgetController.text.trim().isEmpty
        ? 0
        : MoneyCalculator.parseToMinor(_budgetController.text, label: 'Budget');

    final startDate = _startDate;
    final endDate = _endDate;
    if (startDate != null && endDate != null && endDate.isBefore(startDate)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('End date cannot be before the start date.'),
          ),
        );
      }
      return;
    }

    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      await ref
          .read(tripRepositoryProvider)
          .save(
            widget.trip.copyWith(
              name: name,
              totalBudgetMinor: budget,
              startLocation: _locationController.text.trim().isEmpty
                  ? null
                  : _locationController.text.trim(),
              startDate: startDate,
              endDate: endDate,
              updatedAt: now,
            ),
          );
      if (mounted) Navigator.of(context).pop();
    } on AppException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit trip'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _nameController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Trip name'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _budgetController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Budget',
              hintText: 'e.g. 2500',
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _locationController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Starting from',
              hintText: 'e.g. Erode',
            ),
            maxLength: 80,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: AppDateField(
                  label: 'Start date',
                  value: _startDate,
                  onChanged: (d) => setState(() => _startDate = d),
                  clearable: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppDateField(
                  label: 'End date',
                  value: _endDate,
                  onChanged: (d) => setState(() => _endDate = d),
                  clearable: true,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: _saving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Save'),
      ),
    ],
  );
}
