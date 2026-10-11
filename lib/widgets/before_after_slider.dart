import 'dart:io';
import 'package:flutter/material.dart';

/// Before/after comparison. The divider follows the finger directly
/// (no drag-delta lag) and only the clipped layer repaints while moving.
class BeforeAfterSlider extends StatefulWidget {
  final File before;
  final Widget after;

  const BeforeAfterSlider({
    super.key,
    required this.before,
    required this.after,
  });

  @override
  State<BeforeAfterSlider> createState() => _BeforeAfterSliderState();
}

class _BeforeAfterSliderState extends State<BeforeAfterSlider> {
  final ValueNotifier<double> _fraction = ValueNotifier<double>(0.5);

  @override
  void dispose() {
    _fraction.dispose();
    super.dispose();
  }

  void _setFrom(Offset local, double width) {
    if (width <= 0) return;
    _fraction.value = (local.dx / width).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) => _setFrom(e.localPosition, width),
          onPointerMove: (e) => _setFrom(e.localPosition, width),
          child: Stack(
            fit: StackFit.expand,
            children: [
              RepaintBoundary(child: IgnorePointer(child: widget.after)),
              ValueListenableBuilder<double>(
                valueListenable: _fraction,
                builder: (context, f, _) {
                  final dividerX = width * f;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRect(
                        clipper: _LeftClipper(dividerX),
                        child: Image.file(
                          widget.before,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                      ),
                      Positioned(
                        left: dividerX - 1,
                        top: 0,
                        bottom: 0,
                        child: Container(width: 2, color: Colors.white),
                      ),
                      Positioned(
                        left: dividerX - 16,
                        top: height / 2 - 16,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(blurRadius: 4, color: Colors.black38),
                            ],
                          ),
                          child: const Icon(Icons.drag_handle, size: 18),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const Positioned(left: 8, top: 8, child: _Label(text: 'Before')),
              const Positioned(right: 8, top: 8, child: _Label(text: 'After')),
            ],
          ),
        );
      },
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}

class _LeftClipper extends CustomClipper<Rect> {
  final double dividerX;
  _LeftClipper(this.dividerX);

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, dividerX, size.height);

  @override
  bool shouldReclip(covariant _LeftClipper oldClipper) =>
      oldClipper.dividerX != dividerX;
}
