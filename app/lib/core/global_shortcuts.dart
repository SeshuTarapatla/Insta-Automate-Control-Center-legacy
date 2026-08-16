// V2.12 — the single source both `shell/app_shell.dart`'s `CallbackShortcuts`
// map and `shortcuts_reference.dart`'s displayed list build from, so the two
// can no longer independently drift the way the file's own pre-V2.12 comment
// had to warn about by hand. Only the bindings that genuinely live in one
// `CallbackShortcuts` map are here — `Ctrl+Alt+I` (a real OS-level
// `hotkey_manager` registration, `shell/hotkey.dart`) and every page-scoped
// binding (`Ctrl+E`, `Ctrl+F`/`Esc` in Settings, the Library key map) are
// physically elsewhere and stay hand-listed in `shortcuts_reference.dart`
// rather than being forced into a shape they don't have.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

enum GlobalShortcutId {
  commandPalette,
  shortcutsReference,
  navOverview,
  navFlows,
  navLive,
  navServices,
  navLibrary,
  navInsights,
  navSettings,
  toggleNavRail,
}

class GlobalShortcut {
  const GlobalShortcut({required this.id, required this.activator, required this.keys, required this.description});

  final GlobalShortcutId id;
  final SingleActivator activator;
  final String keys;
  final String description;
}

const globalShortcuts = [
  GlobalShortcut(
    id: GlobalShortcutId.commandPalette,
    activator: SingleActivator(LogicalKeyboardKey.keyK, control: true),
    keys: 'Ctrl+K',
    description: 'Open the command palette',
  ),
  GlobalShortcut(
    id: GlobalShortcutId.shortcutsReference,
    activator: SingleActivator(LogicalKeyboardKey.slash, shift: true),
    keys: '?',
    description: 'Open this shortcut list',
  ),
  GlobalShortcut(
    id: GlobalShortcutId.navOverview,
    activator: SingleActivator(LogicalKeyboardKey.digit1, control: true),
    keys: 'Ctrl+1',
    description: 'Jump to Overview',
  ),
  GlobalShortcut(
    id: GlobalShortcutId.navFlows,
    activator: SingleActivator(LogicalKeyboardKey.digit2, control: true),
    keys: 'Ctrl+2',
    description: 'Jump to Flows',
  ),
  GlobalShortcut(
    id: GlobalShortcutId.navLive,
    activator: SingleActivator(LogicalKeyboardKey.digit3, control: true),
    keys: 'Ctrl+3',
    description: 'Jump to Live',
  ),
  GlobalShortcut(
    id: GlobalShortcutId.navServices,
    activator: SingleActivator(LogicalKeyboardKey.digit4, control: true),
    keys: 'Ctrl+4',
    description: 'Jump to Services',
  ),
  GlobalShortcut(
    id: GlobalShortcutId.navLibrary,
    activator: SingleActivator(LogicalKeyboardKey.digit5, control: true),
    keys: 'Ctrl+5',
    description: 'Jump to Library',
  ),
  GlobalShortcut(
    id: GlobalShortcutId.navInsights,
    activator: SingleActivator(LogicalKeyboardKey.digit6, control: true),
    keys: 'Ctrl+6',
    description: 'Jump to Insights',
  ),
  GlobalShortcut(
    id: GlobalShortcutId.navSettings,
    activator: SingleActivator(LogicalKeyboardKey.digit7, control: true),
    keys: 'Ctrl+7',
    description: 'Jump to Settings',
  ),
  GlobalShortcut(
    id: GlobalShortcutId.toggleNavRail,
    activator: SingleActivator(LogicalKeyboardKey.keyB, control: true),
    keys: 'Ctrl+B',
    description: 'Collapse or expand the nav rail',
  ),
];
