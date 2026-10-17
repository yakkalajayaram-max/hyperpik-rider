import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// A thumb-friendly confirm: drag the knob across to commit a step that cannot be undone (picked up, delivered). A tap on a
/// button is too easy to do by accident on a bike.
class SlideToConfirm extends StatefulWidget {
  const SlideToConfirm({super.key, required this.label, required this.onConfirmed, this.color = Rd.accent, this.busy = false});
  final String label;
  final Future<void> Function() onConfirmed;
  final Color color;
  final bool busy;

  @override
  State<SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<SlideToConfirm> {
  double _x = 0;
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      const knob = 60.0;
      final max = c.maxWidth - knob - 8;
      return Container(
        height: 68,
        decoration: BoxDecoration(color: widget.color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(34), border: Border.all(color: widget.color.withValues(alpha: 0.5))),
        child: Stack(children: [
          Center(
            child: Opacity(
              opacity: (1 - (_x / (max == 0 ? 1 : max))).clamp(0.25, 1),
              child: Text(widget.busy ? 'Please wait…' : widget.label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16.5, letterSpacing: 0.2)),
            ),
          ),
          Positioned(
            left: 4 + _x,
            top: 4,
            child: GestureDetector(
              onHorizontalDragUpdate: widget.busy || _done ? null : (d) => setState(() => _x = (_x + d.delta.dx).clamp(0, max)),
              onHorizontalDragEnd: widget.busy || _done
                  ? null
                  : (_) async {
                      if (_x >= max * 0.88) {
                        setState(() {
                          _x = max;
                          _done = true;
                        });
                        HapticFeedback.heavyImpact();
                        await widget.onConfirmed();
                        if (mounted) {
                          setState(() {
                            _x = 0;
                            _done = false;
                          });
                        }
                      } else {
                        setState(() => _x = 0);
                      }
                    },
              child: Container(
                width: knob,
                height: knob,
                decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.5), blurRadius: 14)]),
                child: Icon(_done ? Icons.check_rounded : Icons.chevron_right_rounded, color: Colors.white, size: 34),
              ),
            ),
          ),
        ]),
      );
    });
  }
}

/// A calm pulse behind an icon: the visual for "online, looking for deliveries".
class Radar extends StatefulWidget {
  const Radar({super.key, required this.active});
  final bool active;

  @override
  State<Radar> createState() => _RadarState();
}

class _RadarState extends State<Radar> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.active ? Rd.online : Rd.muted;
    return SizedBox(
      width: 190,
      height: 190,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Stack(alignment: Alignment.center, children: [
          if (widget.active)
            for (final shift in const [0.0, 0.5])
              Builder(builder: (_) {
                final t = (_c.value + shift) % 1;
                return Container(
                  width: 70 + 120 * t,
                  height: 70 + 120 * t,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color.withValues(alpha: (1 - t) * 0.6), width: 2)),
                );
              }),
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.18), shape: BoxShape.circle, border: Border.all(color: color, width: 2)),
            child: Icon(widget.active ? Icons.two_wheeler_rounded : Icons.power_settings_new_rounded, color: color, size: 40),
          ),
        ]),
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.icon});
  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Rd.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: Rd.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (icon != null) ...[Icon(icon, size: 16, color: Rd.muted), const SizedBox(width: 6)],
          Text(label, style: const TextStyle(color: Rd.muted, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
      ]),
    );
  }
}
