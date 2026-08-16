import 'package:flutter_test/flutter_test.dart';

import 'package:ia_control_center/core/insights_models.dart';
import 'package:ia_control_center/core/scheduler_models.dart';
import 'package:ia_control_center/features/overview/caps_tile.dart';

import 'ui/test_harness.dart';

/// V2.13.3/D121 — Overview's caps tile could sit open across a day rollover
/// showing yesterday's real total as if it were today's. The scheduler
/// heartbeat is fine (`Insta-Automate`'s `Scrape.fetch()`/etc. always query
/// by the current date), but a heartbeat that's stopped arriving at all
/// (a disconnected device blocks `serve()` before `heartbeat_loop()` ever
/// starts) leaves `flowsControllerProvider`'s snapshot frozen, and the
/// once-per-session `burndown` fallback has no wall-clock awareness of its
/// own. These tests exercise `CapsTile` directly, isolated from the rest of
/// `OverviewPage`, against both failure shapes.
String _isoToday() {
  final now = DateTime.now();
  String pad2(int n) => n.toString().padLeft(2, '0');
  return '${now.year}-${pad2(now.month)}-${pad2(now.day)}';
}

Burndown _burndownEndingOn(String lastDate, {int value = 5}) => Burndown(
  days: 1,
  limits: const {'profiles': 10, 'reels': 30, 'posts': 30, 'scrape': 300, 'follow': 60},
  scan: [BurndownDay(date: lastDate, values: {'profiles': value, 'reels': value, 'posts': value})],
  scrape: [BurndownDay(date: lastDate, values: {'scraped': value})],
  follow: [BurndownDay(date: lastDate, values: {'followed': value})],
);

void main() {
  testWidgets('shows the burndown total when its last day is genuinely today, with no live data', (tester) async {
    await pumpUi(tester, CapsTile(burndown: _burndownEndingOn(_isoToday(), value: 7)));
    expect(find.text('7/300'), findsOneWidget);
  });

  testWidgets('falls back to 0, not a stale day total, once the burndown snapshot predates today', (tester) async {
    // A fixed, deliberately-ancient date — never "today" no matter when this
    // test runs. Before the fix, `_CapBar` read `row.days.last.values[...]`
    // unconditionally and would have shown 5/300 here.
    await pumpUi(tester, CapsTile(burndown: _burndownEndingOn('2000-01-01', value: 5)));
    expect(find.text('0/300'), findsOneWidget);
    expect(find.text('5/300'), findsNothing);
  });

  testWidgets('trusts a live heartbeat figure over the burndown snapshot regardless of date', (tester) async {
    await pumpUi(
      tester,
      CapsTile(
        burndown: _burndownEndingOn('2000-01-01', value: 5),
        liveFlows: const {
          'entity-scrape': FlowState(
            flow: 'entity-scrape',
            switchOn: true,
            phase: 'waiting',
            nextTriggerAt: null,
            gate: FlowGate(ok: true),
            today: {'scraped': 42},
            lastRun: null,
          ),
        },
      ),
    );
    expect(find.text('42/300'), findsOneWidget);
  });
}
