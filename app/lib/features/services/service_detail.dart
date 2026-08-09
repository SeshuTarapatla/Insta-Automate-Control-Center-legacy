import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_snack_bar.dart';
import '../../core/service_actions.dart';
import '../../core/service_models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/buttons.dart';
import '../../ui/icons.dart';
import '../../ui/layout.dart';
import '../../ui/status.dart';
import '../../ui/surfaces.dart';
import '../../ui/text.dart';
import 'service_status_kind.dart';
import 'service_terminal.dart';
import 'services_controller.dart';

class ServiceDetail extends ConsumerStatefulWidget {
  const ServiceDetail({super.key, required this.status});

  final ServiceStatus status;

  @override
  ConsumerState<ServiceDetail> createState() => _ServiceDetailState();
}

class _ServiceDetailState extends ConsumerState<ServiceDetail> {
  /// The action in flight, or null. One at a time: these kill and spawn process
  /// trees, and letting a second land mid-flight is how you get two copies on
  /// one port.
  String? _busy;

  Future<void> _run(String action, Future<void> Function() body, String success) async {
    setState(() => _busy = action);
    try {
      await body();
      if (mounted) AppSnackBar.show(context, success);
    } catch (error) {
      if (mounted) {
        AppSnackBar.show(
          context,
          '${widget.status.label}: ${describeAgentError(error)}',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  ServicesController get _services => ref.read(servicesControllerProvider.notifier);

  /// `core/service_actions.dart` owns the confirm dialog and the try/catch
  /// (shared with the command palette, V2.12); this only adds the per-button
  /// busy-spinner state, which is purely local UI and has no palette
  /// equivalent to share.
  Future<void> _wrap(String action, Future<void> Function() body) async {
    setState(() => _busy = action);
    await body();
    if (mounted) setState(() => _busy = null);
  }

  Future<void> _start() => _wrap('start', () => startService(context, ref, widget.status));
  Future<void> _stop() => _wrap('stop', () => stopService(context, ref, widget.status));
  Future<void> _restart() => _wrap('restart', () => restartService(context, ref, widget.status));
  Future<void> _takeover() => _wrap('takeover', () => takeoverService(context, ref, widget.status));
  Future<void> _test() => _wrap('test', () => testService(context, ref, widget.status));

  Future<void> _setSelfHeal(bool value) => _run(
    'self_heal',
    () => _services.setSelfHeal(widget.status.name, value),
    value
        ? 'Self-heal on — the agent will restart ${widget.status.label} if it dies'
        : 'Self-heal off — ${widget.status.label} will stay down if it dies',
  );

  Future<void> _setAutostart(bool value) => _run(
    'autostart',
    () => _services.setAutostart(widget.status.name, value),
    value ? 'Autostart on' : 'Autostart off',
  );

  @override
  Widget build(BuildContext context) {
    ref.watch(uptimeTickProvider);

    final status = widget.status;
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    // At the 1024 px minimum window this pane is ~550 wide, where the stat
    // chips wrap onto four rows and every card's text wraps with them — the
    // panels above the terminal can genuinely want more height than the window
    // has. A vertical `ResizableSplit` replaces the old fixed "everything
    // except the terminal's floor" calculation: the panels scroll among
    // themselves within whatever share of the height the user has dragged for
    // them, and the terminal keeps the rest.
    return ResizableSplit(
      axis: Axis.vertical,
      persistKey: 'services.detail.split',
      initialFirstSize: 360,
      minFirst: 260,
      minSecond: 220,
      first: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(theme, status),
            SizedBox(height: tokens.space.lg),
            _stats(theme, status),
            SizedBox(height: tokens.space.md),
            _switches(theme, status),
            if (status.hasTest) ...[SizedBox(height: tokens.space.md), _testPanel(theme, status)],
          ],
        ),
      ),
      second: ServiceTerminal(key: ValueKey(status.name), status: status),
    );
  }

  // ---------------------------------------------------------------- header

  Widget _header(ThemeData theme, ServiceStatus status) {
    final tokens = theme.tokens;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  StatusDot(kind: status.state.statusKind, pulsing: status.state.isTransient, size: 12),
                  SizedBox(width: tokens.space.sm),
                  // Flexible, not fixed: at the 1024 px minimum window the
                  // action buttons leave this row little to work with, and the
                  // name is the part that can afford to ellipsize.
                  Flexible(
                    child: Text(
                      status.label,
                      style: theme.textTheme.headlineSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(width: tokens.space.sm),
                  Text(
                    status.state.label.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: status.state.color(theme),
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              SizedBox(height: tokens.space.xs),
              Text(
                status.description,
                style: theme.textTheme.bodyMedium?.copyWith(color: tokens.content.secondary),
              ),
            ],
          ),
        ),
        SizedBox(width: tokens.space.lg),
        // A Row lays its non-flexible children out first, against the full
        // width — without a cap the button Wrap could take the lot and leave
        // the name nothing to render into.
        ConstrainedBox(constraints: const BoxConstraints(maxWidth: 360), child: _actions(status)),
      ],
    );
  }

  Widget _actions(ServiceStatus status) {
    final busy = _busy != null;

    return ButtonGroup(
      children: [
        if (status.canTakeover)
          AppButton(
            label: 'Take over',
            tone: ButtonTone.primary,
            filled: true,
            busy: _busy == 'takeover',
            onPressed: busy ? null : _takeover,
          )
        else if (status.isRunning)
          AppButton(
            label: 'Restart',
            busy: _busy == 'restart',
            onPressed: busy ? null : _restart,
          )
        else
          AppButton(
            label: 'Start',
            tone: ButtonTone.primary,
            filled: true,
            busy: _busy == 'start',
            onPressed: busy ? null : _start,
          ),
        if (status.canStop)
          AppButton(
            label: 'Stop',
            tone: ButtonTone.danger,
            busy: _busy == 'stop',
            onPressed: busy ? null : _stop,
          ),
        if (status.hasTest)
          AppButton(
            label: 'Test',
            busy: _busy == 'test',
            // The test needs something to talk to; an external process still
            // answers on the port, so it is testable without being ours.
            onPressed: busy || !status.isRunning ? null : _test,
          ),
      ],
    );
  }

  // ----------------------------------------------------------------- stats

  Widget _stats(ThemeData theme, ServiceStatus status) {
    final probe = status.probe;
    final tokens = theme.tokens;

    return Wrap(
      spacing: tokens.space.sm,
      runSpacing: tokens.space.sm,
      children: [
        _Stat(
          label: 'Uptime',
          value: status.liveUptimeS == null ? '—' : formatUptime(status.liveUptimeS!),
        ),
        _Stat(
          label: 'Restarts',
          value: '${status.restartCount}',
          tone: status.restartCount > 0 ? tokens.status.warn.fg : null,
        ),
        _Stat(label: 'PID', value: status.pid?.toString() ?? '—'),
        _Stat(label: 'Port', value: '${status.port}'),
        _Stat(
          label: 'Probe',
          value: probe == null ? '—' : '${probe.latencyMs.round()} ms',
          tone: probe == null
              ? null
              : (probe.ok ? tokens.status.good.fg : theme.colorScheme.error),
          detail: probe?.detail,
        ),
        if (status.exitCode != null)
          _Stat(
            label: 'Exit code',
            value: '${status.exitCode}',
            tone: theme.colorScheme.error,
          ),
        _Stat(label: 'Owner', value: status.origin.label, detail: _ownerDetail(status)),
      ],
    );
  }

  String? _ownerDetail(ServiceStatus status) => switch (status.origin) {
    ServiceOrigin.supervised => 'Started by the agent this run, so its terminal is captured.',
    ServiceOrigin.adopted =>
      'Left running by an earlier agent run and picked back up — the agent can restart without '
          'taking the pipeline down with it.',
    ServiceOrigin.external =>
      'Port held by ${status.portOwner?.display ?? 'another process'}. Take over would kill '
          '${status.external?.display ?? 'its root process'}.',
    ServiceOrigin.none => null,
  };

  // -------------------------------------------------------------- switches

  Widget _switches(ThemeData theme, ServiceStatus status) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _SwitchCard(
            title: 'Self-heal',
            subtitle: status.selfHeal
                ? 'The agent restarts it if it exits, and if it holds its port while failing its '
                      'probe for a minute.'
                : 'A crash stays a crash: it will sit here with its exit code and final output '
                      'until you restart it.',
            value: status.selfHeal,
            busy: _busy == 'self_heal',
            onChanged: _busy != null ? null : _setSelfHeal,
          ),
        ),
        SizedBox(width: theme.tokens.space.md),
        Expanded(
          child: _SwitchCard(
            title: 'Start at logon',
            subtitle: 'Saved now, effective once the agent replaces the startup shortcut (CP 2.5). '
                'Today the shortcut still starts these, and the agent adopts them.',
            value: status.autostart,
            busy: _busy == 'autostart',
            onChanged: _busy != null ? null : _setAutostart,
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ test

  Widget _testPanel(ThemeData theme, ServiceStatus status) {
    final tokens = theme.tokens;
    final test = status.lastTest;
    final tone = test == null
        ? tokens.content.secondary
        : (test.ok ? tokens.status.good.fg : theme.colorScheme.error);

    return AppPanel(
      level: SurfaceLevel.raised,
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AppIcon(
                  test == null
                      ? AppIcons.science
                      : (test.ok ? AppIcons.success : AppIcons.error),
                  size: IconSize.sm,
                  color: tone,
                ),
                SizedBox(width: tokens.space.xs),
                Text('Functional test', style: theme.textTheme.labelLarge),
                const Spacer(),
                if (test != null) NumericText('${test.durationMs.round()} ms', role: TextRole.caption, color: tokens.content.secondary),
              ],
            ),
            SizedBox(height: tokens.space.xs),
            Text(
              test?.summary ??
                  'Not run yet. Unlike the probe, this does real work — a shell command, an '
                      'inference, a scrcpy round trip — and reports what it measured.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: test == null ? tokens.content.secondary : null,
              ),
            ),
            if (test != null && test.metrics.isNotEmpty) ..._metrics(theme, test),
          ],
        ),
      ),
    );
  }
}

