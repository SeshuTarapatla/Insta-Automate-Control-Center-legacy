import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ia_control_center/core/config_models.dart';
import 'package:ia_control_center/core/library_models.dart';
import 'package:ia_control_center/core/nav_state.dart';
import 'package:ia_control_center/core/ops_models.dart';
import 'package:ia_control_center/core/scheduler_models.dart';
import 'package:ia_control_center/core/service_models.dart';
import 'package:ia_control_center/core/theme/theme_controller.dart';
import 'package:ia_control_center/features/flows/flows_controller.dart';
import 'package:ia_control_center/features/library/library_controller.dart';
import 'package:ia_control_center/features/services/services_controller.dart';
import 'package:ia_control_center/features/settings/config_controller.dart';
import 'package:ia_control_center/features/settings/ops_controller.dart';
import 'package:ia_control_center/ui/command/command_item.dart';
import 'package:ia_control_center/ui/command/command_matcher.dart';
import 'package:ia_control_center/ui/command/command_palette.dart';
import 'package:ia_control_center/ui/command/command_recents.dart';
import 'package:ia_control_center/ui/command/command_registry.dart';

// ------------------------------------------------------------- fakes
// Same "override `build()`, skip the real network/native round trip"
// precedent every other layout test's fakes use (`flows_layout_test.dart`'s
// `_FakeFlowsController` etc.) — none of these ever touch a real `dio` call
// or the real `flutter_acrylic` native effect `ThemeController.setTheme`
// would otherwise trigger.
class _FakeFlowsController extends FlowsController {
  @override
  Future<SchedulerSnapshot> build() async => SchedulerSnapshot(
    online: true,
    lastHeartbeatAt: 0,
    flows: {
      'entity-scrape': FlowState(
        flow: 'entity-scrape',
        switchOn: true,
        phase: 'idle',
        nextTriggerAt: null,
        gate: const FlowGate(ok: true),
        today: null,
        lastRun: null,
      ),
    },
  );
}

class _FakeFoldersController extends LibraryFoldersController {
  @override
  Future<List<LibraryFolderInfo>> build() async => const [
    LibraryFolderInfo(name: 'gender_valid', flat: true, total: 1204, entities: 3),
    LibraryFolderInfo(name: 'scraped', flat: true, total: 191, entities: 2),
  ];
}

ServiceStatus _adb() => ServiceStatus(
  name: 'adb',
  label: 'ADB',
  description: 'adb server',
  state: ServiceState.running,
  origin: ServiceOrigin.supervised,
  pid: 1,
  uptimeS: 10,
  restartCount: 0,
  exitCode: null,
  error: null,
  probe: null,
  hasTest: false,
  lastTest: null,
  selfHeal: true,
  autostart: true,
  terminalAvailable: true,
  canTakeover: false,
  external: null,
  portOwner: null,
  cmd: const [],
  port: 5037,
  logSeq: 0,
  receivedAt: DateTime(2026, 1, 1),
);

class _FakeServicesController extends ServicesController {
  @override
  Future<List<ServiceStatus>> build() async => [_adb()];
}

class _FakeConfigController extends ConfigController {
  @override
  Future<ConfigResponse> build() async => const ConfigResponse(
    path: 'config.env',
    values: ConfigValues(switches: {}, entityQueue: [], limits: {'SCRAPE_LIMIT': 300}),
    schema: [
      ConfigKeySchema(name: 'SCRAPE_LIMIT', group: 'scrape', type: 'int', defaultValue: 300, help: 'Daily scrape cap'),
    ],
    provenance: {},
  );
}

/// Skips `ThemeController.build()`'s real `_load()` — which unconditionally
/// calls the native `flutter_acrylic` window effect — since nothing here
/// needs a real theme, only a stable one the registry can read.
class _FakeThemeController extends ThemeController {
  @override
  ThemePrefs build() => ThemePrefs.initial;
}

final _overrides = [
  flowsControllerProvider.overrideWith(_FakeFlowsController.new),
  libraryFoldersControllerProvider.overrideWith(_FakeFoldersController.new),
  servicesControllerProvider.overrideWith(_FakeServicesController.new),
  configControllerProvider.overrideWith(_FakeConfigController.new),
  themeControllerProvider.overrideWith(_FakeThemeController.new),
  opsSpecsProvider.overrideWith(
    (ref) async => const [
      OpsJobSpec(id: 'reset_pool', label: 'Reset work pool', description: 'Re-registers deployments', confirm: false, consequence: null),
    ],
  ),
];

