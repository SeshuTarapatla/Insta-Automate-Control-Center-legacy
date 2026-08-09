// Fuzzy subsequence matching (SCREENS.md §8: "Fuzzy subsequence matching,
// grouped results, recents first") — every character of the query has to
// appear in order somewhere in the candidate text, not necessarily
// contiguous, so "scr" matches "Trigger now: Scrape" the way the mockup's
// own "scr" example expects.
import 'command_item.dart';

/// Null if [query] isn't a subsequence of [text] (case-insensitive); a lower
/// score for a tighter, earlier match otherwise — an exact prefix match
/// scores best, then earliest-starting, then most-contiguous.
int? _score(String text, String query) {
  if (query.isEmpty) return 0;
  final t = text.toLowerCase();
  final q = query.toLowerCase();

  if (t.startsWith(q)) return 0;

  var qi = 0;
  var matchStart = -1;
  var gaps = 0;
  var lastMatch = -1;
  for (var ti = 0; ti < t.length && qi < q.length; ti++) {
    if (t[ti] == q[qi]) {
      if (matchStart == -1) matchStart = ti;
      if (lastMatch != -1 && ti - lastMatch > 1) gaps += ti - lastMatch - 1;
      lastMatch = ti;
      qi++;
    }
  }
  if (qi < q.length) return null;
  // Later-starting and gappier matches score worse (higher); a bare +1
  // keeps every subsequence match ranked below a prefix match (score 0)
  // regardless of position.
  return 1 + matchStart + gaps;
}

/// The best (lowest) score for [item] against [query] across its label and
/// keywords — a keyword hit still surfaces the item, just never ranks above
/// an equally-good label hit (a flat `+1` keyword penalty).
int? _itemScore(CommandItem item, String query) {
  int? best = _score(item.label, query);
  for (final keyword in item.keywords) {
    final s = _score(keyword, query);
    if (s == null) continue;
    final penalized = s + 1;
    if (best == null || penalized < best) best = penalized;
  }
  return best;
}

/// Filters and orders [items] for [query] — empty query returns everything
/// in registry order (grouped, stable); a real query drops non-matches and
/// ranks by score within each group. Group order always follows
/// [commandGroupOrder], never match strength, so results don't jump around
/// group-to-group as the query changes.
List<CommandItem> filterCommands(List<CommandItem> items, String query) {
  final trimmed = query.trim();
  // The original index rides along as an explicit final tiebreaker — `List.
  // sort` makes no stability guarantee, and an empty query scores every item
  // `0`, which would otherwise leave same-group ties in whatever order the
  // sort happened to leave them rather than registry order.
  final scored = <(CommandItem, int, int)>[];
  for (var i = 0; i < items.length; i++) {
    final score = trimmed.isEmpty ? 0 : _itemScore(items[i], trimmed);
    if (score != null) scored.add((items[i], score, i));
  }

  int groupRank(String group) {
    final index = commandGroupOrder.indexOf(group);
    return index == -1 ? commandGroupOrder.length : index;
  }

  scored.sort((a, b) {
    final groupCompare = groupRank(a.$1.group).compareTo(groupRank(b.$1.group));
    if (groupCompare != 0) return groupCompare;
    final scoreCompare = a.$2.compareTo(b.$2);
    if (scoreCompare != 0) return scoreCompare;
    return a.$3.compareTo(b.$3);
  });

  return [for (final entry in scored) entry.$1];
}

/// Groups an already-ordered (see [filterCommands]) list back into sections
/// for display, preserving arrival order within each group.
List<MapEntry<String, List<CommandItem>>> groupCommands(List<CommandItem> items) {
  final byGroup = <String, List<CommandItem>>{};
  for (final item in items) {
    byGroup.putIfAbsent(item.group, () => []).add(item);
  }
  return [
    for (final group in commandGroupOrder)
      if (byGroup[group] case final list?) MapEntry(group, list),
  ];
}