/// A test reports whatever it measured, and the values are not all the same
/// shape: `231` and a 100-character model blob path both arrive as metrics.
/// Numbers read well as chips; a path does not — as a chip it either runs off
/// the card or squeezes every other chip out of the row. So the long ones drop
/// to their own full-width line underneath.
List<Widget> _metrics(ThemeData theme, TestOutcome test) {
  const inlineLimit = 40;
  final entries = test.metrics.entries.toList();
  final short = entries.where((entry) => '${entry.value}'.length <= inlineLimit);
  final long = entries.where((entry) => '${entry.value}'.length > inlineLimit);

  return [
    if (short.isNotEmpty) ...[
      const Gap.sm(),
      // Wrap hands its children unbounded width, so even a chip that is meant
      // to be short is told the line width it has to fit inside.
      LayoutBuilder(
        builder: (context, constraints) => Wrap(
          spacing: theme.tokens.space.sm,
          runSpacing: theme.tokens.space.sm,
          children: [
            for (final entry in short)
              _MetricChip(
                label: entry.key.replaceAll('_', ' '),
                value: '${entry.value}',
                maxWidth: constraints.maxWidth,
              ),
          ],
        ),
      ),
    ],
    for (final entry in long) ...[
      const Gap.sm(),
      _MetricLine(label: entry.key.replaceAll('_', ' '), value: '${entry.value}'),
    ],
  ];
}