/// Pumps the real palette behind a button, using the button's own context as
/// the stable `anchorContext` — exactly how `title_bar.dart`/`app_shell.dart`
/// call `showCommandPalette` for real. Returns the container so a test can
/// read provider state after an action closes the dialog.
Future<ProviderContainer> _pumpPaletteHost(WidgetTester tester) async {
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides,
      child: Consumer(
        builder: (context, ref, _) {
          container = ProviderScope.containerOf(context);
          return MaterialApp(
            theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
            home: Scaffold(
              body: Builder(
                builder: (innerContext) =>
                    ElevatedButton(onPressed: () => showCommandPalette(innerContext), child: const Text('open')),
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('filterCommands — matcher', () {
    CommandItem item(String id, String group, String label) =>
        CommandItem(id: id, group: group, label: label, onSelect: () {});

    test('a subsequence match survives even when not contiguous', () {
      final items = [item('a', 'Flows', 'Trigger now: Scrape')];
      expect(filterCommands(items, 'scr'), hasLength(1));
      expect(filterCommands(items, 'trgnwscr'), hasLength(1));
    });

    test('a query whose letters are not all present matches nothing', () {
      final items = [item('a', 'Flows', 'Trigger now: Scrape')];
      expect(filterCommands(items, 'zzz'), isEmpty);
    });

    test('a prefix match outranks a later subsequence match in the same group', () {
      final items = [item('a', 'Flows', 'Trigger now: Scrape'), item('b', 'Flows', 'Scrape')];
      final result = filterCommands(items, 'scrape');
      expect(result.map((i) => i.id), ['b', 'a']);
    });

    test('group order always follows commandGroupOrder, not input or match order', () {
      final items = [item('help', 'Help', 'Keyboard shortcuts'), item('goto', 'Go to', 'Overview'), item('flow', 'Flows', 'Trigger now: Scrape')];
      final result = filterCommands(items, '');
      expect(result.map((i) => i.id), ['goto', 'flow', 'help']);
    });

    test('an empty query returns every item, ties broken by registry order', () {
      final items = [item('a', 'Flows', 'Alpha'), item('b', 'Flows', 'Bravo'), item('c', 'Flows', 'Charlie')];
      expect(filterCommands(items, '').map((i) => i.id), ['a', 'b', 'c']);
    });

    test('groupCommands buckets by group in commandGroupOrder, dropping empty groups', () {
      final items = [item('a', 'Flows', 'Alpha'), item('b', 'Help', 'Beta')];
      final grouped = groupCommands(items);
      expect(grouped.map((e) => e.key), ['Flows', 'Help']);
    });
  });

  group('buildCommandItems — registry content', () {
    Future<List<CommandItem>> pump(WidgetTester tester) async {
      late List<CommandItem> items;
      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides,
          child: Consumer(
            builder: (context, ref, _) {
              items = buildCommandItems(context, ref);
              return const MaterialApp(home: SizedBox());
            },
          ),
        ),
      );
      // The fake controllers above are still `AsyncNotifier`s — genuinely
      // async, even with no real `dio` call inside — so their first
      // `.value` is null until this settles, same as every real screen.
      await tester.pumpAndSettle();
      return items;
    }

    testWidgets('every group is populated from its real provider, gated exactly like the source screen', (tester) async {
      final items = await pump(tester);
      final byLabel = {for (final item in items) item.label: item};

      // Flows: only entity-scrape is faked, so its trigger exists but
      // entity-follow-only "Reduce reserve" must not appear at all.
      expect(byLabel['Trigger now: Scrape'], isNotNull);
      expect(byLabel.keys.where((l) => l.startsWith('Reduce reserve')), isEmpty);

      // Library: both folders open, both curation folders reviewable, real
      // counts riding along as the badge.
      expect(byLabel['Open folder: gender_valid']?.badge, '1204');
      expect(byLabel['Review: gender_valid'], isNotNull);
      expect(byLabel['Review: scraped'], isNotNull);

      // Services: `_adb()` is supervised+running+canStop, no test — gated
      // exactly like `ServiceDetail._actions()`'s own switch.
      expect(byLabel['Restart: ADB'], isNotNull);
      expect(byLabel['Stop: ADB'], isNotNull);
      expect(byLabel.keys.where((l) => l.contains('ADB') && l.startsWith('Start')), isEmpty);
      expect(byLabel.keys.where((l) => l.contains('ADB') && l.startsWith('Test')), isEmpty);

      // Ops, Appearance, Settings, Help.
      expect(byLabel['Reset work pool'], isNotNull);
      expect(byLabel['Classic theme'], isNotNull);
      expect(byLabel['Density: Comfortable'], isNotNull);
      expect(byLabel['SCRAPE_LIMIT']?.badge, '300');
      expect(byLabel['Keyboard shortcuts'], isNotNull);
      expect(byLabel['Welcome guide'], isNotNull);

      // Go to: all seven destinations plus the settings/insights sub-tabs.
      expect(byLabel['Overview'], isNotNull);
      expect(byLabel['Settings › Ops'], isNotNull);
      expect(byLabel['Insights › Funnel'], isNotNull);
      expect(byLabel['Live · Scrape'], isNotNull);
    });
  });

  group('CommandPalette widget', () {
    testWidgets('typing narrows to one match, and activating it resolves to the real action', (tester) async {
      final container = await _pumpPaletteHost(tester);
      expect(find.byType(CommandPalette), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'open folder: gender_valid');
      await tester.pump();
      expect(find.text('Open folder: gender_valid'), findsOneWidget);
      expect(find.text('Open folder: scraped'), findsNothing);

      await tester.tap(find.text('Open folder: gender_valid'));
      await tester.pumpAndSettle();

      // The palette closed and the exact same provider writes
      // `curation_tile.dart`'s own "open in Library" helper makes actually
      // ran — not a second, palette-only implementation of "open a folder."
      expect(find.byType(CommandPalette), findsNothing);
      expect(container.read(selectedFolderProvider), 'gender_valid');
      expect(container.read(selectedNavIndexProvider), libraryIndex);
      expect(container.read(recentCommandsProvider), contains('library.open.gender_valid'));
    });

    testWidgets('ArrowDown/ArrowDown/Enter activates the third Go-to item without ever touching the mouse', (tester) async {
      final container = await _pumpPaletteHost(tester);

      // Registry order for "Go to" with only entity-scrape faked: Overview,
      // Flows, Live, Services, Library, Insights, Settings, then the tab
      // sub-entries — index 2 is Live regardless of any of that tail.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.byType(CommandPalette), findsNothing);
      expect(container.read(selectedNavIndexProvider), liveIndex);
    });

    testWidgets('ArrowDown past the visible rows scrolls the list to follow the highlight', (tester) async {
      await _pumpPaletteHost(tester);
      // Scoped past the search field's own internal (horizontal) Scrollable
      // — the result list's vertical `SingleChildScrollView` is the one that
      // needs to follow the highlight.
      final scrollable = find.descendant(of: find.byType(SingleChildScrollView), matching: find.byType(Scrollable));
      expect(scrollable, findsOneWidget);
      final before = tester.state<ScrollableState>(scrollable).position.pixels;

      // The registry here (~38 items across every group) comfortably
      // outgrows the palette's fixed 480px body — 20 steps guarantees the
      // highlight moves well past whatever was visible on first open.
      for (var i = 0; i < 20; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      }
      await tester.pumpAndSettle();

      // A generous margin, not just "moved at all" — the bug this guards
      // was the highlight silently running off the bottom of a *static*
      // list, so the fix has to move the viewport by roughly a screenful,
      // not by one row's worth of incidental settle.
      expect(tester.state<ScrollableState>(scrollable).position.pixels, greaterThan(before + 200));
    });

    testWidgets('Esc dismisses without invoking anything', (tester) async {
      final container = await _pumpPaletteHost(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(CommandPalette), findsNothing);
      // Nothing was activated, so the nav index is untouched from its
      // `SelectedNavIndexNotifier.build()` default.
      expect(container.read(selectedNavIndexProvider), overviewIndex);
    });
  });
}
