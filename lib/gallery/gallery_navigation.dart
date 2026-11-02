part of 'gallery_app.dart';

abstract final class _GalleryMotion {
  static const main = Duration(milliseconds: 240);
  static const page = Duration(milliseconds: 280);
  static const back = Duration(milliseconds: 220);
  static const sheet = Duration(milliseconds: 260);
  static const sheetBack = Duration(milliseconds: 200);
  static const dialog = Duration(milliseconds: 180);
  static const dialogBack = Duration(milliseconds: 140);
  static const menu = Duration(milliseconds: 140);
  static const expand = Duration(milliseconds: 180);
  static const content = Duration(milliseconds: 160);
  static const capsule = Duration(milliseconds: 180);
  static const curve = Curves.easeOutCubic;
}

class _GalleryNavigator extends StatefulWidget {
  const _GalleryNavigator({
    super.key,
    required this.controller,
    required this.preferences,
    this.onDisableBeta,
    this.openWebLink,
    this.openEmail,
  });
  final GalleryController controller;
  final GalleryPreferences preferences;
  final VoidCallback? onDisableBeta;
  final Future<void> Function(Uri)? openWebLink;
  final Future<bool> Function(String)? openEmail;

  @override
  State<_GalleryNavigator> createState() => _GalleryNavigatorState();
}

