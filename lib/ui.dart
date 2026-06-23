import 'package:flutter/material.dart';

/// Design tokens lifted from the IMS HLS-Streamer monitoring console:
/// near-black panels, monospace type, amber / teal / green signal colors,
/// thin borders that light up amber on focus.
class P {
  static const bg = Color(0xFF070B11);
  static const panel = Color(0xFF0C1119);
  static const panelHi = Color(0xFF10171F);
  static const border = Color(0xFF182832);
  static const amber = Color(0xFFF9AE05);
  static const teal = Color(0xFF2FD4C4);
  static const green = Color(0xFF40E07C);
  static const grey = Color(0xFF7D8A94);
  static const greyDim = Color(0xFF49545C);
  static const magenta = Color(0xFFE5479B);
}

const String kMono = 'monospace';

TextStyle mono({
  Color color = P.grey,
  double size = 12,
  FontWeight weight = FontWeight.w500,
  double spacing = 0,
}) =>
    TextStyle(
      fontFamily: kMono,
      color: color,
      fontSize: size,
      fontWeight: weight,
      letterSpacing: spacing,
      height: 1.15,
    );

/// Tiny uppercase, letter-spaced caption.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {this.color = P.grey, this.size = 10, super.key});
  final String text;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: mono(color: color, size: size, weight: FontWeight.w600, spacing: 1.6),
      );
}

/// Bordered status pill (LIVE / SCTE / ACTIVE / PLAYED ...).
class Pill extends StatelessWidget {
  const Pill(this.text, {required this.color, this.filled = false, super.key});
  final String text;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: filled ? color.withOpacity(0.16) : Colors.transparent,
          border: Border.all(color: color.withOpacity(0.55)),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          text.toUpperCase(),
          style: mono(color: color, size: 9.5, weight: FontWeight.w700, spacing: 1.0),
        ),
      );
}

/// Label-over-value readout used for the metric strips.
class StatReadout extends StatelessWidget {
  const StatReadout(
    this.label,
    this.value, {
    this.valueColor = P.green,
    this.valueSize = 18,
    super.key,
  });
  final String label;
  final String value;
  final Color valueColor;
  final double valueSize;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Eyebrow(label),
          const SizedBox(height: 5),
          Text(value,
              style: mono(color: valueColor, size: valueSize, weight: FontWeight.w700)),
        ],
      );
}

/// Soft pulsing status dot (the "live" heartbeat).
class PulseDot extends StatefulWidget {
  const PulseDot({this.color = P.green, this.size = 8, super.key});
  final Color color;
  final double size;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _c.drive(Tween(begin: 0.35, end: 1.0)),
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            boxShadow: [
              BoxShadow(color: widget.color.withOpacity(0.6), blurRadius: 6),
            ],
          ),
        ),
      );
}

/// D-pad / touch friendly icon button with an amber focus glow.
class FocusIconButton extends StatefulWidget {
  const FocusIconButton({
    required this.icon,
    required this.onPressed,
    this.color = P.teal,
    this.label,
    this.autofocus = false,
    super.key,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final Color color;
  final String? label;
  final bool autofocus;

  @override
  State<FocusIconButton> createState() => _FocusIconButtonState();
}

class _FocusIconButtonState extends State<FocusIconButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final accent = _focused ? P.amber : widget.color;
    return InkWell(
      autofocus: widget.autofocus,
      onTap: widget.onPressed,
      onFocusChange: (f) => setState(() => _focused = f),
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 30,
        padding: EdgeInsets.symmetric(horizontal: widget.label == null ? 8 : 10),
        decoration: BoxDecoration(
          color: _focused ? P.amber.withOpacity(0.16) : Colors.black.withOpacity(0.40),
          border: Border.all(
            color: _focused ? P.amber : P.border,
            width: _focused ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(6),
          boxShadow: _focused
              ? [BoxShadow(color: P.amber.withOpacity(0.45), blurRadius: 10)]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon, size: 15, color: accent),
            if (widget.label != null) ...[
              const SizedBox(width: 6),
              Text(widget.label!,
                  style: mono(color: accent, size: 10.5, weight: FontWeight.w700, spacing: 0.8)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Standard panel chrome (dark gradient + thin border, amber when focused).
BoxDecoration panelDecoration({bool focused = false, Color? accent}) =>
    BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [P.panelHi, P.panel],
      ),
      border: Border.all(
        color: focused ? P.amber : (accent ?? P.border),
        width: focused ? 2 : 1,
      ),
      borderRadius: BorderRadius.circular(6),
      boxShadow: focused
          ? [BoxShadow(color: P.amber.withOpacity(0.35), blurRadius: 14)]
          : null,
    );
