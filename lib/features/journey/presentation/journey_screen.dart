import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/calculations/participation.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/widgets/app_section_header.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/member_avatar.dart';
import '../../../injection/database_providers.dart';
import '../../journey/domain/journey.dart';
import '../../members/domain/member.dart';
import '../../trips/data/trip_views.dart';

/// Journey screen: visual route map, segment management, participant assignment.
class JourneyScreen extends ConsumerWidget {
  const JourneyScreen({super.key, required this.tripId});

  final int tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(tripViewProvider(tripId));
    final journey = ref.watch(journeyViewProvider(tripId));

    return Scaffold(
      appBar: AppBar(title: const Text('Journey')),
      body: SafeArea(
        bottom: true,
        child: AsyncValueView<TripView?>(
          value: view,
          onRetry: () => ref.invalidate(tripViewProvider(tripId)),
          isEmpty: (value) => value == null,
          empty: const EmptyState(
            icon: Icons.route_outlined,
            title: 'No journey',
            message: 'This trip could not be found.',
          ),
          builder: (tripView) {
            if (tripView == null) return const SizedBox.shrink();
            return _JourneyBody(
              tripId: tripId,
              tripStartLocation: tripView.trip.startLocation,
              members: tripView.members,
              journey:
                  journey.value ??
                  const JourneyView(
                    locations: [],
                    segments: [],
                    participations: [],
                  ),
            );
          },
        ),
      ),
    );
  }
}

class _JourneyBody extends ConsumerStatefulWidget {
  const _JourneyBody({
    required this.tripId,
    required this.tripStartLocation,
    required this.members,
    required this.journey,
  });

  final int tripId;
  final String? tripStartLocation;
  final List<Member> members;
  final JourneyView journey;

  @override
  ConsumerState<_JourneyBody> createState() => _JourneyBodyState();
}

class _JourneyBodyState extends ConsumerState<_JourneyBody> {
  final _locationNameController = TextEditingController();
  bool _saving = false;

  /// Optimistic overrides for member participation toggles.
  /// Key: (memberId, segmentId), Value: participating state.
  /// These are applied immediately on toggle for instant UI feedback,
  /// then cleared when the stream delivers the authoritative data.
  final Map<(int, int), bool> _participationOverrides = {};

  @override
  void didUpdateWidget(covariant _JourneyBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When the parent rebuilds with fresh journey data from the stream,
    // clear overrides that have been resolved (the stream data now matches).
    if (oldWidget.journey != widget.journey) {
      _clearResolvedOverrides();
    }
  }

  /// Remove overrides whose values now match the stream data.
  void _clearResolvedOverrides() {
    final resolved = <(int, int)>[];
    for (final entry in _participationOverrides.entries) {
      final memberId = entry.key.$1;
      final segmentId = entry.key.$2;
      final expected = widget.journey.participations.any(
        (p) =>
            p.memberId == memberId &&
            p.segmentId == segmentId &&
            p.participating == entry.value,
      );
      if (expected) {
        resolved.add(entry.key);
      }
    }
    for (final key in resolved) {
      _participationOverrides.remove(key);
    }
  }

