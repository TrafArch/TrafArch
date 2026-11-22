import 'package:flutter/material.dart';

abstract final class GalleryMotion {
  static const instant = Duration(milliseconds: 100);
  static const fast = Duration(milliseconds: 160);
  static const normal = Duration(milliseconds: 220);
  static const medium = Duration(milliseconds: 300);
  static const slow = Duration(milliseconds: 400);

  static const standard = Curves.easeInOutCubic;
  static const emphasized = Curves.easeOutCubic;
  static const decelerate = Curves.easeOutCubic;
  static const accelerate = Curves.easeInCubic;
  static const linear = Curves.linear;
  static const curve = decelerate;

  static const micro = 2.0;
  static const small = 4.0;
  static const distance = 8.0;
  static const large = 16.0;
  static const menuDistance = 6.0;
  static const expandDistance = 6.0;
  static const menuScale = .96;
  static const pressedScale = .98;
  static const menuExitScale = .98;
  static const sheetScrim = Color(0x66000000);

  static const theme = Duration(milliseconds: 200);
  static const main = theme;
  static const page = medium;
  static const back = Duration(milliseconds: 260);
  static const sheet = Duration(milliseconds: 320);
  static const sheetBack = feedbackIn;
  static const menu = Duration(milliseconds: 180);
  static const menuBack = Duration(milliseconds: 140);
  static const expand = back;
  static const collapse = normal;
  static const arrow = theme;
  static const feedbackIn = Duration(milliseconds: 240);
  static const feedbackOut = menu;
  static const readResult = Duration(milliseconds: 560);
  static const content = fast;
  static const capsule = menu;

  static Duration duration(BuildContext context, Duration normal) =>
      (MediaQuery.maybeDisableAnimationsOf(context) ?? false)
      ? Duration.zero
      : normal;
}

class GalleryPressFeedback extends StatefulWidget {
  const GalleryPressFeedback({
    super.key,
    required this.enabled,
    required this.child,
  });

  final bool enabled;
  final Widget child;

  @override
  State<GalleryPressFeedback> createState() => _GalleryPressFeedbackState();
}

class _GalleryPressFeedbackState extends State<GalleryPressFeedback> {
  int? _pointer;

  void _release(PointerEvent event) {
    if (_pointer == event.pointer) setState(() => _pointer = null);
  }

  @override
  void didUpdateWidget(GalleryPressFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _pointer = null;
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: !widget.enabled
        ? null
        : (event) {
            if (_pointer == null && event.buttons == 1) {
              setState(() => _pointer = event.pointer);
            }
          },
    onPointerUp: _release,
    onPointerCancel: _release,
    child: AnimatedScale(
      scale: _pointer != null && !MediaQuery.disableAnimationsOf(context)
          ? GalleryMotion.pressedScale
          : 1,
      duration: GalleryMotion.duration(context, GalleryMotion.instant),
      curve: GalleryMotion.decelerate,
      child: widget.child,
    ),
  );
}
