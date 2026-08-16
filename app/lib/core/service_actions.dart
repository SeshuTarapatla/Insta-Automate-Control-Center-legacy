// V2.12 — the confirm dialogs and start/stop/restart/takeover/test calls
// `features/services/service_detail.dart` used to hand-roll privately, lifted
// out so the command palette can trigger the exact same actions with the
// exact same confirms instead of a second implementation. `ServiceDetail`
// itself now calls these too (see its own `_run` wrapper, which only adds
// the per-button busy-spinner state these standalone functions don't need).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/services/services_controller.dart';
import 'app_snack_bar.dart';
import 'service_models.dart';

/// What actually stops working while a service is down — shown in the stop
/// confirmation, because "are you sure?" without a consequence is not a real
/// confirmation (the same rule `flow_switch_confirm.dart` follows).
const serviceStopConsequence = {
  'adb': 'Every phone interaction goes through the ADB server: scan, scrape and follow runs will '
      'fail until it is back, and the pods lose the device too.',
  'vl-server': 'Gender and privacy classification stops. entity_classify will fail on every image '
      'it tries while the model is down.',
  'wsl-bridge': 'The device mirror stops. The pipeline itself keeps running — this only affects '
      'scrcpy.',
};

Future<bool> _confirm(BuildContext context, String title, String body, String action) async {
  final answer = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(action)),
      ],
    ),
  );
  return answer == true;
}

Future<void> _run(
  BuildContext context,
  Future<void> Function() body,
  String successMessage,
  String failureLabel,
) async {
  try {
    await body();
    if (context.mounted) AppSnackBar.show(context, successMessage);
  } catch (error) {
    if (context.mounted) {
      AppSnackBar.show(context, '$failureLabel: ${describeAgentError(error)}', isError: true);
    }
  }
}

Future<void> startService(BuildContext context, WidgetRef ref, ServiceStatus status) => _run(
  context,
  () => ref.read(servicesControllerProvider.notifier).start(status.name),
  '${status.label} started',
  status.label,
);

Future<bool> confirmStopService(BuildContext context, ServiceStatus status) => _confirm(
  context,
  'Stop ${status.label}?',
  serviceStopConsequence[status.name] ?? 'Anything that depends on it will fail until it is back.',
  'Stop',
);

Future<void> stopService(BuildContext context, WidgetRef ref, ServiceStatus status) async {
  if (!await confirmStopService(context, status)) return;
  if (!context.mounted) return;
  await _run(
    context,
    () => ref.read(servicesControllerProvider.notifier).stop(status.name),
    '${status.label} stopped',
    status.label,
  );
}

Future<void> restartService(BuildContext context, WidgetRef ref, ServiceStatus status) => _run(
  context,
  () => ref.read(servicesControllerProvider.notifier).restart(status.name),
  '${status.label} restarted',
  status.label,
);

Future<bool> confirmTakeoverService(BuildContext context, ServiceStatus status) => _confirm(
  context,
  'Take over ${status.label}?',
  'The agent will kill ${status.external?.display ?? 'the external process'} '
      '(pid ${status.external?.pid}) and start its own supervised copy on port ${status.port}. '
      'Anything mid-flight through it will be interrupted.',
  'Take over',
);

Future<void> takeoverService(BuildContext context, WidgetRef ref, ServiceStatus status) async {
  if (!await confirmTakeoverService(context, status)) return;
  if (!context.mounted) return;
  await _run(
    context,
    () => ref.read(servicesControllerProvider.notifier).takeover(status.name),
    '${status.label} taken over',
    status.label,
  );
}

/// A failing test is an answer, not an error — reported as plainly as a
/// passing one via the same snackbar path, its metrics staying on screen
/// either way (`ServiceDetail`'s stat panels re-read `runTest`'s stored
/// outcome, not this function's return value).
Future<void> testService(BuildContext context, WidgetRef ref, ServiceStatus status) async {
  try {
    final outcome = await ref.read(servicesControllerProvider.notifier).runTest(status.name);
    if (context.mounted) {
      AppSnackBar.show(context, '${status.label}: ${outcome.summary}', isError: !outcome.ok);
    }
  } catch (error) {
    if (context.mounted) {
      AppSnackBar.show(context, '${status.label}: ${describeAgentError(error)}', isError: true);
    }
  }
}
