import 'package:flutter/material.dart';

import 'global_shortcuts.dart';
import 'theme/tokens.dart';

/// Every keyboard binding in the app. Global-scope rows (V2.12) are
/// generated from `global_shortcuts.dart` — the same list `shell/
/// app_shell.dart`'s `CallbackShortcuts` wires up — so those specifically
/// can no longer drift the way this file's pre-V2.12 comment had to warn
/// about by hand. What's left hand-listed below is physically elsewhere and
/// honestly can't be generated the same way: `Ctrl+Alt+I` is a real OS-level
/// `hotkey_manager` registration (`shell/hotkey.dart`), not a
/// `CallbackShortcuts` binding, and every Settings/Library row is a
/// page-scoped key handler with no shared registry of its own. Keep those in
/// step with `settings/config_file_bar.dart` (Ctrl+E),
/// `settings/devices_tab.dart` (Ctrl+F/Esc) and `library/library_grid.dart`
/// (the rest).
class ShortcutEntry {
  const ShortcutEntry({required this.keys, required this.description, required this.scope});

  final String keys;
  final String description;
  final String scope;
}

final shortcutReference = [
  const ShortcutEntry(keys: 'Ctrl+Alt+I', description: 'Show or hide the window', scope: 'Global'),
  for (final s in globalShortcuts) ShortcutEntry(keys: s.keys, description: s.description, scope: 'Global'),
  const ShortcutEntry(keys: 'Ctrl+E', description: 'Open config.env for editing', scope: 'Settings'),
  const ShortcutEntry(keys: 'Ctrl+F', description: 'Search paired devices', scope: 'Settings › Devices'),
  const ShortcutEntry(keys: 'Esc', description: 'Close device search', scope: 'Settings › Devices'),
  const ShortcutEntry(keys: 'Click / Space', description: 'Toggle the focused image', scope: 'Library'),
  const ShortcutEntry(keys: 'Arrow keys', description: 'Move focus by one image or row', scope: 'Library'),
  const ShortcutEntry(
    keys: 'Shift + click / arrow',
    description: 'Extend the selection to here',
    scope: 'Library',
  ),
  const ShortcutEntry(keys: 'Ctrl+A', description: 'Select every image in this folder', scope: 'Library'),
  const ShortcutEntry(keys: 'Delete', description: 'Delete the current selection', scope: 'Library'),
];

Future<void> showShortcutsReference(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final tokens = theme.tokens;
      final byScope = <String, List<ShortcutEntry>>{};
      for (final entry in shortcutReference) {
        byScope.putIfAbsent(entry.scope, () => []).add(entry);
      }

      return AlertDialog(
        title: const Text('Keyboard shortcuts'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final scope in byScope.keys) ...[
                  Padding(
                    padding: EdgeInsets.only(top: tokens.space.md, bottom: tokens.space.xs),
                    child: Text(
                      scope,
                      style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary),
                    ),
                  ),
                  for (final entry in byScope[scope]!)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: tokens.space.xs / 2),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 150,
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: tokens.space.xs, vertical: tokens.space.xs / 1.3),
                              decoration: BoxDecoration(
                                color: tokens.surface.raised,
                                borderRadius: BorderRadius.circular(tokens.geometry.radiusSm),
                                border: Border.all(color: tokens.surface.border),
                              ),
                              child: Text(
                                entry.keys,
                                style: theme.textTheme.bodySmall?.copyWith(fontFamily: tokens.typography.mono),
                              ),
                            ),
                          ),
                          SizedBox(width: tokens.space.md),
                          Expanded(child: Text(entry.description, style: theme.textTheme.bodySmall)),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
      );
    },
  );
}
