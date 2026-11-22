part of 'gallery_app.dart';

/// Route-independent anchors, measured after layout and after scroll/metrics.
/// Positions are global logical coordinates until the popup converts them to
/// its own SafeArea; captured rectangles are only for fixture-only menus.
class _GalleryAnchorRegistry extends ChangeNotifier {
  final Map<String, BuildContext> _contexts = {};
  final Map<String, Rect?> _measured = {};
  bool _scheduled = false;
  bool _disposed = false;
  String? _activeId;

  void track(String? id) {
    if (_activeId == id) return;
    _activeId = id;
    _contexts.removeWhere((_, context) => !context.mounted);
    _measured.clear();
    scheduleMeasure();
  }

  void register(String id, BuildContext context) {
    _contexts[id] = context;
    scheduleMeasure();
  }

  void unregister(String id, BuildContext context) {
    if (!identical(_contexts[id], context)) return;
    _contexts.remove(id);
    scheduleMeasure();
  }

  Rect? boundsOf(String id) {
    final context = _contexts[id];
    if (context == null || !context.mounted) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final viewport = Scrollable.maybeOf(context)?.context.findRenderObject();
    if (viewport is RenderBox && viewport.attached && viewport.hasSize) {
      final visible = viewport.localToGlobal(Offset.zero) & viewport.size;
      if (!visible.overlaps(rect)) return null;
    }
    return rect;
  }

  void scheduleMeasure() {
    if (_scheduled || _disposed || _activeId == null) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (_disposed || _activeId == null) return;
      var changed = false;
      for (final id in [_activeId!]) {
        final rect = boundsOf(id);
        if (_measured[id] != rect) {
          _measured[id] = rect;
          changed = true;
        }
        if (_contexts[id]?.mounted == false) _contexts.remove(id);
      }
      if (changed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _contexts.clear();
    _measured.clear();
    super.dispose();
  }
}

/// Retire contexts on deactivation, before an outgoing route is disposed.
class _GalleryMenuAnchor extends StatefulWidget {
  const _GalleryMenuAnchor({
    required this.registry,
    required this.id,
    required this.child,
  });
  final _GalleryAnchorRegistry registry;
  final String id;
  final Widget child;

  @override
  State<_GalleryMenuAnchor> createState() => _GalleryMenuAnchorState();
}

class _GalleryMenuAnchorState extends State<_GalleryMenuAnchor> {
  @override
  void deactivate() {
    widget.registry.unregister(widget.id, context);
    super.deactivate();
  }

  @override
  void didUpdateWidget(_GalleryMenuAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id || oldWidget.registry != widget.registry) {
      oldWidget.registry.unregister(oldWidget.id, context);
    }
  }

  @override
  Widget build(BuildContext context) {
    widget.registry.register(widget.id, context);
    return widget.child;
  }
}

typedef _GalleryMotion = GalleryMotion;

class _GalleryNavigator extends StatefulWidget {
  const _GalleryNavigator({
    super.key,
    required this.controller,
    required this.preferences,
    required this.loadKnowledge,
    this.onDisableBeta,
    this.openWebLink,
    this.openEmail,
  });
  final GalleryController controller;
  final GalleryPreferences preferences;
  final Future<GalleryKnowledgeIndex> Function() loadKnowledge;
  final VoidCallback? onDisableBeta;
  final Future<void> Function(Uri)? openWebLink;
  final Future<bool> Function(String)? openEmail;

  @override
  State<_GalleryNavigator> createState() => _GalleryNavigatorState();
}

