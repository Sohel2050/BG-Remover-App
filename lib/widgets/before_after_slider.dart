import 'dart:io';
import 'package:flutter/material.dart';

/// Classic draggable before/after comparison slider.
/// [before] and [after] should be same-aspect-ratio images (e.g. original
/// photo vs. the background-removed result) — both are laid out identically
/// via BoxFit.contain so the divider lines up correctly on both.
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
  double _dividerFraction = 0.5; // 0 = all "after", 1 = all "before"

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final dividerX = width * _dividerFraction;

        return GestureDetector(
          onHorizontalDragUpdate: (details) {
            setState(() {
              _dividerFraction =
                  (dividerX + details.delta.dx) / width;
              _dividerFraction = _dividerFraction.clamp(0.0, 1.0);
            });
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // "After" fills the whole area.
              Positioned.fill(child: widget.after),

              // "Before" is clipped to the left portion only.
              Positioned.fill(
                child: ClipRect(
                  clipper: _LeftClipper(dividerX),
                  child: Image.file(widget.before, fit: BoxFit.contain),
                ),
              ),

              // Divider line + drag handle.
              Positioned(
                left: dividerX - 1,
                top: 0,
                bottom: 0,
                child: Container(width: 2, color: Colors.white),
              ),
              Positioned(
                left: dividerX - 16,
                top: constraints.maxHeight / 2 - 16,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(blurRadius: 4, color: Colors.black38),
                    ],
                  ),
                  child: const Icon(Icons.drag_handle, size: 18),
                ),
              ),

              // Labels.
              const Positioned(
                left: 8,
                top: 8,
                child: _Label(text: 'Before'),
              ),
              const Positioned(
                right: 8,
                top: 8,
                child: _Label(text: 'After'),
              ),
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
