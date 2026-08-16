import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../ui/feedback.dart';
import '../../core/dependency_models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/data.dart';
import '../../ui/icons.dart';
import '../../ui/overlays.dart';
import '../../ui/status.dart';
import '../../ui/surfaces.dart';
import '../../ui/text.dart';
import 'dependencies_controller.dart';
import 'services_controller.dart';

extension _DependencyLevelStatusKindX on DependencyLevel {
  StatusKind get statusKind => switch (this) {
    DependencyLevel.ok => StatusKind.good,
    DependencyLevel.warn => StatusKind.warn,
    DependencyLevel.fail => StatusKind.bad,
  };
}

/// `ui/status.dart`'s icon vocabulary lives behind `AppIcons`
/// (a `ui/` concern) — `core/dependency_models.dart` can't reach it without
/// inverting the `core/` → `ui/` layering (D100's precedent), so the mapping
/// lives here instead, the only consumer.
extension _DependencyLevelIconX on DependencyLevel {
  PhosphorIconData Function(PhosphorIconsStyle) get glyph => switch (this) {
    DependencyLevel.ok => AppIcons.success,
    DependencyLevel.warn => AppIcons.warning,
    DependencyLevel.fail => AppIcons.error,
  };
}

/// The read-only half of Phase 2: k3s, Postgres, Prefect, the two pods, the
/// phone, the internet, Syncthing and disk. The agent supervises none of these,
/// so there is nothing to click — the value is knowing which one is why a flow
/// is failing.
class DependenciesTab extends ConsumerStatefulWidget {
  const DependenciesTab({super.key});

  @override
  ConsumerState<DependenciesTab> createState() => _DependenciesTabState();
}

class _DependenciesTabState extends ConsumerState<DependenciesTab> {
  bool _refreshing = false;

  // Worst-first by default (`DependencyLevel`'s declared order is
  // ok/warn/fail, so descending sorts fail to the top) — "the value is
  // knowing which one is why a flow is failing," not which group it's in.
  AppTableSort _sort = const AppTableSort(columnIndex: 2, ascending: false);

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    await ref.read(dependenciesControllerProvider.notifier).refresh();
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(dependenciesControllerProvider);

    return async.stateView(
      describeError: describeAgentError,
      onRetry: _refresh,
      data: (snapshot) {
        final tokens = theme.tokens;
        final columns = dependencyTableColumns();
        final sortKey = columns[_sort.columnIndex].sortKey;
        var rows = snapshot.items;
        if (sortKey != null) {
          rows = [...rows]..sort((a, b) => sortKey(a).compareTo(sortKey(b)));
          if (!_sort.ascending) rows = rows.reversed.toList();
        }

        return ListView(
          padding: EdgeInsets.all(tokens.space.lg),
          children: [
            _summary(theme, snapshot),
            SizedBox(height: tokens.space.xl),
            AppPanel(
              padding: EdgeInsets.zero,
              child: AppTable<Dependency>(
                columns: columns,
                rows: rows,
                sort: _sort,
                onSort: (sort) => setState(() => _sort = sort),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _summary(ThemeData theme, DependencySnapshot snapshot) {
    final tokens = theme.tokens;
    final worst = snapshot.worst;
    final headline = switch (worst) {
      DependencyLevel.ok => 'Everything the pipeline depends on is up',
      DependencyLevel.warn => '${snapshot.warn} need attention',
      DependencyLevel.fail => '${snapshot.fail} down',
    };

    return AppPanel(
      level: SurfaceLevel.raised,
      borderRadius: tokens.geometry.radiusLg,
      child: Row(
        children: [
          AppIcon(worst.glyph, color: worst.color(theme)),
          SizedBox(width: tokens.space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(headline, style: theme.textTheme.titleMedium),
                SizedBox(height: tokens.space.xs / 2),
                Text(
                  '${snapshot.ok} ok · ${snapshot.warn} warning · ${snapshot.fail} failed — '
                  'checked ${TimeOfDay.fromDateTime(snapshot.checkedAt).format(context)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary),
                ),
              ],
            ),
          ),
          _refreshing
              ? Padding(
                  padding: EdgeInsets.symmetric(horizontal: tokens.space.lg),
                  child: const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : FilledButton.tonalIcon(
                  onPressed: _refresh,
                  icon: AppIcon(AppIcons.refresh, size: IconSize.sm),
                  label: const Text('Re-check'),
                ),
        ],
      ),
    );
  }
}

/// Public for the layout test: a failing dependency's long detail sentence is
/// the longest text on the screen, and the flexible Detail column has to
/// survive the narrow pane without overflowing. One flat, sortable table
/// across all ten dependencies (not the four group sections the old bespoke
/// rows had) — sorting by State surfaces every failure together regardless of
/// which group it's in, the more operationally useful default. Each group's
/// explanatory blurb moves into a tooltip on its row's Group cell instead of
/// a standing text block, so the context isn't lost, just no longer
/// always-on.
List<AppTableColumn<Dependency>> dependencyTableColumns() => [
  AppTableColumn<Dependency>(
    label: 'Group',
    width: 90,
    sortable: true,
    sortKey: (d) => d.group.label,
    cell: (d) => AppTooltip(
      rich: true,
      title: d.group.label,
      message: d.group.blurb,
      child: Text(d.group.label, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
  ),
  AppTableColumn<Dependency>(
    label: 'Name',
    width: 140,
    sortable: true,
    sortKey: (d) => d.label,
    cell: (d) => Text(d.label, maxLines: 1, overflow: TextOverflow.ellipsis),
  ),
  AppTableColumn<Dependency>(
    label: 'State',
    width: 110,
    sortable: true,
    sortKey: (d) => d.level.index,
    cell: (d) => StatusChip(kind: d.level.statusKind, label: _levelLabel(d.level), dense: true),
  ),
  AppTableColumn<Dependency>(label: 'Detail', cell: (d) => _DetailCell(dependency: d)),
  AppTableColumn<Dependency>(
    label: 'Latency',
    width: 90,
    numeric: true,
    sortable: true,
    sortKey: (d) => d.latencyMs,
    cell: (d) => NumericText(
      '${d.latencyMs.round()} ms',
      role: TextRole.caption,
    ),
  ),
];

String _levelLabel(DependencyLevel level) => switch (level) {
  DependencyLevel.ok => 'OK',
  DependencyLevel.warn => 'Warning',
  DependencyLevel.fail => 'Failed',
};

class _DetailCell extends StatelessWidget {
  const _DetailCell({required this.dependency});

  final Dependency dependency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    return Text(
      dependency.detail,
      style: theme.textTheme.bodySmall?.copyWith(
        color: dependency.level == DependencyLevel.ok ? tokens.content.secondary : null,
      ),
    );
  }
}
