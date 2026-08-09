// SCREENS.md §8's own source table — every group built from a provider that
// already exists, every action a call into an existing controller/dialog.
// Built fresh (cheaply — every read below is a cached `.value`, never a
// network call) on each `CommandPalette` rebuild, so counts/labels stay live
// while the palette is open and the query changes.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/flow_switch_confirm.dart';
import '../../core/force_run.dart';
import '../../core/library_models.dart';
import '../../core/nav_state.dart';
import '../../core/ops_actions.dart';
import '../../core/ops_models.dart';
import '../../core/onboarding.dart';
import '../../core/scheduler_models.dart';
import '../../core/service_actions.dart';
import '../../core/service_models.dart';
import '../../core/settings_nav.dart';
import '../../core/shortcuts_reference.dart';
import '../../core/theme/density.dart';
import '../../core/theme/registry.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/theme/tokens.dart';
import '../../features/flows/flows_controller.dart';
import '../../features/library/library_controller.dart';
import '../../features/library/review_page.dart';
import '../../features/live/live_controller.dart';
import '../../features/overview/curation_tile.dart' show curationFolders;
import '../../features/services/services_controller.dart';
import '../../features/settings/config_controller.dart';
import '../../features/settings/ops_controller.dart';
import '../icons.dart';
import 'command_item.dart';

const _destinations = [
  (overviewIndex, 'Overview', AppIcons.overview),
  (flowsIndex, 'Flows', AppIcons.flow),
  (liveIndex, 'Live', AppIcons.sensor),
  (servicesIndex, 'Services', AppIcons.service),
  (libraryIndex, 'Library', AppIcons.library),
  (insightsIndex, 'Insights', AppIcons.insight),
  (settingsIndex, 'Settings', AppIcons.settings),
];

const _settingsTabs = [
  (settingsFlowsTabIndex, 'Flows'),
  (settingsLimitsTabIndex, 'Limits'),
  (settingsQueueTabIndex, 'Queue'),
  (settingsDevicesTabIndex, 'Devices'),
  (settingsAppearanceTabIndex, 'Appearance'),
  (settingsOpsTabIndex, 'Ops'),
];

const _insightsTabs = [
  (insightsFunnelTabIndex, 'Funnel'),
  (insightsRankingTabIndex, 'Ranking'),
  (insightsBurndownTabIndex, 'Daily limits'),
];

String _densityLabel(Density density) => switch (density) {
  Density.compact => 'Compact',
  Density.comfortable => 'Comfortable',
  Density.spacious => 'Spacious',
};

