// SCREENS.md §8 — "recents first." Persisted the same way
// `LibraryZoomNotifier`/`ThemeController` are: a synchronous empty default so
// the palette never flashes wrong content, the real saved list loading a
// moment later.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecentCommandsNotifier extends Notifier<List<String>> {
  static const _prefsKey = 'command_palette_recents';
  static const _max = 8;

  @override
  List<String> build() {
    _load();
    return const [];
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_prefsKey);
    if (saved != null) state = saved;
  }

  Future<void> recordUse(String id) async {
    state = [id, ...state.where((existing) => existing != id)].take(_max).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, state);
  }
}

final recentCommandsProvider = NotifierProvider<RecentCommandsNotifier, List<String>>(RecentCommandsNotifier.new);