class _GalleryNavigatorState extends State<_GalleryNavigator>
    with WidgetsBindingObserver {
  final _navigator = GlobalKey<NavigatorState>();
  final Map<String, ModalRoute<void>> _routes = {};
  ModalRoute<void>? _gesture;
  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_navigationChanged);
    widget.preferences.addListener(_navigationChanged);
  }

  void _navigationChanged() {
    final active = _gesture;
    if (active != null &&
        (!widget.preferences.enabled ||
            !widget.controller.navigationStack.any(
              (e) => _routes[e.id] == active,
            ))) {
      _gesture = null;
      active.handleCancelBackGesture();
    }
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent event) {
    if (!mounted ||
        !widget.preferences.enabled ||
        widget.preferences.loading ||
        _reduceMotion ||
        event.isButtonEvent ||
        Theme.of(context).platform != TargetPlatform.android) {
      return false;
    }
    final route = _routes[widget.controller.navigationStack.last.id];
    if (route == null ||
        !route.isCurrent ||
        !route.popGestureEnabled ||
        route.popGestureInProgress) {
      return false;
    }
    _gesture = route;
    route.handleStartBackGesture(progress: 1 - event.progress.clamp(0, 1));
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent event) {
    _gesture?.handleUpdateBackGestureProgress(
      progress: 1 - event.progress.clamp(0, 1),
    );
  }

  @override
  void handleCancelBackGesture() {
    final route = _gesture;
    _gesture = null;
    route?.handleCancelBackGesture();
  }

  @override
  void handleCommitBackGesture() {
    final route = _gesture;
    _gesture = null;
    route?.handleCommitBackGesture();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_navigationChanged);
    widget.preferences.removeListener(_navigationChanged);
    _gesture = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.controller, widget.preferences]),
    builder: (context, _) {
      if (_reduceMotion && _gesture != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) handleCancelBackGesture();
        });
      }
      return NavigatorPopHandler<void>(
        onPopWithResult: (_) => _navigator.currentState?.maybePop(),
        child: Navigator(
          key: _navigator,
          onDidRemovePage: (page) => widget.controller.didPopRoute(
            (page as _GalleryRoutePage).entry.id,
          ),
          pages: [
            for (final entry in widget.controller.navigationStack)
              _GalleryRoutePage(
                entry: entry,
                reduceMotion: _reduceMotion,
                onCreated: (route) => _routes[entry.id] = route,
                onDisposed: () => _routes.remove(entry.id),
                child: AnimatedBuilder(
                  animation: Listenable.merge([
                    widget.controller,
                    widget.preferences,
                  ]),
                  builder: (context, _) => _GalleryView(
                    key: ValueKey('route-${entry.id}'),
                    entry: entry,
                    controller: widget.controller,
                    preferences: widget.preferences,
                    onDisableBeta: widget.onDisableBeta,
                    openWebLink: widget.openWebLink,
                    openEmail: widget.openEmail,
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _GalleryRoutePage extends Page<void> {
  _GalleryRoutePage({
    required this.entry,
    required this.child,
    required this.reduceMotion,
    required this.onCreated,
    required this.onDisposed,
  }) : super(
         key: ValueKey(entry.id),
         name: entry.overlay?.name ?? entry.page.name,
       );

  final GalleryRouteEntry entry;
  final Widget child;
  final bool reduceMotion;
  final ValueChanged<ModalRoute<void>> onCreated;
  final VoidCallback onDisposed;

  @override
  Route<void> createRoute(BuildContext context) {
    final ModalRoute<void> route = entry.overlay == null
        ? _GalleryPageRoute(this)
        : _GalleryPopupRoute(this);
    onCreated(route);
    return route;
  }
}

/// Keep the route controller at the gesture's actual progress when committing.
/// TransitionRoute's default commit restarts its reverse animation at 1.0.
mixin _GalleryPredictiveRoute on ModalRoute<void> {
  bool _tracking = false;
  AnimationStatusListener? _settleListener;
  final Map<Animation<double>, CurvedAnimation> _curves = {};
  _GalleryRoutePage get configuration => settings as _GalleryRoutePage;

  double motionProgress(Animation<double> parent) {
    final eased = _curves.putIfAbsent(
      parent,
      () => CurvedAnimation(
        parent: parent,
        curve: _GalleryMotion.curve,
        reverseCurve: Curves.easeInCubic,
      ),
    );
    return popGestureInProgress ? parent.value : eased.value;
  }

  @override
  void handleStartBackGesture({double progress = 1}) {
    _tracking = true;
    super.handleStartBackGesture(progress: progress);
  }

  void _settleGesture() {
    if (!_tracking) return;
    void stop() {
      if (!_tracking) return;
      _tracking = false;
      if (_settleListener != null) {
        controller?.removeStatusListener(_settleListener!);
      }
      _settleListener = null;
      navigator?.didStopUserGesture();
    }

    if (controller?.isAnimating ?? false) {
      _settleListener = (status) {
        if (status == AnimationStatus.completed ||
            status == AnimationStatus.dismissed) {
          stop();
        }
      };
      controller!.addStatusListener(_settleListener!);
    } else {
      stop();
    }
  }

  @override
  void handleCommitBackGesture() {
    if (!_tracking) return;
    if (isCurrent) {
      final progress = controller!.value;
      navigator?.pop();
      if (progress > 0) {
        controller?.animateBack(
          0,
          duration: reverseTransitionDuration * progress,
          curve: _GalleryMotion.curve,
        );
      }
    }
    _settleGesture();
  }

  @override
  void handleCancelBackGesture() {
    if (!_tracking) return;
    if (isCurrent) {
      controller?.animateTo(
        1,
        duration: transitionDuration * (1 - controller!.value),
        curve: _GalleryMotion.curve,
      );
    }
    _settleGesture();
  }

  Widget interactive(Widget child) => AnimatedBuilder(
    animation: animation!,
    builder: (context, _) => IgnorePointer(
      ignoring: !isCurrent || animation!.status == AnimationStatus.reverse,
      child: ExcludeFocus(
        excluding: !isCurrent || animation!.status == AnimationStatus.reverse,
        child: ExcludeSemantics(excluding: !isCurrent, child: child),
      ),
    ),
  );

  @override
  void dispose() {
    if (_settleListener != null) {
      controller?.removeStatusListener(_settleListener!);
    }
    if (_tracking) navigator?.didStopUserGesture();
    for (final curve in _curves.values) {
      curve.dispose();
    }
    configuration.onDisposed();
    super.dispose();
  }
}

class _GalleryPageRoute extends PageRoute<void> with _GalleryPredictiveRoute {
  _GalleryPageRoute(_GalleryRoutePage page) : super(settings: page);
  @override
  bool get maintainState => true;
  @override
  Color? get barrierColor => null;
  @override
  String? get barrierLabel => null;
  @override
  Duration get transitionDuration =>
      configuration.reduceMotion ? Duration.zero : _GalleryMotion.page;
  @override
  Duration get reverseTransitionDuration =>
      configuration.reduceMotion ? Duration.zero : _GalleryMotion.back;
  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => configuration.child;
  @override
  bool canTransitionTo(TransitionRoute<dynamic> nextRoute) =>
      nextRoute is _GalleryPageRoute;
  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (configuration.reduceMotion) return interactive(child);
    final primary = motionProgress(animation);
    final secondary = motionProgress(secondaryAnimation);
    return FractionalTranslation(
      translation: Offset((isFirst ? 0 : 1 - primary) - .08 * secondary, 0),
      child: interactive(child),
    );
  }
}

class _GalleryPopupRoute extends PopupRoute<void> with _GalleryPredictiveRoute {
  _GalleryPopupRoute(_GalleryRoutePage page) : super(settings: page);
  bool get _menu => [
    GalleryOverlay.cardMenu,
    GalleryOverlay.source,
    GalleryOverlay.mode,
  ].contains(configuration.entry.overlay);
  bool get _sheet => [
    GalleryOverlay.face,
    GalleryOverlay.trip,
    GalleryOverlay.export,
    GalleryOverlay.rawFeedback,
  ].contains(configuration.entry.overlay);
  @override
  bool get barrierDismissible => true;
  @override
  Color get barrierColor =>
      _menu ? Colors.transparent : const Color(0x99000000);
  @override
  String get barrierLabel => _menu ? '关闭菜单' : '关闭弹层';
  @override
  Curve get barrierCurve => _GalleryMotion.curve;
  @override
  Widget buildModalBarrier() => AnimatedBuilder(
    animation: animation!,
    builder: (context, _) => ModalBarrier(
      color: Color.lerp(
        Colors.transparent,
        barrierColor,
        configuration.reduceMotion ? 1 : motionProgress(animation!),
      ),
      dismissible: barrierDismissible,
      onDismiss: () => navigator?.maybePop(),
      semanticsLabel: barrierLabel,
      barrierSemanticsDismissible: true,
    ),
  );
  @override
  Duration get transitionDuration => configuration.reduceMotion
      ? Duration.zero
      : _menu
      ? _GalleryMotion.menu
      : _sheet
      ? _GalleryMotion.sheet
      : _GalleryMotion.dialog;
  @override
  Duration get reverseTransitionDuration => configuration.reduceMotion
      ? Duration.zero
      : _menu
      ? _GalleryMotion.menu
      : _sheet
      ? _GalleryMotion.sheetBack
      : _GalleryMotion.dialogBack;
  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => configuration.child;
  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final value = configuration.reduceMotion ? 1.0 : motionProgress(animation);
    final content = interactive(child);
    if (_sheet) {
      return FractionalTranslation(
        translation: Offset(0, 1 - value),
        child: content,
      );
    }
    return Opacity(
      opacity: value,
      child: _menu
          ? Transform.translate(
              offset: Offset(0, -4 * (1 - value)),
              child: content,
            )
          : Transform.scale(scale: .96 + .04 * value, child: content),
    );
  }
}

class _GalleryMainTransition extends StatefulWidget {
  const _GalleryMainTransition({
    required this.page,
    required this.child,
    required this.reduceMotion,
  });
  final GalleryPage page;
  final Widget child;
  final bool reduceMotion;
  @override
  State<_GalleryMainTransition> createState() => _GalleryMainTransitionState();
}

class _GalleryMainSlot {
  _GalleryMainSlot(this.child, this.begin, this.end);
  Widget child;
  double begin, end;
  double position(double progress) => begin + (end - begin) * progress;
}

class _GalleryMainTransitionState extends State<_GalleryMainTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation =
      AnimationController(
        vsync: this,
        duration: _GalleryMotion.main,
        value: 1,
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _slots.removeWhere((page, _) => page != widget.page));
        }
      });
  final Map<GalleryPage, _GalleryMainSlot> _slots = {};
  @override
  void initState() {
    super.initState();
    _slots[widget.page] = _GalleryMainSlot(widget.child, 0, 0);
  }

  @override
  void didUpdateWidget(_GalleryMainTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reduceMotion) {
      _animation.stop();
      _slots.clear();
      _slots[widget.page] = _GalleryMainSlot(widget.child, 0, 0);
    } else if (widget.page != oldWidget.page) {
      final value = _GalleryMotion.curve.transform(_animation.value);
      for (final item in _slots.entries) {
        item.value.begin = item.value.position(value);
        item.value.end = item.key.index < widget.page.index ? -1 : 1;
      }
      final incoming = _slots.putIfAbsent(
        widget.page,
        () => _GalleryMainSlot(
          widget.child,
          // A third tap can arrive before the previous destination reaches
          // zero. Start beside that moving page so their edges stay joined.
          _slots[oldWidget.page]!.begin +
              (widget.page.index > oldWidget.page.index ? 1 : -1),
          0,
        ),
      );
      incoming.child = widget.child;
      incoming.end = 0;
      _animation.forward(from: 0);
    } else {
      _slots[widget.page]!.child = widget.child;
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRect(
    child: AnimatedBuilder(
      animation: _animation,
      builder: (context, _) => Stack(
        fit: StackFit.expand,
        children: [
          for (final item in _slots.entries)
            FractionalTranslation(
              key: ValueKey(item.key),
              translation: Offset(
                item.value.position(
                  _GalleryMotion.curve.transform(_animation.value),
                ),
                0,
              ),
              child: IgnorePointer(
                ignoring: item.key != widget.page,
                child: ExcludeFocus(
                  excluding: item.key != widget.page,
                  child: ExcludeSemantics(
                    excluding: item.key != widget.page,
                    child: TickerMode(
                      enabled: item.key == widget.page,
                      child: ColoredBox(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: item.value.child,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _GalleryFade extends StatelessWidget {
  const _GalleryFade({
    required this.identity,
    required this.child,
    required this.reduceMotion,
  });
  final Object identity;
  final Widget child;
  final bool reduceMotion;
  @override
  Widget build(BuildContext context) => reduceMotion
      ? child
      : AnimatedSwitcher(
          duration: reduceMotion ? Duration.zero : _GalleryMotion.content,
          switchInCurve: _GalleryMotion.curve,
          switchOutCurve: _GalleryMotion.curve,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: IgnorePointer(
              ignoring: child.key != ValueKey(identity),
              child: ExcludeFocus(
                excluding: child.key != ValueKey(identity),
                child: ExcludeSemantics(
                  excluding: child.key != ValueKey(identity),
                  child: child,
                ),
              ),
            ),
          ),
          child: KeyedSubtree(key: ValueKey(identity), child: child),
        );
}

class _GalleryCollapse extends StatefulWidget {
  const _GalleryCollapse({
    required this.open,
    required this.builder,
    required this.reduceMotion,
  });
  final bool open, reduceMotion;
  final WidgetBuilder builder;
  @override
  State<_GalleryCollapse> createState() => _GalleryCollapseState();
}

class _GalleryCollapseState extends State<_GalleryCollapse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation =
      AnimationController(
        vsync: this,
        duration: _GalleryMotion.expand,
        value: widget.open ? 1 : 0,
      )..addStatusListener((status) {
        if (status == AnimationStatus.dismissed && mounted) {
          setState(() => _content = null);
        }
      });
  Widget? _content;
  @override
  void initState() {
    super.initState();
    // Initialize against the initial open state, before didUpdateWidget can
    // receive the first expansion.
    _animation;
  }

  @override
  void didUpdateWidget(_GalleryCollapse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reduceMotion) {
      _animation.value = widget.open ? 1 : 0;
    } else if (widget.open != oldWidget.open) {
      widget.open ? _animation.forward() : _animation.reverse();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.open) _content = widget.builder(context);
    if (_content == null || !widget.open && _animation.value == 0) {
      return const SizedBox.shrink();
    }
    return ClipRect(
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) => Align(
          alignment: Alignment.topCenter,
          heightFactor: _GalleryMotion.curve.transform(_animation.value),
          child: child,
        ),
        child: IgnorePointer(
          ignoring: !widget.open,
          child: ExcludeFocus(
            excluding: !widget.open,
            child: ExcludeSemantics(excluding: !widget.open, child: _content!),
          ),
        ),
      ),
    );
  }
}
