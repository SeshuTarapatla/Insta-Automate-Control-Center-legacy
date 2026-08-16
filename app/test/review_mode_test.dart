import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ia_control_center/core/library_image.dart';
import 'package:ia_control_center/core/library_models.dart';
import 'package:ia_control_center/features/library/library_controller.dart';
import 'package:ia_control_center/features/library/review_page.dart';

/// `review_page.dart`'s own keyboard map (SCREENS.md §5b) and V2.13.2/D121's
/// partial-Apply rules: Apply now runs on whatever's actually been decided
/// (no longer gated on every loaded image being decided, or on `hasMore`
/// being false first — that whole-directory-safety concern belonged to the
/// old `POST /api/library/apply` call, which this Apply no longer makes),
/// and review mode is embedded (`libraryReviewingProvider`), not a pushed
/// route, so Esc/close/Apply toggle that flag instead of popping a
/// Navigator. `FileOpener.openUrl` (the `O` key) is deliberately never
/// exercised here — it shells out to the real OS via win32 `ShellExecute`,
/// same reasoning `library_layout_test.dart` already follows for the tile's
/// own "Open on Instagram" menu item.
final _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

LibraryImageEntry _image(String name, {String folder = 'gender_valid', String entity = 'someone'}) =>
    LibraryImageEntry(name: name, path: '$folder/$entity/$name');

/// Records every mutating call instead of hitting a real agent — `move()`/
/// `delete()`/`loadMore()` are all overridden directly (not just `build()`,
/// unlike `library_layout_test.dart`'s fakes), since this suite's whole point
/// is verifying those calls do or don't happen.
class _RecordingImagesController extends LibraryImagesController {
  _RecordingImagesController(this._initial);
  final LibraryImagesState _initial;

  int loadMoreCalls = 0;
  List<Map<String, String>>? movedPairs;
  List<String>? deletedPaths;

  @override
  Future<LibraryImagesState> build() async => _initial;

  @override
  Future<void> loadMore() async {
    loadMoreCalls++;
    final current = state.value;
    if (current == null || !current.hasMore) return;
    final more = [for (var i = 0; i < 10; i++) _image('more$i.jpg')];
    state = AsyncValue.data(current.copyWith(images: [...current.images, ...more], hasMore: false, loadingMore: false));
  }

  @override
  Future<MoveResult> move(List<Map<String, String>> moves) async {
    movedPairs = moves;
    return MoveResult(moved: moves.map((m) => m['to']!).toList(), alreadySynced: const [], errors: const []);
  }

  @override
  Future<DeleteResult> delete(List<String> paths) async {
    deletedPaths = paths;
    return DeleteResult(deleted: paths, errors: const []);
  }
}

class _FakeMoveTargetsController extends MoveTargetsController {
  _FakeMoveTargetsController(this._targets);
  final Map<String, String> _targets;

  @override
  Future<Map<String, String>> build() async => _targets;
}

class _FakeFoldersController extends LibraryFoldersController {
  _FakeFoldersController(this._folders);
  final List<LibraryFolderInfo> _folders;

  @override
  Future<List<LibraryFolderInfo>> build() async => _folders;
}

/// Mirrors how `library_page.dart` actually swaps review mode in — a plain
/// `libraryReviewingProvider` flag, not a pushed route (V2.13.2/D121), so
/// Esc/close/a successful Apply all just flip that flag rather than popping
/// a Navigator.
Future<_RecordingImagesController> _pump(
  WidgetTester tester, {
  required List<LibraryImageEntry> images,
  required int total,
  bool hasMore = false,
  String folder = 'gender_valid',
  String? entity = 'someone',
  Map<String, String> moveTargets = const {},
  List<LibraryFolderInfo> folders = const [],
}) async {
  final controller = _RecordingImagesController(
    LibraryImagesState(images: images, total: total, hasMore: hasMore, loadingMore: false),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        libraryImagesControllerProvider.overrideWith(() => controller),
        moveTargetsControllerProvider.overrideWith(() => _FakeMoveTargetsController(moveTargets)),
        libraryFoldersControllerProvider.overrideWith(() => _FakeFoldersController(folders)),
        libraryImageBytesProvider.overrideWith((ref, path) async => _tinyPng),
      ],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        home: Consumer(
          builder: (context, ref, _) {
            final reviewing = ref.watch(libraryReviewingProvider);
            if (!reviewing) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => ref.read(libraryReviewingProvider.notifier).start(),
                    child: const Text('open review'),
                  ),
                ),
              );
            }
            return LibraryReviewPage(folder: folder, entity: entity);
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text('open review'));
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
}

