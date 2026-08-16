import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/feedback.dart';
import '../../core/insights_models.dart';
import '../../core/nav_state.dart';
import '../../core/settings_nav.dart';
import '../../core/theme/tokens.dart';
import '../../ui/data.dart';
import '../../ui/icons.dart';
import '../../ui/page.dart';
import '../../ui/status.dart';
import '../../ui/text.dart';
import '../flows/flows_controller.dart';
import '../library/entity_yield_dialog.dart';
import '../library/library_controller.dart';
import '../overview/caps_tile.dart';
import 'burndown_chart.dart';
import 'funnel_chart.dart';
import 'insights_controller.dart';

/// Only these three funnel stages have a genuine matching Library folder to
/// jump to — `Private` and `Followed` don't (a private profile never lands
/// in a browsable folder, and "followed" has none either, same reasoning
/// D81 used to drop both from the per-entity yield dialog), so those two
/// stay plain labels rather than links that would land somewhere misleading.
const _funnelStageFolders = {'Scanned': 'scanned', 'Female': 'gender_valid', 'Scraped': 'scraped'};

void _openLibraryFolder(WidgetRef ref, String folder) {
  ref.read(selectedFolderProvider.notifier).select(folder);
  ref.read(selectedEntityProvider.notifier).select(null);
  ref.read(selectedNavIndexProvider.notifier).select(libraryIndex);
}

/// Phase 7, CP 7.2 — the whole-library views the per-entity funnel (CP 5.4)
/// and the Flows screen's own "today" counters never showed on their own:
/// where the library stands in aggregate, which entities are actually
/// yielding, and whether the daily caps are being hit. Classify-accuracy
/// sampling was scoped out of this checkpoint (no persisted verdict history
/// exists to sample from — see DECISIONS.md).
class InsightsPage extends ConsumerWidget {
  const InsightsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Same `Key`-forces-a-remount trick `settings_page.dart` uses for a
    // palette-requested tab jump (V2.12) — `DefaultTabController` only ever
    // reads `initialIndex` once per mount.
    final requestedTab = ref.watch(requestedInsightsTabProvider);
    return DefaultTabController(
      key: ValueKey(requestedTab),
      initialIndex: requestedTab,
      length: 3,
      child: AppPage(
        title: 'Insights',
        maxContentWidth: 900,
        tabs: const [
          AppTab(label: 'Funnel'),
          AppTab(label: 'Ranking'),
          AppTab(label: 'Daily limits'),
        ],
        body: const TabBarView(children: [FunnelTab(), RankingTab(), BurndownTab()]),
      ),
    );
  }
}

class FunnelTab extends ConsumerWidget {
  const FunnelTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(funnelSummaryProvider);

    return async.stateView(
      describeError: describeInsightsError,
      onRetry: () => ref.invalidate(funnelSummaryProvider),
      data: (summary) {
        VoidCallback? openFolder(String label) {
          final folder = _funnelStageFolders[label];
          return folder == null ? null : () => _openLibraryFolder(ref, folder);
        }

        final stages = [
          FunnelStageData(label: 'Scanned', count: summary.scanned, onTap: openFolder('Scanned')),
          FunnelStageData(label: 'Private', count: summary.private),
          FunnelStageData(
            label: 'Female',
            count: summary.female,
            caption: summary.male > 0
                ? 'of ${summary.private} private — ${summary.male} classified male instead'
                : null,
            onTap: openFolder('Female'),
          ),
          FunnelStageData(
            label: 'Scraped',
            count: summary.scraped,
            caption: 'real all-time total — Insta-Automate\'s own daily scrape counters, summed',
            onTap: openFolder('Scraped'),
          ),
          FunnelStageData(
            label: 'Followed',
            count: summary.followed,
            caption: 'real all-time total — Insta-Automate\'s own daily follow counters, summed',
          ),
        ];

        final tokens = theme.tokens;
        return ListView(
          padding: EdgeInsets.all(tokens.space.lg),
          children: [
            Row(
              children: [
                Text('Whole library', style: theme.textTheme.titleMedium),
                SizedBox(width: tokens.space.sm),
                StatusChip(kind: StatusKind.neutral, label: '${summary.entities} entities', dense: true),
              ],
            ),
            SizedBox(height: tokens.space.xs),
            Text(
              'Every entity with any scan or scrape activity. Each stage shows its share of the '
              'whole library and, more usefully, its real conversion from the stage right before it.',
              style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary),
            ),
            SizedBox(height: tokens.space.xl),
            FunnelChart(stages: stages),
          ],
        );
      },
    );
  }
}

/// Column 0 (Entity) has no `sortKey` — sorting by name has no real use here
/// and `AppTableSort` only ever targets a sortable column via its header tap,
/// so leaving it out is enough to keep it out of the sort rotation.
List<AppTableColumn<EntityRanking>> _rankingColumns() => [
  AppTableColumn<EntityRanking>(
    label: 'Entity',
    cell: (row) => Text(row.root, overflow: TextOverflow.ellipsis, maxLines: 1),
  ),
  AppTableColumn<EntityRanking>(label: 'Type', width: 90, cell: (row) => Text(row.type)),
  AppTableColumn<EntityRanking>(label: 'Access', width: 90, cell: (row) => Text(row.access)),
  // Wide enough for the longest header label ("Scanned") plus its sort arrow
  // once active, not just the numbers themselves — a real overflow caught by
  // `insights_layout_test.dart`'s huge-counts case, not by inspection.
  AppTableColumn<EntityRanking>.numeric(label: 'Scanned', value: (row) => row.scanned, width: 120, sortable: true),
  AppTableColumn<EntityRanking>.numeric(label: 'Private', value: (row) => row.private, width: 120, sortable: true),
  AppTableColumn<EntityRanking>.numeric(label: 'Female', value: (row) => row.female, width: 120, sortable: true),
];