  @override
  void dispose() {
    _locationNameController.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addLocation() async {
    final name = _locationNameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(journeyRepositoryProvider)
          .addLocation(widget.tripId, name);
      _locationNameController.clear();
      if (mounted) Navigator.of(context).pop();
    } on AppException catch (e) {
      _showSnack(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteLocation(int locationId) async {
    try {
      await ref.read(journeyRepositoryProvider).deleteLocation(locationId);
    } on AppException catch (e) {
      _showSnack(e.message);
    }
  }

  Future<void> _addSegment({
    required int startLocationId,
    required int endLocationId,
  }) async {
    try {
      await ref
          .read(journeyRepositoryProvider)
          .addSegment(
            widget.tripId,
            startLocationId: startLocationId,
            endLocationId: endLocationId,
          );
    } on AppException catch (e) {
      _showSnack(e.message);
    }
  }

  Future<void> _deleteSegment(int segmentId) async {
    try {
      await ref.read(journeyRepositoryProvider).deleteSegment(segmentId);
    } on AppException catch (e) {
      _showSnack(e.message);
    }
  }

  Future<void> _reorderSegments(int oldIndex, int newIndex) async {
    final segments = widget.journey.segments;
    if (segments.isEmpty) return;
    final ordered = List<int>.from(segments.map((s) => s.id));
    if (oldIndex < newIndex) newIndex--;
    final item = ordered.removeAt(oldIndex);
    ordered.insert(newIndex, item);
    try {
      await ref.read(journeyRepositoryProvider).resequenceSegments(ordered);
    } on AppException catch (e) {
      _showSnack(e.message);
    }
  }

  Future<void> _saveMemberTravel(Member member, {int? join, int? leave}) async {
    try {
      await ref
          .read(memberRepositoryProvider)
          .save(member.copyWith(joinLocationId: join, leaveLocationId: leave));
    } on AppException catch (e) {
      _showSnack(e.message);
    }
  }

  void _editSegmentParticipants(TravelSegmentView view) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Who travelled ${view.label}',
                  style: Theme.of(sheetContext).textTheme.sectionTitle,
                ),
                const SizedBox(height: 4),
                Text(
                  'Defaults come from each member\'s join/leave location. Toggle individuals who travelled otherwise.',
                  style: Theme.of(sheetContext).textTheme.captionMuted,
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final member in widget.members)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(member.name),
                          secondary: MemberAvatar(member.name, radius: 14),
                          value: _isParticipating(
                            view.segment.id,
                            member.id,
                            view,
                          ),
                          onChanged: (value) {
                            // Apply optimistic update and refresh the sheet.
                            setState(() {
                              _participationOverrides[(
                                    member.id,
                                    view.segment.id,
                                  )] =
                                  value;
                            });
                            setSheetState(() {});
                            _persistParticipation(
                              view.segment.id,
                              member.id,
                              value,
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Whether a member is participating in a segment, checking optimistic
  /// overrides first, then the stream-derived participation data.
  bool _isParticipating(int segmentId, int memberId, TravelSegmentView view) {
    final override = _participationOverrides[(memberId, segmentId)];
    if (override != null) return override;
    return view.effectiveParticipants.contains(memberId);
  }

  /// Persists the participation change in the background without blocking
  /// the UI.
  Future<void> _persistParticipation(
    int segmentId,
    int memberId,
    bool value,
  ) async {
    try {
      await ref
          .read(journeyRepositoryProvider)
          .setParticipation(
            memberId: memberId,
            segmentId: segmentId,
            participating: value,
          );
    } on AppException catch (e) {
      // Revert optimistic override on failure.
      if (mounted) {
        setState(() {
          _participationOverrides.remove((memberId, segmentId));
        });
        _showSnack(e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final journey = widget.journey;
    final locations = journey.locations;
    final segments = journey.segments;

    final startName = segments.isNotEmpty
        ? (journey.locationById(segments.first.startLocationId)?.name ??
              widget.tripStartLocation ??
              '?')
        : (widget.tripStartLocation ?? 'Start');

    final endName = segments.isNotEmpty
        ? (journey.locationById(segments.last.endLocationId)?.name ?? '?')
        : null;

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      children: [
        // ── Visual Route Map ──
        if (locations.isNotEmpty)
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Route', style: theme.textTheme.statLabel),
                  const SizedBox(height: 12),
                  _VisualRoute(
                    locations: locations,
                    segments: segments,
                    journey: journey,
                  ),
                  if (segments.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          Icons.flag_outlined,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '$startName → $endName · ${segments.length} segment${segments.length == 1 ? '' : 's'}',
                            style: theme.textTheme.bodyMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

        const SizedBox(height: AppSpacing.md),

        // ── Segments ──
        SectionHeader(
          'Segments',
          trailing: locations.length >= 2
              ? TextButton.icon(
                  onPressed: () => _showAddSegmentSheet(theme),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                )
              : null,
        ),
        if (segments.isEmpty)
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add locations and create travel segments to track who goes where.',
                    style: theme.textTheme.bodyMuted,
                  ),
                  const SizedBox(height: 8),
                  if (locations.length < 2)
                    Text(
                      'Add at least 2 locations first.',
                      style: theme.textTheme.captionMuted,
                    ),
                ],
              ),
            ),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: segments.length,
            // ignore: deprecated_member_use
            onReorder: _reorderSegments,
            itemBuilder: (context, index) {
              final view = _toSegmentView(journey, index);
              return Card(
                key: ValueKey(segments[index].id),
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: InkWell(
                  onTap: () => _editSegmentParticipants(view),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Row(
                      children: [
                        Icon(
                          Icons.drag_handle,
                          size: 20,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                view.label,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (view.participantsChips.isNotEmpty)
                                Wrap(
                                  spacing: 4,
                                  runSpacing: 2,
                                  children: [
                                    for (final name
                                        in view.participantsChips.take(3))
                                      Chip(
                                        label: Text(
                                          name,
                                          style: theme.textTheme.labelSmall,
                                        ),
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                      ),
                                    if (view.participantsChips.length > 3)
                                      Chip(
                                        label: Text(
                                          '+${view.participantsChips.length - 3}',
                                          style: theme.textTheme.labelSmall,
                                        ),
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                      ),
                                  ],
                                )
                              else
                                Text(
                                  'Tap to set participants',
                                  style: theme.textTheme.captionMuted,
                                ),
                            ],
                          ),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Actions',
                          onSelected: (action) {
                            if (action == 'expense') {
                              context.push(
                                AppRoutes.addExpense(
                                  widget.tripId,
                                  segmentId: segments[index].id,
                                ),
                              );
                            } else if (action == 'delete') {
                              _deleteSegment(segments[index].id);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'expense',
                              child: Text('Add expense'),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete segment'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),

        const SizedBox(height: AppSpacing.md),

        // ── Locations ──
        SectionHeader(
          'Locations',
          trailing: TextButton.icon(
            onPressed: _showAddLocationDialog,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add'),
          ),
        ),
        if (locations.isEmpty)
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                'Add places like "Erode" or "Salem" to build the journey.',
                style: theme.textTheme.bodyMuted,
              ),
            ),
          )
        else
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < locations.length; i++)
                  ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Text(
                        '${i + 1}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    title: Text(locations[i].name),
                    trailing: IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => _deleteLocation(locations[i].id),
                    ),
                  ),
              ],
            ),
          ),

        const SizedBox(height: AppSpacing.md),

        // ── Who Travels Where ──
        const SectionHeader('Who travels where'),
        if (locations.isEmpty)
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                'Add locations first, then set join/leave points for each member.',
                style: theme.textTheme.bodyMuted,
              ),
            ),
          )
        else
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (final member in widget.members)
                  _MemberTravelTile(
                    member: member,
                    locations: locations,
                    onChanged: (join, leave) =>
                        _saveMemberTravel(member, join: join, leave: leave),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  TravelSegmentView _toSegmentView(JourneyView journey, int index) {
    final segment = journey.segments[index];
    final label =
        '${journey.locationById(segment.startLocationId)?.name ?? '?'} → '
        '${journey.locationById(segment.endLocationId)?.name ?? '?'}';
    final effective = _effectiveParticipants(journey, segment, index);
    final participants = [
      for (final member in widget.members)
        if (effective.contains(member.id)) member.name,
    ];
    return TravelSegmentView(
      segment: segment,
      label: label,
      participantsChips: participants,
      effectiveParticipants: effective,
    );
  }

  /// Computes the effective participants for a segment, applying any
  /// optimistic overrides on top of the stream-derived participation data.
  Set<int> _effectiveParticipants(
    JourneyView journey,
    TravelSegment segment,
    int index,
  ) {
    // Start with the stream-derived participation set.
    final effective = ParticipationCalculator.participatingMemberIds(
      segment: segment,
      segmentOrder: index,
      members: widget.members,
      segments: journey.segments,
      locations: journey.locations,
      participations: journey.participations,
    );

    // Apply any pending optimistic overrides for this segment.
    for (final member in widget.members) {
      final override = _participationOverrides[(member.id, segment.id)];
      if (override != null) {
        if (override) {
          effective.add(member.id);
        } else {
          effective.remove(member.id);
        }
      }
    }

    return effective;
  }

  void _showAddLocationDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add a location'),
        content: TextField(
          controller: _locationNameController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Location name',
            hintText: 'e.g. Salem',
          ),
          textCapitalization: TextCapitalization.words,
          onSubmitted: (_) => _addLocation(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _saving ? null : _addLocation,
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showAddSegmentSheet(ThemeData theme) {
    final journey = widget.journey;
    final locations = journey.locations;
    final connectedStart = journey.segments.isNotEmpty
        ? journey.segments.last.endLocationId
        : locations.first.id;
    final options = locations.where((l) => l.id != connectedStart).toList();

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add next segment', style: theme.textTheme.sectionTitle),
              const SizedBox(height: 4),
              Text(
                'Choose where the next leg goes from the current end point.',
                style: theme.textTheme.captionMuted,
              ),
              const SizedBox(height: 12),
              if (options.isEmpty)
                Text(
                  'No available destinations.',
                  style: theme.textTheme.bodyMuted,
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final location in options)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: MemberAvatar(location.name, radius: 14),
                          title: Text(location.name),
                          trailing: const Icon(Icons.chevron_right, size: 20),
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            _addSegment(
                              startLocationId: connectedStart,
                              endLocationId: location.id,
                            );
                          },
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class TravelSegmentView {
  const TravelSegmentView({
    required this.segment,
    required this.label,
    required this.participantsChips,
    required this.effectiveParticipants,
  });

  final TravelSegment segment;
  final String label;
  final List<String> participantsChips;
  final Set<int> effectiveParticipants;
}

class _VisualRoute extends StatelessWidget {
  const _VisualRoute({
    required this.locations,
    required this.segments,
    required this.journey,
  });

  final List<TripLocation> locations;
  final List<TravelSegment> segments;
  final JourneyView journey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 60,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: locations.length,
        itemBuilder: (context, index) {
          final location = locations[index];
          final isStart = index == 0;
          final isEnd = index == locations.length - 1;
          return Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 70,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: isStart || isEnd ? 16 : 12,
                        height: isStart || isEnd ? 16 : 12,
                        decoration: BoxDecoration(
                          color: isStart
                              ? theme.colorScheme.primary
                              : isEnd
                              ? theme.colorScheme.tertiary
                              : theme.colorScheme.primary.withAlpha(150),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        location.name,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (!isEnd)
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Container(
                      width: 40,
                      height: 2,
                      color: theme.colorScheme.primary.withAlpha(100),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MemberTravelTile extends StatelessWidget {
  const _MemberTravelTile({
    required this.member,
    required this.locations,
    required this.onChanged,
  });

  final Member member;
  final List<TripLocation> locations;
  final void Function(int? join, int? leave) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final noLocations = locations.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              MemberAvatar(member.name, radius: 14),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  member.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int?>(
                  initialValue: member.joinLocationId,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Joined at',
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('From the start'),
                    ),
                    for (final location in locations)
                      DropdownMenuItem<int?>(
                        value: location.id,
                        child: Text(
                          location.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: noLocations
                      ? null
                      : (value) => onChanged(value, member.leaveLocationId),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: DropdownButtonFormField<int?>(
                  initialValue: member.leaveLocationId,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Left at',
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('At the end'),
                    ),
                    for (final location in locations)
                      DropdownMenuItem<int?>(
                        value: location.id,
                        child: Text(
                          location.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: noLocations
                      ? null
                      : (value) => onChanged(member.joinLocationId, value),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    );
  }
}
