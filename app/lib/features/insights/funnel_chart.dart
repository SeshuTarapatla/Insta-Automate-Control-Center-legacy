import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../ui/icons.dart';
import '../../ui/text.dart';

/// One stage of a sequential funnel — `count` is the real number at that
/// stage, `caption` is optional extra context shown under the conversion
/// line (e.g. the male-classified-instead note, or "real all-time total").
/// `onTap`, when set, jumps to the matching Library folder — only stages
/// with a genuine folder to browse get one (V2.11); a stage with no real
/// folder (e.g. "Private", "Followed") stays a plain label rather than a
/// link that would land somewhere misleading.
class FunnelStageData {
  const FunnelStageData({required this.label, required this.count, this.caption, this.onTap});

  final String label;
  final int count;
  final String? caption;
  final VoidCallback? onTap;
}

/// A real narrowing funnel (PLAN CP 7.2, corrected from a flat bar-per-stage
/// layout): each stage is a trapezoid whose *top* edge matches the previous
/// stage's width and whose *bottom* edge matches its own, so the shape reads
/// as one continuous silhouette narrowing stage by stage — not five
/// identically-scaled bars that all read "% of the very first stage" and
/// therefore stop moving once a stage is already small.
///
/// Every stage is labeled with **both** conversion numbers, since either one
/// alone hides something real: "% of total" answers "how much of the
/// original pool made it this far" but flattens out for a stage several
/// filters deep (2% of scanned looks the same whether Followed dropped hard
/// this stage or was always thin); "% of previous" answers "how much of
/// *this* filter's input survived it" but says nothing about overall scale.
/// Showing both is the actual fix for what a single normalized bar can't
/// say — not a fancier bar, a different question answered per stage.
///
/// Draws in on first build, one stage at a time top to bottom
/// (`tokens.motion.standard`, staggered by stage via `Interval`) — collapses
/// to the plain static shape instantly under `tokens.motion.reduced`.
class FunnelChart extends StatefulWidget {
  const FunnelChart({super.key, required this.stages});

  final List<FunnelStageData> stages;

  // Tall enough for three lines (name+count, conversion, an optional
  // caption) plus the label's own vertical padding — measured against the
  // real font metrics, not guessed, since a caption-bearing stage is the
  // tallest content this label ever holds.
  static const _segmentHeight = 84.0;
  static const _labelWidth = 300.0;

  @override
  State<FunnelChart> createState() => _FunnelChartState();
}