class RankingTab extends ConsumerStatefulWidget {
  const RankingTab({super.key});

  @override
  ConsumerState<RankingTab> createState() => RankingTabState();
}

class RankingTabState extends ConsumerState<RankingTab> {
  String _query = '';
  AppTableSort _sort = const AppTableSort(columnIndex: 3, ascending: false);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(entityRankingProvider);
    final columns = _rankingColumns();

    return async.stateView(
      describeError: describeInsightsError,
      onRetry: () => ref.invalidate(entityRankingProvider),
      data: (rows) {
        final filtered = _query.isEmpty
            ? rows
            : rows.where((r) => r.root.toLowerCase().contains(_query.toLowerCase())).toList();
        final sortKey = columns[_sort.columnIndex].sortKey;
        var sorted = filtered;
        if (sortKey != null) {
          sorted = [...sorted]..sort((a, b) => sortKey(a).compareTo(sortKey(b)));
          if (!_sort.ascending) sorted = sorted.reversed.toList();
        }

        if (rows.isEmpty) {
          return const EmptyView(
            icon: Icons.insights_outlined,
            title: 'No entity has any scan or scrape activity yet.',
          );
        }

        final tokens = theme.tokens;
        final searchRow = Row(
          children: [
            SizedBox(
              width: 280,
              child: TextField(
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: AppIcon(AppIcons.search, size: IconSize.sm),
                  hintText: 'Filter by root…',
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            SizedBox(width: tokens.space.md),
            NumericText('${sorted.length} of ${rows.length}', role: TextRole.caption, color: tokens.content.secondary),
          ],
        );

        // One scrollable for the whole tab (search row + table), same as
        // before — the table itself no longer needs its own horizontal
        // scroller since every column now genuinely fits any width the
        // window can produce (D77): Entity absorbs whatever space is left
        // over, the rest stay fixed.
        return ListView(
          padding: EdgeInsets.all(tokens.space.lg),
          children: [
            searchRow,
            SizedBox(height: tokens.space.md),
            AppTable<EntityRanking>(
              columns: columns,
              rows: sorted,
              sort: _sort,
              onSort: (sort) => setState(() => _sort = sort),
              onRowTap: (row) => showEntityYieldDialog(context, row.root),
            ),
          ],
        );
      },
    );
  }
}

const _dayOptions = [7, 14, 30, 90];

class BurndownTab extends ConsumerWidget {
  const BurndownTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selectedDays = ref.watch(burndownDaysProvider);
    final async = ref.watch(burndownProvider);
    final liveFlows = ref.watch(flowsControllerProvider).value?.flows;

    final tokens = theme.tokens;
    return ListView(
      padding: EdgeInsets.all(tokens.space.lg),
      children: [
        // "Am I near a cap" answered before reading five charts — the same
        // live-preferring `CapsTile` the Overview bento tile uses (V2.7),
        // reused rather than rebuilt.
        async.stateView(
          describeError: describeInsightsError,
          onRetry: () => ref.invalidate(burndownProvider),
          data: (burndown) => CapsTile(burndown: burndown, liveFlows: liveFlows),
        ),
        SizedBox(height: tokens.space.lg),
        Wrap(
          spacing: tokens.space.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Last', style: theme.textTheme.bodyMedium),
            for (final option in _dayOptions)
              ChoiceChip(
                label: Text('${option}d'),
                selected: selectedDays == option,
                onSelected: (_) => ref.read(burndownDaysProvider.notifier).select(option),
              ),
          ],
        ),
        SizedBox(height: tokens.space.lg),
        async.stateView(
          describeError: describeInsightsError,
          onRetry: () => ref.invalidate(burndownProvider),
          data: (burndown) => Wrap(
            spacing: tokens.space.lg,
            runSpacing: tokens.space.lg,
            children: [
              _burndownCard(context, 'Scan — profiles', burndown.scan, 'profiles', burndown.limits['profiles']),
              _burndownCard(context, 'Scan — reels', burndown.scan, 'reels', burndown.limits['reels']),
              _burndownCard(context, 'Scan — posts', burndown.scan, 'posts', burndown.limits['posts']),
              _burndownCard(context, 'Scrape', burndown.scrape, 'scraped', burndown.limits['scrape']),
              _burndownCard(context, 'Follow', burndown.follow, 'followed', burndown.limits['follow']),
            ],
          ),
        ),
      ],
    );
  }

  Widget _burndownCard(BuildContext context, String title, List<BurndownDay> days, String field, int? cap) {
    return SizedBox(
      width: 420,
      child: BurndownCard(title: title, days: days, values: field, cap: cap),
    );
  }
}