/// [context] must be a stable ancestor context that outlives the palette
/// dialog itself (the title bar's or `AppShell`'s own `build` context, never
/// the dialog route's) — every closure below may run a confirm dialog or a
/// snackbar well after the palette that built it has already popped.
List<CommandItem> buildCommandItems(BuildContext context, WidgetRef ref) {
  final items = <CommandItem>[];

  // ---------------------------------------------------------------- Go to
  for (final (index, label, icon) in _destinations) {
    items.add(
      CommandItem(
        id: 'goto.nav.$index',
        group: 'Go to',
        label: label,
        icon: icon,
        onSelect: () => ref.read(selectedNavIndexProvider.notifier).select(index),
      ),
    );
  }
  for (final (index, label) in _settingsTabs) {
    items.add(
      CommandItem(
        id: 'goto.settings.$index',
        group: 'Go to',
        label: 'Settings › $label',
        icon: AppIcons.settings,
        onSelect: () {
          ref.read(requestedSettingsTabProvider.notifier).select(index);
          ref.read(selectedNavIndexProvider.notifier).select(settingsIndex);
        },
      ),
    );
  }
  for (final (index, label) in _insightsTabs) {
    items.add(
      CommandItem(
        id: 'goto.insights.$index',
        group: 'Go to',
        label: 'Insights › $label',
        icon: AppIcons.insight,
        onSelect: () {
          ref.read(requestedInsightsTabProvider.notifier).select(index);
          ref.read(selectedNavIndexProvider.notifier).select(insightsIndex);
        },
      ),
    );
  }
  for (final flow in flowOrder) {
    items.add(
      CommandItem(
        id: 'goto.live.$flow',
        group: 'Go to',
        label: 'Live · ${flowTitle[flow]}',
        icon: AppIcons.sensor,
        keywords: [flow],
        onSelect: () {
          ref.read(selectedFlowProvider.notifier).select(flow);
          ref.read(selectedNavIndexProvider.notifier).select(liveIndex);
        },
      ),
    );
  }

  // --------------------------------------------------------------- Flows
  final flows = ref.watch(flowsControllerProvider).value?.flows ?? const <String, FlowState>{};
  for (final flow in flowOrder) {
    final state = flows[flow];
    if (state == null) continue;
    final title = flowTitle[flow] ?? flow;

    items.add(
      CommandItem(
        id: 'flow.trigger.$flow',
        group: 'Flows',
        label: 'Trigger now: $title',
        subtitle: state.gate.detail ?? (state.gate.ok ? null : state.gate.reason),
        icon: AppIcons.trigger,
        keywords: [flow],
        onSelect: () => forceRunFlow(context, ref, state),
      ),
    );

    if (state.phase == 'running' && state.lastRun != null) {
      items.add(
        CommandItem(
          id: 'flow.stop.$flow',
          group: 'Flows',
          label: 'Stop: $title',
          badge: 'running',
          icon: AppIcons.stop,
          keywords: [flow],
          onSelect: () => stopFlowRun(context, ref, state),
        ),
      );
    }

    if (flow == 'entity-follow') {
      items.add(
        CommandItem(
          id: 'flow.reduceReserve',
          group: 'Flows',
          label: 'Reduce reserve: $title',
          icon: AppIcons.queue,
          onSelect: () => reduceReserveFlow(context, ref, state),
        ),
      );
    }

    items.add(
      CommandItem(
        id: 'flow.switch.$flow',
        group: 'Flows',
        label: state.switchOn ? 'Turn off: $title' : 'Turn on: $title',
        icon: AppIcons.power,
        keywords: [flow, flowSwitchKey(flow)],
        onSelect: () => toggleFlowSwitch(context, ref, flow, !state.switchOn),
      ),
    );
  }

  // ------------------------------------------------------------- Library
  final folders = ref.watch(libraryFoldersControllerProvider).value ?? const <LibraryFolderInfo>[];
  for (final folder in folders) {
    items.add(
      CommandItem(
        id: 'library.open.${folder.name}',
        group: 'Library',
        label: 'Open folder: ${folder.name}',
        badge: folder.total > 0 ? '${folder.total}' : null,
        icon: AppIcons.folderOpen,
        onSelect: () {
          ref.read(selectedFolderProvider.notifier).select(folder.name);
          ref.read(selectedEntityProvider.notifier).select(null);
          ref.read(selectedNavIndexProvider.notifier).select(libraryIndex);
        },
      ),
    );
  }
  for (final folder in curationFolders) {
    final info = folders.where((f) => f.name == folder).firstOrNull;
    items.add(
      CommandItem(
        id: 'library.review.$folder',
        group: 'Library',
        label: 'Review: $folder',
        badge: info != null && info.total > 0 ? '${info.total}' : null,
        icon: AppIcons.review,
        onSelect: () => openReviewModeForFolder(context, ref, folder),
      ),
    );
  }
  // Per-entity jump is scoped to whichever non-flat folder is already
  // loaded (`libraryEntitiesControllerProvider` is folder-scoped, not a
  // whole-library index) — real, but bounded to what's already on screen or
  // was last browsed, not an eager fetch across all seven folders.
  final currentFolder = ref.watch(selectedFolderProvider);
  if (currentFolder != null) {
    final entities = ref.watch(libraryEntitiesControllerProvider).value ?? const <LibraryEntityInfo>[];
    for (final entity in entities.take(50)) {
      items.add(
        CommandItem(
          id: 'library.entity.$currentFolder.${entity.root}',
          group: 'Library',
          label: 'Open ${entity.root} ($currentFolder)',
          badge: '${entity.count}',
          icon: AppIcons.entity,
          onSelect: () {
            ref.read(selectedFolderProvider.notifier).select(currentFolder);
            ref.read(selectedEntityProvider.notifier).select(entity.root);
            ref.read(selectedNavIndexProvider.notifier).select(libraryIndex);
          },
        ),
      );
    }
  }

  // ------------------------------------------------------------ Services
  final services = ref.watch(servicesControllerProvider).value ?? const <ServiceStatus>[];
  for (final status in services) {
    void gotoService() {
      ref.read(selectedServiceProvider.notifier).select(status.name);
      ref.read(selectedNavIndexProvider.notifier).select(servicesIndex);
    }

    if (status.canTakeover) {
      items.add(
        CommandItem(
          id: 'service.takeover.${status.name}',
          group: 'Services',
          label: 'Take over: ${status.label}',
          icon: AppIcons.service,
          onSelect: () {
            gotoService();
            takeoverService(context, ref, status);
          },
        ),
      );
    } else if (status.isRunning) {
      items.add(
        CommandItem(
          id: 'service.restart.${status.name}',
          group: 'Services',
          label: 'Restart: ${status.label}',
          icon: AppIcons.service,
          onSelect: () {
            gotoService();
            restartService(context, ref, status);
          },
        ),
      );
    } else {
      items.add(
        CommandItem(
          id: 'service.start.${status.name}',
          group: 'Services',
          label: 'Start: ${status.label}',
          icon: AppIcons.service,
          onSelect: () {
            gotoService();
            startService(context, ref, status);
          },
        ),
      );
    }

    if (status.canStop) {
      items.add(
        CommandItem(
          id: 'service.stop.${status.name}',
          group: 'Services',
          label: 'Stop: ${status.label}',
          icon: AppIcons.stop,
          onSelect: () {
            gotoService();
            stopService(context, ref, status);
          },
        ),
      );
    }

    if (status.hasTest && status.isRunning) {
      items.add(
        CommandItem(
          id: 'service.test.${status.name}',
          group: 'Services',
          label: 'Test: ${status.label}',
          icon: AppIcons.science,
          onSelect: () {
            gotoService();
            testService(context, ref, status);
          },
        ),
      );
    }
  }

  // ----------------------------------------------------------------- Ops
  final opsSpecs = ref.watch(opsSpecsProvider).value ?? const <OpsJobSpec>[];
  for (final spec in opsSpecs) {
    items.add(
      CommandItem(
        id: 'ops.${spec.id}',
        group: 'Ops',
        label: spec.label,
        subtitle: spec.description,
        icon: AppIcons.job,
        onSelect: () {
          ref.read(requestedSettingsTabProvider.notifier).select(settingsOpsTabIndex);
          ref.read(selectedNavIndexProvider.notifier).select(settingsIndex);
          runOpsJob(context, ref, spec);
        },
      ),
    );
  }

  // ----------------------------------------------------------- Appearance
  final themePrefs = ref.watch(themeControllerProvider);
  for (final id in ThemeId.values) {
    final tokens = buildTokensFor(id);
    items.add(
      CommandItem(
        id: 'appearance.theme.${id.name}',
        group: 'Appearance',
        label: '${tokens.name} theme',
        badge: themePrefs.themeId == id ? 'current' : null,
        icon: AppIcons.appearance,
        onSelect: () => ref.read(themeControllerProvider.notifier).setTheme(id),
      ),
    );
  }
  for (final density in Density.values) {
    items.add(
      CommandItem(
        id: 'appearance.density.${density.name}',
        group: 'Appearance',
        label: 'Density: ${_densityLabel(density)}',
        badge: themePrefs.density == density ? 'current' : null,
        icon: AppIcons.appearance,
        onSelect: () => ref.read(themeControllerProvider.notifier).setDensity(density),
      ),
    );
  }

  // ------------------------------------------------------------- Settings
  final config = ref.watch(configControllerProvider).value;
  if (config != null) {
    for (final schema in config.schema) {
      if (schema.type != 'int') continue;
      final value = config.values.limits[schema.name];
      items.add(
        CommandItem(
          id: 'settings.limit.${schema.name}',
          group: 'Settings',
          label: schema.name,
          subtitle: schema.help,
          badge: value?.toString(),
          icon: AppIcons.settings,
          onSelect: () {
            ref.read(requestedSettingsTabProvider.notifier).select(settingsLimitsTabIndex);
            ref.read(selectedNavIndexProvider.notifier).select(settingsIndex);
            ref.read(highlightedConfigKeyProvider.notifier).highlight(schema.name);
          },
        ),
      );
    }
  }

  // ---------------------------------------------------------------- Help
  items.add(
    CommandItem(
      id: 'help.shortcuts',
      group: 'Help',
      label: 'Keyboard shortcuts',
      icon: AppIcons.help,
      onSelect: () => showShortcutsReference(context),
    ),
  );
  items.add(
    CommandItem(
      id: 'help.welcome',
      group: 'Help',
      label: 'Welcome guide',
      icon: AppIcons.help,
      onSelect: () => showWelcomeDialog(context),
    ),
  );

  return items;
}