class _MetricLine extends StatelessWidget {
  const _MetricLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    return Tooltip(
      message: value,
      child: AppPanel(
        level: SurfaceLevel.raised,
        padding: EdgeInsets.symmetric(horizontal: tokens.space.sm, vertical: tokens.space.xs),
        borderRadius: tokens.geometry.radiusSm,
        child: Row(
          children: [
            Text(label, style: theme.textTheme.labelSmall?.copyWith(color: tokens.content.secondary)),
            SizedBox(width: tokens.space.xs),
            Expanded(child: MonoText(value, role: TextRole.label)),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.tone, this.detail});

  final String label;
  final String value;
  final Color? tone;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    final box = AppPanel(
      level: SurfaceLevel.raised,
      padding: EdgeInsets.symmetric(horizontal: tokens.space.md, vertical: tokens.space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(color: tokens.content.secondary, letterSpacing: 0.8),
          ),
          SizedBox(height: tokens.space.xs / 2),
          NumericText(value, role: TextRole.cardTitle, color: tone),
        ],
      ),
    );

    return detail == null ? box : Tooltip(message: detail!, child: box);
  }
}

class _SwitchCard extends StatelessWidget {
  const _SwitchCard({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.busy,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final bool busy;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    return AppPanel(
      level: SurfaceLevel.raised,
      padding: EdgeInsets.fromLTRB(tokens.space.md, tokens.space.sm, tokens.space.sm, tokens.space.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.labelLarge),
                SizedBox(height: tokens.space.xs / 1.3),
                Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary)),
              ],
            ),
          ),
          busy
              ? Padding(
                  padding: EdgeInsets.all(tokens.space.md),
                  child: const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value, required this.maxWidth});

  final String label;
  final String value;

  /// The width of the line the chip sits on. A chip never exceeds it: the value
  /// ellipsizes and the full text moves to the tooltip.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    final chip = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: AppPanel(
        level: SurfaceLevel.raised,
        padding: EdgeInsets.symmetric(horizontal: tokens.space.sm, vertical: tokens.space.xs),
        borderRadius: tokens.geometry.radiusSm,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: theme.textTheme.labelSmall?.copyWith(color: tokens.content.secondary)),
            SizedBox(width: tokens.space.xs),
            Flexible(child: NumericText(value, role: TextRole.label)),
          ],
        ),
      ),
    );

    // Only where it can actually be cut off — a tooltip on `231` is noise.
    return value.length > 24 ? Tooltip(message: value, child: chip) : chip;
  }
}
