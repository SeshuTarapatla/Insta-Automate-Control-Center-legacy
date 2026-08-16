// V2.12 — `features/settings/ops_tab.dart`'s own `_run` (confirm-if-needed,
// start, fold 409s and other failures into a snackbar) lifted out so the
// command palette can start the exact same job through the exact same path.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/services/services_controller.dart' show describeAgentError;
import '../features/settings/ops_controller.dart';
import 'app_snack_bar.dart';
import 'ops_confirm.dart';
import 'ops_models.dart';

/// Returns the started job, or `null` if the user cancelled the confirm
/// dialog or the start call failed (a snackbar already explains why).
Future<OpsJob?> runOpsJob(BuildContext context, WidgetRef ref, OpsJobSpec spec) async {
  if (spec.confirm) {
    final confirmed = await confirmOpsAction(context, spec.label, spec.consequence ?? '');
    if (!confirmed) return null;
  }
  if (!context.mounted) return null;
  try {
    return await ref.read(opsJobsControllerProvider.notifier).start(spec.id);
  } on DioException catch (error) {
    if (!context.mounted) return null;
    final message = error.response?.statusCode == 409
        ? 'A job is already running — wait for it to finish first.'
        : 'Failed to start ${spec.label}: ${describeAgentError(error)}';
    AppSnackBar.show(context, message, isError: true);
    return null;
  }
}