class _GalleryNavigatorState extends State<_GalleryNavigator>
    with WidgetsBindingObserver {
  final _navigator = GlobalKey<NavigatorState>();
  final _anchors = _GalleryAnchorRegistry();
  final Map<String, ModalRoute<void>> _routes = {};
  ModalRoute<void>? _gesture;
  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_navigationChanged);
    widget.preferences.addListener(_navigationChanged);
    _anchors.addListener(_anchorChanged);
    _anchors.track(widget.controller.navigationStack.last.anchorId);
  }

  void _anchorChanged() {
    final entry = widget.controller.navigationStack.last;
    final id = entry.anchorId;
    if (id != null && _anchors.boundsOf(id) == null) widget.controller.back();
  }

  @override
  void didChangeMetrics() => _anchors.scheduleMeasure();

  void _navigationChanged() {
    _anchors.track(widget.controller.navigationStack.last.anchorId);
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
    _anchors.dispose();
    super.dispose();
  }

  /// Opaque routes hide everything below them, so a covered page (or a page
  /// that is already leaving after its route was popped) keeps its last build
  /// instead of rebuilding an off-screen tree on every notification.
  bool _isVisible(GalleryRouteEntry entry) {
    final stack = widget.controller.navigationStack;
    final index = stack.indexWhere((e) => e.id == entry.id);
    if (index < 0) return false;
    final lastOpaque = stack.lastIndexWhere(
      (e) => e.kind != GalleryRouteKind.overlay,
    );
    return index >= lastOpaque;
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
        onPopWithResult: (_) {
          final controller = widget.controller;
          final top = controller.navigationStack.last;
          if (top.overlay == GalleryOverlay.face &&
              controller.faceCrop?.editing == true) {
            controller.exitFaceCrop();
            return;
          }
          _navigator.currentState?.maybePop();
        },
        child: Navigator(
          key: _navigator,
          onDidRemovePage: (page) => widget.controller.didPopRoute(
            (page as _GalleryRoutePage).entry.id,
          ),
          pages: [
            for (final entry in widget.controller.navigationStack)
              _GalleryRoutePage(
                entry: entry,
                controller: widget.controller,
                reduceMotion: _reduceMotion,
                onCreated: (route) => _routes[entry.id] = route,
                onDisposed: () => _routes.remove(entry.id),
                child: AnimatedBuilder(
                  animation: Listenable.merge([
                    widget.controller,
                    widget.preferences,
                    if (entry.overlay != null) _anchors,
                  ]),
                  builder: (context, _) => _GalleryView(
                    key: ValueKey('route-${entry.id}'),
                    entry: entry,
                    controller: widget.controller,
                    preferences: widget.preferences,
                    loadKnowledge: widget.loadKnowledge,
                    anchors: _anchors,
                    visible: _isVisible(entry),
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
    required this.controller,
    required this.child,
    required this.reduceMotion,
    required this.onCreated,
    required this.onDisposed,
  }) : super(
         key: ValueKey(entry.id),
         name: entry.overlay?.name ?? entry.page.name,
       );

  final GalleryRouteEntry entry;
  final GalleryController controller;
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
        reverseCurve: GalleryMotion.accelerate.flipped,
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
      translation: Offset((isFirst ? 0 : 1 - primary) - .06 * secondary, 0),
      child: RepaintBoundary(child: interactive(child)),
    );
  }
}

class _GalleryPopupRoute extends PopupRoute<void> with _GalleryPredictiveRoute {
  _GalleryPopupRoute(_GalleryRoutePage page) : super(settings: page);
  final _dragVisibility = ValueNotifier(1.0);
  bool _menuEntered = false;
  bool get _menu => [
    GalleryOverlay.cardMenu,
    GalleryOverlay.source,
    GalleryOverlay.mode,
  ].contains(configuration.entry.overlay);
  bool get _sheet => configuration.entry.overlay?.isBottomSheet ?? false;
  @override
  bool get barrierDismissible => true;
  @override
  Color get barrierColor => _menu
      ? Colors.transparent
      : _sheet
      ? GalleryMotion.sheetScrim
      : const Color(0x99000000);
  @override
  String get barrierLabel => _menu ? '关闭菜单' : '关闭弹层';
  @override
  Curve get barrierCurve => _GalleryMotion.curve;
  @override
  Widget buildModalBarrier() => AnimatedBuilder(
    animation: Listenable.merge([animation!, _dragVisibility]),
    builder: (context, _) => ModalBarrier(
      color: Color.lerp(
        Colors.transparent,
        barrierColor,
        _dragVisibility.value *
            (configuration.reduceMotion ? 1 : motionProgress(animation!)),
      ),
      dismissible: barrierDismissible,
      onDismiss: () {
        if (_faceCropping) {
          configuration.controller.exitFaceCrop();
        } else {
          navigator?.maybePop();
        }
      },
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
      : GalleryDialogMotion.enter;
  @override
  Duration get reverseTransitionDuration => configuration.reduceMotion
      ? Duration.zero
      : _menu
      ? _GalleryMotion.menuBack
      : _sheet
      ? _GalleryMotion.sheetBack
      : GalleryDialogMotion.exit;
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
      // While the cropper is open the route stays put: the predictive gesture
      // crossfades cropper → face sheet inside the page instead of sliding.
      if (_cropGesture || _faceCropping) return content;
      // Keep the sheet's painted content reusable while it tracks the gesture
      // or slides away, matching the page route's boundary placement.
      return FractionalTranslation(
        translation: Offset(0, 1 - value),
        child: Opacity(
          opacity: const Interval(0, .35).transform(value),
          child: RepaintBoundary(child: content),
        ),
      );
    }
    if (_menu) return content;
    return Opacity(
      opacity: value,
      child: Transform.scale(
        scale: lerpDouble(GalleryDialogMotion.initialScale, 1, value)!,
        child: content,
      ),
    );
  }

  bool get _faceCropping =>
      configuration.entry.overlay == GalleryOverlay.face &&
      configuration.controller.faceCrop?.editing == true;

  /// True from the start of a predictive gesture that began in crop mode
  /// until the route animation settles, so committing the gesture (which
  /// exits crop mode) never switches mid-flight to the sheet slide.
  bool _cropGesture = false;

  void _cropGestureSettled(AnimationStatus status) {
    if (status == AnimationStatus.completed ||
        status == AnimationStatus.dismissed) {
      _cropGesture = false;
      controller?.removeStatusListener(_cropGestureSettled);
    }
  }

  @override
  void handleStartBackGesture({double progress = 1}) {
    if (_faceCropping) {
      _cropGesture = true;
      controller?.addStatusListener(_cropGestureSettled);
    }
    super.handleStartBackGesture(progress: progress);
  }

  @override
  void handleCommitBackGesture() {
    if (_cropGesture && _faceCropping) {
      configuration.controller.exitFaceCrop();
      if (isCurrent) {
        controller?.animateTo(
          1,
          duration: transitionDuration * (1 - controller!.value),
          curve: _GalleryMotion.curve,
        );
      }
      _settleGesture();
      return;
    }
    super.handleCommitBackGesture();
  }

  @override
  void dispose() {
    controller?.removeStatusListener(_cropGestureSettled);
    super.dispose();
    _dragVisibility.dispose();
  }
}

class _GalleryMainTransition extends StatefulWidget {
  const _GalleryMainTransition({
    required this.page,
    required this.builder,
    required this.reduceMotion,
  });
  final GalleryPage page;
  final Widget Function(GalleryPage) builder;
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
  double get _value => _GalleryMotion.curve.transform(_animation.value);

  @override
  void initState() {
    super.initState();
    _slots[widget.page] = _GalleryMainSlot(widget.builder(widget.page), 1, 1);
  }

  @override
  void didUpdateWidget(_GalleryMainTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reduceMotion) {
      _animation.stop();
      _slots.clear();
      _slots[widget.page] = _GalleryMainSlot(widget.builder(widget.page), 1, 1);
      _animation.value = 1;
    } else if (widget.page != oldWidget.page) {
      final progress = _value;
      _animation.stop();
      for (final item in _slots.entries) {
        item.value.begin = item.value.position(progress);
        item.value.end = 0;
      }
      final incoming = _slots.putIfAbsent(
        widget.page,
        () => _GalleryMainSlot(widget.builder(widget.page), 0, 1),
      );
      incoming.child = widget.builder(widget.page);
      incoming.end = 1;
      _animation.forward(from: 0);
    } else {
      for (final item in _slots.entries) {
        item.value.child = widget.builder(item.key);
      }
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
            Opacity(
              key: ValueKey(item.key),
              opacity: item.value.position(_value),
              child: IgnorePointer(
                ignoring: item.key != widget.page,
                child: ExcludeFocus(
                  excluding: item.key != widget.page,
                  child: ExcludeSemantics(
                    excluding: item.key != widget.page,
                    child: TickerMode(
                      enabled: item.key == widget.page,
                      child: RepaintBoundary(
                        child: ColoredBox(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          child: item.value.child,
                        ),
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
        value: 1,
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed && !widget.open && mounted) {
          setState(() => _content = null);
        }
      });
  Widget? _content;
  late double _from = widget.open ? 1 : 0;
  late double _to = _from;
  double _offsetFrom = 0;
  double _offsetTo = 0;
  Curve _curve = GalleryMotion.decelerate;
  double get _progress => _curve.transform(_animation.value);
  double get _reveal => lerpDouble(_from, _to, _progress)!;
  double get _offset => lerpDouble(_offsetFrom, _offsetTo, _progress)!;

  @override
  void initState() {
    super.initState();
    // Initialize against the initial open state, before didUpdateWidget can
    // receive the first expansion.
    _animation;
    _to;
  }

  @override
  void didUpdateWidget(_GalleryCollapse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reduceMotion) {
      _to = widget.open ? 1 : 0;
      _offsetTo = 0;
      _animation.value = 1;
    } else if (widget.open != oldWidget.open) {
      final offset = _offset;
      _from = _reveal;
      _to = widget.open ? 1 : 0;
      _offsetFrom = widget.open && _from == 0
          ? GalleryMotion.expandDistance
          : offset;
      _offsetTo = widget.open ? 0 : -GalleryMotion.micro;
      _curve = widget.open
          ? GalleryMotion.decelerate
          : GalleryMotion.accelerate;
      _animation.duration =
          (widget.open ? GalleryMotion.expand : GalleryMotion.collapse) *
          (_to - _from).abs();
      _animation.forward(from: 0);
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
    if (_content == null || !widget.open && _reveal == 0) {
      return const SizedBox.shrink();
    }
    return ClipRect(
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) => Align(
          alignment: Alignment.topCenter,
          heightFactor: _reveal,
          child: Opacity(
            opacity: _reveal,
            child: Transform.translate(
              offset: Offset(0, _offset),
              child: child,
            ),
          ),
        ),
        child: IgnorePointer(
          ignoring: !widget.open,
          child: ExcludeFocus(
            excluding: !widget.open,
            child: ExcludeSemantics(
              excluding: !widget.open,
              child: RepaintBoundary(child: _content!),
            ),
          ),
        ),
      ),
    );
  }
}
