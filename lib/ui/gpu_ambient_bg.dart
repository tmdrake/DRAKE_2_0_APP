import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../ble/suit_state.dart';

/// GPU-composited ambient backdrop (Impeller / Vulkan / GLES).
///
/// Animated radial fills + soft rings painted each frame. Impeller accelerates
/// this on device; no full 3D engine required for a live shell feel.
class GpuAmbientBg extends StatefulWidget {
  const GpuAmbientBg({
    super.key,
    required this.linkState,
    required this.accent,
    required this.child,
  });

  final LinkState linkState;
  final Color accent;
  final Widget child;

  @override
  State<GpuAmbientBg> createState() => _GpuAmbientBgState();
}

class _GpuAmbientBgState extends State<GpuAmbientBg>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker((d) {
      if (!mounted) return;
      setState(() => _elapsed = d);
    })
      ..start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_ticker.isActive) _ticker.start();
    } else {
      _ticker.stop();
    }
  }

  double get _speed {
    switch (widget.linkState) {
      case LinkState.linked:
        return 1.0;
      case LinkState.stale:
        return 0.45;
      case LinkState.scanning:
      case LinkState.connecting:
      case LinkState.retrying:
        return 1.55;
      case LinkState.off:
        return 0.28;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _elapsed.inMicroseconds / 1e6 * _speed;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Own layer so control rebuilds do not re-rasterize the ambient paint.
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _AmbientPainter(
                t: t,
                accent: widget.accent,
                linkState: widget.linkState,
              ),
              isComplex: true,
              willChange: true,
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _AmbientPainter extends CustomPainter {
  _AmbientPainter({
    required this.t,
    required this.accent,
    required this.linkState,
  });

  final double t;
  final Color accent;
  final LinkState linkState;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width;
    final h = size.height;

    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF0D0618),
    );

    final liveBoost = linkState == LinkState.linked ? 1.15 : 0.85;

    final orbs = <(Offset, double, Color)>[
      (
        Offset(
          w * (0.25 + 0.12 * math.sin(t * 0.7)),
          h * (0.22 + 0.08 * math.cos(t * 0.55)),
        ),
        w * 0.55,
        const Color(0xFF7B2CBF),
      ),
      (
        Offset(
          w * (0.78 + 0.1 * math.cos(t * 0.5)),
          h * (0.35 + 0.1 * math.sin(t * 0.65)),
        ),
        w * 0.48,
        accent,
      ),
      (
        Offset(
          w * (0.5 + 0.15 * math.sin(t * 0.35 + 1.2)),
          h * (0.75 + 0.06 * math.cos(t * 0.4)),
        ),
        w * 0.6,
        const Color(0xFF00D4FF).withValues(alpha: 0.55),
      ),
    ];

    for (final (c, r, col) in orbs) {
      final paint = Paint()
        ..shader = ui.Gradient.radial(
          c,
          r,
          [
            col.withValues(alpha: 0.36 * liveBoost),
            col.withValues(alpha: 0.07 * liveBoost),
            Colors.transparent,
          ],
          const [0.0, 0.45, 1.0],
        );
      canvas.drawCircle(c, r, paint);
    }

    final cx = w * 0.5;
    final cy = h * 0.16;
    final ringR = w * 0.4;
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(t * 0.25);
    final sweep = Paint()
      ..shader = ui.Gradient.sweep(
        Offset.zero,
        [
          accent.withValues(alpha: 0.0),
          accent.withValues(alpha: 0.2 * liveBoost),
          const Color(0xFF9D4EDD).withValues(alpha: 0.16 * liveBoost),
          accent.withValues(alpha: 0.0),
        ],
        const [0.0, 0.35, 0.65, 1.0],
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 26
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawCircle(Offset.zero, ringR, sweep);
    canvas.restore();

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(w * 0.5, h * 0.4),
          math.max(w, h) * 0.85,
          [
            Colors.transparent,
            const Color(0xFF0D0618).withValues(alpha: 0.5),
            const Color(0xFF0D0618).withValues(alpha: 0.9),
          ],
          const [0.35, 0.75, 1.0],
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _AmbientPainter old) =>
      old.t != t || old.accent != accent || old.linkState != linkState;
}
