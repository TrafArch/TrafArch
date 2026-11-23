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

  /// 同级底栏切换。数值与 [theme] 相同，但从「主题局部过渡」的语义里拆出来
  /// （Motion 1.0.1 差异项 D1），改一处不会波及另一处。
  static const mainTab = Duration(milliseconds: 200);
  static const main = mainTab;

  /// 卡面左滑揭示与松手回弹（同一手势的正反向）。
  static const swipe = Duration(milliseconds: 200);

  /// 轻量局部高亮／描边（裁切框激活态），与 [menu] 同值但语义独立。
  static const highlight = Duration(milliseconds: 180);

  /// 列表项插入／移除；沿用折叠的等值档位，语义与展开收起区分。
  static const insert = back;
  static const remove = normal;

  /// 读卡示意：形变与失败徽标用项目补充值，循环进度是纯装饰。
  static const readMorph = readResult;
  static const readFailure = Duration(milliseconds: 520);
  static const readLoop = Duration(milliseconds: 2800);

  /// 读卡专用强调曲线（Motion 1.0.1 差异项 D5）：蓝本未定义
  /// `easeInOutCubicEmphasized`，读卡示意需要更早收束的进出，作为项目补充
  /// 曲线集中定义，观感与既有实现一致。
  static const readCurve = Curves.easeInOutCubicEmphasized;

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
