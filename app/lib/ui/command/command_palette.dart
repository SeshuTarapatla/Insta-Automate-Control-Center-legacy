// SCREENS.md §8 — `Ctrl+K` from anywhere. A new front door to existing
// actions, never a second implementation of one (COMPONENTS.md §0's own
// rule for this directory).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../icons.dart';
import '../layout.dart';
import '../status.dart';
import '../surfaces.dart';
import 'command_item.dart';
import 'command_matcher.dart';
import 'command_recents.dart';
import 'command_registry.dart';

/// [anchorContext] must outlive the palette dialog itself — the title bar's
/// or `AppShell`'s own stable `build` context, never a context scoped to
/// whatever page happens to be showing (that page can be navigated away from
/// as a direct result of the very command being invoked).
Future<void> showCommandPalette(BuildContext anchorContext) {
  return showDialog<void>(
    context: anchorContext,
    barrierColor: Theme.of(anchorContext).tokens.surface.scrim,
    builder: (_) => CommandPalette(anchorContext: anchorContext),
  );
}

class CommandPalette extends ConsumerStatefulWidget {
  const CommandPalette({super.key, required this.anchorContext});

  final BuildContext anchorContext;

  @override
  ConsumerState<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends ConsumerState<CommandPalette> {
  final _textController = TextEditingController();
  String _query = '';
  int _highlighted = 0;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _setQuery(String value) {
    setState(() {
      _query = value;
      _highlighted = 0;
    });
  }

  void _move(int delta, int count) {
    if (count == 0) return;
    setState(() => _highlighted = (_highlighted + delta).clamp(0, count - 1));
  }

  void _activate(CommandItem item) {
    Navigator.of(context).pop();
    ref.read(recentCommandsProvider.notifier).recordUse(item.id);
    // Fires against `widget.anchorContext`, which stays mounted across
    // whatever nav-index/tab-index writes the action itself makes — the
    // dialog's own `context` above is only ever used to pop the palette.
    item.onSelect();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).tokens;
    if (!widget.anchorContext.mounted) return const SizedBox.shrink();

    final allItems = buildCommandItems(widget.anchorContext, ref);
    final recents = ref.watch(recentCommandsProvider);
    final trimmed = _query.trim();

    final flat = <CommandItem>[];
    final displayGroup = <String>[];
    if (trimmed.isEmpty && recents.isNotEmpty) {
      final byId = {for (final item in allItems) item.id: item};
      final recentItems = [for (final id in recents) ?byId[id]];
      final recentIds = recentItems.map((i) => i.id).toSet();
      for (final item in recentItems) {
        flat.add(item);
        displayGroup.add('Recent');
      }
      for (final item in filterCommands(allItems, '')) {
        if (recentIds.contains(item.id)) continue;
        flat.add(item);
        displayGroup.add(item.group);
      }
    } else {
      for (final item in filterCommands(allItems, _query)) {
        flat.add(item);
        displayGroup.add(item.group);
      }
    }

    final highlighted = flat.isEmpty ? 0 : _highlighted.clamp(0, flat.length - 1);

    // One key per row, rebuilt fresh every frame but only ever read back
    // within this same build's own post-frame callback below — arrow-key
    // navigation moves the highlight by exactly one row at a time, so the
    // newly-highlighted row is always adjacent to what was already on
    // screen, never a jump `ensureVisible` could fail to resolve.
    final rowKeys = List.generate(flat.length, (_) => GlobalKey());

    final rows = <Widget>[];
    var lastGroup = '';
    for (var i = 0; i < flat.length; i++) {
      if (displayGroup[i] != lastGroup) {
        lastGroup = displayGroup[i];
        rows.add(_GroupHeader(label: lastGroup));
      }
      rows.add(
        _CommandRow(
          key: rowKeys[i],
          item: flat[i],
          highlighted: i == highlighted,
          onTap: () => _activate(flat[i]),
        ),
      );
    }

    if (flat.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final rowContext = rowKeys[highlighted].currentContext;
        if (rowContext != null) {
          Scrollable.ensureVisible(rowContext, duration: const Duration(milliseconds: 100));
        }
      });
    }

    return Align(
      alignment: const Alignment(0, -0.55),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1, flat.length),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1, flat.length),
          const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop(),
          const SingleActivator(LogicalKeyboardKey.enter): () {
            if (flat.isNotEmpty) _activate(flat[highlighted]);
          },
        },
        child: Material(
          type: MaterialType.transparency,
          child: AppOverlay(
            padding: EdgeInsets.zero,
            child: SizedBox(
              width: 640,
              height: 480,
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.all(tokens.space.md),
                    child: TextField(
                      controller: _textController,
                      autofocus: true,
                      onChanged: _setQuery,
                      onSubmitted: (_) {
                        if (flat.isNotEmpty) _activate(flat[highlighted]);
                      },
                      style: Theme.of(context).textTheme.bodyLarge,
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: 'Search flows, folders, jobs, themes, config keys…',
                        prefixIcon: AppIcon(AppIcons.search, size: IconSize.md),
                      ),
                    ),
                  ),
                  const AppDivider(),
                  Expanded(
                    child: flat.isEmpty
                        ? Center(
                            child: Text(
                              'No matching commands',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: tokens.content.secondary),
                            ),
                          )
                        : SingleChildScrollView(
                            padding: EdgeInsets.symmetric(vertical: tokens.space.xs),
                            child: Column(children: rows),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    return Padding(
      padding: EdgeInsets.fromLTRB(tokens.space.md, tokens.space.sm, tokens.space.md, tokens.space.xs / 2),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(color: tokens.content.tertiary, letterSpacing: 0.6),
      ),
    );
  }
}

class _CommandRow extends StatelessWidget {
  const _CommandRow({super.key, required this.item, required this.highlighted, required this.onTap});

  final CommandItem item;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: tokens.space.sm, vertical: tokens.space.xs / 2),
      child: AppPanel(
        padding: EdgeInsets.symmetric(horizontal: tokens.space.sm, vertical: tokens.space.sm),
        selected: highlighted,
        interactive: true,
        onTap: onTap,
        child: Row(
          children: [
            if (item.icon != null) ...[
              AppIcon(item.icon!, size: IconSize.sm, color: tokens.content.secondary),
              SizedBox(width: tokens.space.sm),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                  if (item.subtitle != null)
                    Text(
                      item.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary),
                    ),
                ],
              ),
            ),
            if (item.badge != null) ...[
              SizedBox(width: tokens.space.sm),
              StatusChip(kind: StatusKind.neutral, label: item.badge!, dense: true),
            ],
          ],
        ),
      ),
    );
  }
}