class _FunnelChartState extends State<FunnelChart> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final tokens = Theme.of(context).tokens;
    _controller.duration = tokens.motion.standard;
    if (tokens.motion.reduced) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final stages = widget.stages;
    if (stages.isEmpty) return const SizedBox.shrink();

    final maxCount = stages.first.count == 0 ? 1 : stages.first.count;
    final fractions = [for (final stage in stages) (stage.count / maxCount).clamp(0.0, 1.0)];
    final fillColor = tokens.chart.series.isNotEmpty ? tokens.chart.series.first : theme.colorScheme.primary;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final n = fractions.length;
        final reveal = [
          for (var i = 0; i < n; i++)
            Interval(i / n, (i + 1) / n, curve: tokens.motion.enter).transform(_controller.value.clamp(0.0, 1.0)),
        ];

        return SizedBox(
          height: FunnelChart._segmentHeight * stages.length,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: CustomPaint(
                  painter: _FunnelPainter(
                    fractions: fractions,
                    reveal: reveal,
                    color: fillColor,
                    boundaryColor: tokens.chart.grid,
                  ),
                ),
              ),
              SizedBox(width: tokens.space.xl),
              SizedBox(
                width: FunnelChart._labelWidth,
                child: Column(
                  children: [
                    for (var i = 0; i < stages.length; i++)
                      SizedBox(
                        height: FunnelChart._segmentHeight,
                        child: _FunnelLabel(
                          stage: stages[i],
                          pctOfTotal: stages[i].count / maxCount * 100,
                          pctOfPrevious: i == 0
                              ? null
                              : (stages[i - 1].count == 0 ? 0 : stages[i].count / stages[i - 1].count * 100),
                          previousLabel: i == 0 ? null : stages[i - 1].label.toLowerCase(),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FunnelLabel extends StatelessWidget {
  const _FunnelLabel({required this.stage, required this.pctOfTotal, this.pctOfPrevious, this.previousLabel});

  final FunnelStageData stage;
  final double pctOfTotal;
  final double? pctOfPrevious;
  final String? previousLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conversion = pctOfPrevious == null
        ? '${pctOfTotal.toStringAsFixed(0)}% of total'
        : '${pctOfPrevious!.toStringAsFixed(0)}% of $previousLabel · ${pctOfTotal.toStringAsFixed(0)}% of total';

    final tokens = theme.tokens;
    final content = Padding(
      padding: EdgeInsets.symmetric(vertical: tokens.space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(stage.label, style: theme.textTheme.bodyMedium),
              SizedBox(width: tokens.space.xs),
              Flexible(
                child: NumericText(
                  stage.count,
                  role: TextRole.cardTitle,
                ),
              ),
              if (stage.onTap != null) ...[
                SizedBox(width: tokens.space.xs),
                AppIcon(AppIcons.chevronRight, size: IconSize.sm, color: tokens.content.secondary),
              ],
            ],
          ),
          SizedBox(height: tokens.space.xs / 2),
          Text(
            conversion,
            style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (stage.caption != null)
            Text(
              stage.caption!,
              style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );

    if (stage.onTap == null) return content;
    return InkWell(
      onTap: stage.onTap,
      borderRadius: BorderRadius.circular(tokens.geometry.radiusSm),
      child: content,
    );
  }
}

/// Draws the continuous trapezoid silhouette: stage `i`'s top edge is stage
/// `i-1`'s width (so consecutive stages connect with no visual seam) and its
/// bottom edge is its own — a real narrowing funnel, not `n` separately-
/// scaled bars. A non-zero stage is floored to a minimum visible width so a
/// genuinely thin tail (2% of the top) doesn't taper away to nothing.
/// `reveal[i]` (0→1) scales stage `i`'s own edges for the draw-in animation —
/// by the time a later stage starts revealing, every earlier stage's own
/// `reveal` has already reached 1 (the stagger intervals don't overlap), so
/// its edge is already at its real width and only the new stage grows in.
class _FunnelPainter extends CustomPainter {
  _FunnelPainter({required this.fractions, required this.reveal, required this.color, required this.boundaryColor});

  final List<double> fractions;
  final List<double> reveal;
  final Color color;
  final Color boundaryColor;

  static const _minFraction = 0.03;

  @override
  void paint(Canvas canvas, Size size) {
    if (fractions.isEmpty || size.width <= 0 || size.height <= 0) return;
    final segmentHeight = size.height / fractions.length;
    final fillPaint = Paint()..color = color;
    final boundaryPaint = Paint()
      ..color = boundaryColor
      ..strokeWidth = 2;
    final centerX = size.width / 2;

    double widthFor(int index) {
      final fraction = fractions[index];
      final floored = fraction <= 0 ? 0.0 : fraction.clamp(_minFraction, 1.0);
      return size.width * floored * reveal[index];
    }

    for (var i = 0; i < fractions.length; i++) {
      final topWidth = widthFor(i == 0 ? 0 : i - 1);
      final bottomWidth = widthFor(i);
      final y0 = i * segmentHeight;
      final y1 = (i + 1) * segmentHeight;

      final path = Path()
        ..moveTo(centerX - topWidth / 2, y0)
        ..lineTo(centerX + topWidth / 2, y0)
        ..lineTo(centerX + bottomWidth / 2, y1)
        ..lineTo(centerX - bottomWidth / 2, y1)
        ..close();
      canvas.drawPath(path, fillPaint);

      if (i > 0 && reveal[i] > 0) {
        canvas.drawLine(Offset(centerX - topWidth / 2, y0), Offset(centerX + topWidth / 2, y0), boundaryPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FunnelPainter oldDelegate) =>
      !listEquals(oldDelegate.fractions, fractions) ||
      !listEquals(oldDelegate.reveal, reveal) ||
      oldDelegate.color != color ||
      oldDelegate.boundaryColor != boundaryColor;
}
