// COMPONENTS.md §0 / SCREENS.md §8 — one entry in the command palette. Every
// item reuses an existing action path (a controller method, a confirm
// dialog, a nav-index write) — this type only ever describes *what to show*
// and *what to call*, never a second implementation of the action itself.
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// SCREENS.md §8's own group order — fixed regardless of match order, so
/// results never visually reshuffle group-to-group while the user types.
const commandGroupOrder = ['Go to', 'Flows', 'Library', 'Services', 'Ops', 'Appearance', 'Settings', 'Help'];

class CommandItem {
  const CommandItem({
    required this.id,
    required this.group,
    required this.label,
    this.subtitle,
    this.badge,
    this.icon,
    this.keywords = const [],
    required this.onSelect,
  });

  /// Stable across rebuilds — the recents list persists these, and a matcher
  /// test resolves items by id rather than by (fragile) label text.
  final String id;

  final String group;
  final String label;
  final String? subtitle;

  /// A short trailing marker — a live count, "running", a current value —
  /// never load-bearing on its own (SCREENS.md §8's mockup: "191", "running").
  final String? badge;
  final PhosphorIconData Function(PhosphorIconsStyle)? icon;

  /// Extra subsequence-matchable text beyond the label (e.g. a flow's wire
  /// name alongside its title) — never shown, only searched.
  final List<String> keywords;

  final void Function() onSelect;
}
