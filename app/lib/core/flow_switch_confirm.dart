import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/settings/config_controller.dart';
import 'app_snack_bar.dart';
import 'scheduler_models.dart';

/// What stops if you turn each flow off — shown in the confirmation dialog,
/// because "are you sure?" without a consequence is not a real confirmation.
/// Shared between the Settings > Flows switches tab and the Flows cards, both
/// of which toggle the same `ENTITY_*` keys.
const flowDisableConsequence = {
  'ENTITY_INGEST': 'New profiles, posts and reels posted to the Telegram channel will stop being '
      'picked up. Nothing already queued is affected.',
  'ENTITY_SCAN': 'No new usernames will be harvested from queued entities, so the classify and '
      'scrape stages will eventually run dry.',
  'ENTITY_CLASSIFY': 'Scanned row crops will pile up unclassified, and nothing new will reach '
      'gender_valid for you to promote.',
  'ENTITY_SCRAPE': 'Profiles already promoted to scrape_queued will sit there unscraped.',
  'ENTITY_FOLLOW': 'Profiles already promoted to follow_queued will sit there unfollowed.',
};

/// Returns true if the user confirmed. Only prompts when turning a flow OFF —
/// turning one on needs no confirmation.
Future<bool> confirmFlowSwitch(BuildContext context, String key, bool turningOn) async {
  if (turningOn) return true;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Turn off $key?'),
      content: Text(flowDisableConsequence[key] ?? 'This flow will stop being triggered.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Turn off'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// `flow_node.dart`'s own switch handler, lifted out (V2.12) so the command
/// palette can toggle the same `ENTITY_*` key through the same confirm +
/// apply path rather than a second copy of it.
Future<void> toggleFlowSwitch(BuildContext context, WidgetRef ref, String flow, bool value) async {
  final key = flowSwitchKey(flow);
  if (!await confirmFlowSwitch(context, key, value)) return;
  try {
    await ref.read(configControllerProvider.notifier).applySwitch(key, value);
  } on DioException {
    if (context.mounted) AppSnackBar.show(context, 'Could not update $key', isError: true);
  }
}