void main() {
  testWidgets('Keep/Discard advance and record decisions; Up backs one and un-decides it', (tester) async {
    await _pump(tester, images: [_image('a.jpg'), _image('b.jpg'), _image('c.jpg')], total: 3);

    await _press(tester, LogicalKeyboardKey.arrowRight); // keep a -> position 1
    await _press(tester, LogicalKeyboardKey.arrowLeft); // discard b -> position 2
    await _press(tester, LogicalKeyboardKey.arrowUp); // back to position 1, un-decides b
    // b is undecided again — Space should default it to keep, not flip a
    // decision that no longer exists (it would flip to discard if it read
    // the stale `false` instead of treating a missing key as unset).
    await _press(tester, LogicalKeyboardKey.space); // b -> keep, position stays 1 (no advance)
    await _press(tester, LogicalKeyboardKey.arrowRight); // re-keep b -> position 2
    await _press(tester, LogicalKeyboardKey.arrowRight); // keep c -> position 3 (past the end)

    expect(find.textContaining('All reviewed'), findsOneWidget);
    expect(find.textContaining('3 keep'), findsOneWidget);
  });

  testWidgets('Apply is disabled until something is decided, then runs on just the decided images', (tester) async {
    final images = [for (var i = 0; i < 5; i++) _image('img$i.jpg')];
    // hasMore is deliberately true — V2.13.2 dropped the old "not while more
    // pages remain" rule, since a partial Apply never risks a not-yet-loaded
    // image the way the whole-directory `apply()` endpoint used to.
    final controller = await _pump(tester, images: images, total: 12, hasMore: true);

    final applyButton = find.widgetWithText(FilledButton, 'Apply batch   ⏎');
    expect(tester.widget<FilledButton>(applyButton).onPressed, isNull, reason: 'nothing decided yet');

    await _press(tester, LogicalKeyboardKey.arrowRight); // keep img0
    await _press(tester, LogicalKeyboardKey.arrowLeft); // discard img1

    expect(tester.widget<FilledButton>(applyButton).onPressed, isNotNull, reason: 'two images decided, even with hasMore true');

    await tester.tap(applyButton);
    await tester.pumpAndSettle();
    expect(find.text('Apply decided images?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();

    // Identity target (no move-targets override) — kept stays put, so only
    // the discard actually calls delete(); nothing was moved.
    expect(controller.movedPairs, isNull);
    expect(controller.deletedPaths, ['gender_valid/someone/img1.jpg']);
    // Review mode does not auto-close on Apply anymore — a partial batch is
    // the expected case, not a "finished" signal.
    expect(find.byType(LibraryReviewPage), findsOneWidget);
    expect(find.text('open review'), findsNothing);
  });

  testWidgets('Apply moves kept images when the target differs from the source folder', (tester) async {
    final controller = await _pump(
      tester,
      images: [_image('a.jpg'), _image('b.jpg')],
      total: 2,
      moveTargets: {'gender_valid': 'scrape_queued'},
      folders: [const LibraryFolderInfo(name: 'scrape_queued', flat: false, total: 0, entities: 0)],
    );

    await _press(tester, LogicalKeyboardKey.arrowRight); // keep a
    await _press(tester, LogicalKeyboardKey.arrowLeft); // discard b

    await tester.tap(find.widgetWithText(FilledButton, 'Apply batch   ⏎'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();

    expect(controller.movedPairs, [
      {'from': 'gender_valid/someone/a.jpg', 'to': 'scrape_queued/someone/a.jpg'},
    ]);
    expect(controller.deletedPaths, ['gender_valid/someone/b.jpg']);
  });

  testWidgets('Pagination boundary: loadMore fires once the reader approaches the loaded edge, not before', (
    tester,
  ) async {
    final images = [for (var i = 0; i < 30; i++) _image('img$i.jpg')];
    final controller = await _pump(tester, images: images, total: 40, hasMore: true);

    expect(controller.loadMoreCalls, 0, reason: 'position 0 of 30 is nowhere near the loaded boundary');

    await tester.tap(find.byKey(const ValueKey('review-dot-15')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(controller.loadMoreCalls, 1, reason: 'position 15 of 30 is within the lookahead window');
  });

  testWidgets('Esc exits without writing anything, decisions and all', (tester) async {
    final controller = await _pump(tester, images: [_image('a.jpg'), _image('b.jpg')], total: 2);

    await _press(tester, LogicalKeyboardKey.arrowRight); // decide something, then bail anyway
    await _press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('open review'), findsOneWidget, reason: 'Esc turned libraryReviewingProvider back off');
    expect(controller.movedPairs, isNull, reason: 'nothing is written until Apply — Esc must not call it');
    expect(controller.deletedPaths, isNull);
  });

  testWidgets('Del opens the same confirm dialog every other delete path uses, and Cancel writes nothing', (
    tester,
  ) async {
    final controller = await _pump(tester, images: [_image('a.jpg'), _image('b.jpg')], total: 2);

    await _press(tester, LogicalKeyboardKey.delete);
    await tester.pump();

    expect(find.text('Delete these images?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(controller.deletedPaths, isNull);
  });
}
