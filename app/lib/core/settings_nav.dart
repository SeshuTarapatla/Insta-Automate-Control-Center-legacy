// V2.12 — lets the command palette (and anything else) jump straight to a
// specific Settings/Insights tab, and briefly highlight one Limits field,
// without either page needing to expose a `TabController` of its own.
// `DefaultTabController`'s underlying controller is only ever created once
// per mount, so a plain rebuild with a different `initialIndex` does nothing
// — keying it on the requested index (see `settings_page.dart`/
// `insights_page.dart`) forces a fresh one instead.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

// Index-aligned with `settings_page.dart`'s six `AppTab`s and
// `insights_page.dart`'s three, the same way `core/nav_state.dart`'s own
// `overviewIndex..settingsIndex` are aligned with the nav rail.
const settingsFlowsTabIndex = 0;
const settingsLimitsTabIndex = 1;
const settingsQueueTabIndex = 2;
const settingsDevicesTabIndex = 3;
const settingsAppearanceTabIndex = 4;
const settingsOpsTabIndex = 5;

const insightsFunnelTabIndex = 0;
const insightsRankingTabIndex = 1;
const insightsBurndownTabIndex = 2;

class RequestedTabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) => state = index;
}

final requestedSettingsTabProvider = NotifierProvider<RequestedTabNotifier, int>(RequestedTabNotifier.new);
final requestedInsightsTabProvider = NotifierProvider<RequestedTabNotifier, int>(RequestedTabNotifier.new);

/// The Limits tab's per-field flash, set by a "Settings" palette result and
/// self-clearing — a generation counter (not just a null-after-delay timer)
/// so an older highlight's delayed clear can never stomp a newer one.
class HighlightedConfigKeyNotifier extends Notifier<String?> {
  static const _flashDuration = Duration(milliseconds: 2200);
  int _generation = 0;

  @override
  String? build() => null;

  void highlight(String key) {
    final generation = ++_generation;
    state = key;
    Timer(_flashDuration, () {
      if (_generation == generation) state = null;
    });
  }
}

final highlightedConfigKeyProvider = NotifierProvider<HighlightedConfigKeyNotifier, String?>(
  HighlightedConfigKeyNotifier.new,
);
