import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config_models.dart';
import '../../core/settings_nav.dart';
import '../../core/theme/tokens.dart';
import '../../ui/page.dart';
import 'limit_card.dart';

const _groupOrder = ['scan', 'scrape', 'follow', 'timing'];
const _groupTitles = {'scan': 'Scan', 'scrape': 'Scrape', 'follow': 'Follow', 'timing': 'Timings'};
const _groupCaptions = {'timing': 'seconds — how long each trigger waits'};

class LimitsTab extends ConsumerStatefulWidget {
  const LimitsTab({super.key, required this.config});

  final ConfigResponse config;

  @override
  ConsumerState<LimitsTab> createState() => _LimitsTabState();
}

/// A `ConsumerStatefulWidget` since V2.12 — a palette "jump to its field"
/// result (`highlightedConfigKeyProvider`) needs a real, per-field
/// `GlobalKey` to scroll to, which a plain `StatelessWidget` has nowhere to
/// keep across rebuilds.
class _LimitsTabState extends ConsumerState<LimitsTab> {
  final _cardKeys = <String, GlobalKey>{};

  GlobalKey _keyFor(String name) => _cardKeys.putIfAbsent(name, () => GlobalKey());

  void _scrollToHighlight(String? key) {
    if (key == null) return;
    final target = _cardKeys[key]?.currentContext;
    if (target == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Scrollable.ensureVisible(target, duration: const Duration(milliseconds: 250), alignment: 0.5);
    });
  }

  @override
  Widget build(BuildContext context) {
    final byGroup = <String, List<ConfigKeySchema>>{};
    for (final key in widget.config.schema) {
      if (key.type != 'int') continue;
      byGroup.putIfAbsent(key.group, () => []).add(key);
    }

    final tokens = Theme.of(context).tokens;
    final highlighted = ref.watch(highlightedConfigKeyProvider);
    ref.listen<String?>(highlightedConfigKeyProvider, (previous, next) => _scrollToHighlight(next));

    return ListView(
      padding: EdgeInsets.all(tokens.space.lg),
      children: [
        for (final group in _groupOrder)
          if (byGroup[group] case final keys?) ...[
            SectionHeader(title: _groupTitles[group]!, caption: _groupCaptions[group]),
            SizedBox(height: tokens.space.md),
            Wrap(
              spacing: tokens.space.lg,
              runSpacing: tokens.space.lg,
              children: [
                for (final schema in keys)
                  LimitCard(
                    key: _keyFor(schema.name),
                    schema: schema,
                    committedValue: widget.config.values.limits[schema.name]!,
                    highlighted: highlighted == schema.name,
                  ),
              ],
            ),
            SizedBox(height: tokens.space.xxl),
          ],
      ],
    );
  }
}
