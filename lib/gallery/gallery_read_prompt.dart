part of 'gallery_app.dart';

/// One mounted stage at a time: finish the exit before replacing its content.
/// Keeping the displayed snapshot also keeps outgoing controls and captions in
/// the same phase, including when a read completes during an interrupted exit.
class _GalleryReadFlow extends StatefulWidget {
  const _GalleryReadFlow({
    required this.state,
    required this.hasRead,
    required this.builder,
  });
  final GalleryReadState state;
  final bool hasRead;
  final Widget Function(GalleryReadState, bool) builder;

  @override
  State<_GalleryReadFlow> createState() => _GalleryReadFlowState();
}

class _GalleryReadFlowState extends State<_GalleryReadFlow>
    with SingleTickerProviderStateMixin {
  late GalleryReadState _displayed = widget.state;
  late bool _hasRead = widget.hasRead;
  late final _visibility = AnimationController(vsync: this, value: 1)
    ..addStatusListener(_onVisibilityStatus);
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    if (_reduced) _showImmediately();
  }

  @override
  void didUpdateWidget(_GalleryReadFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state ||
        oldWidget.hasRead != widget.hasRead) {
      if (_reduced) {
        _showImmediately();
      } else {
        _transition();
      }
    }
  }

  void _showImmediately() {
    _visibility.stop(canceled: true);
    _displayed = widget.state;
    _hasRead = widget.hasRead;
    if (_visibility.value != 1) _visibility.value = 1;
  }

  void _transition() {
    if (_visibility.value == 0) {
      _showNext();
    } else {
      _visibility.animateBack(
        0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeInCubic,
      );
    }
  }

  void _onVisibilityStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted && !_reduced) {
      _showNext();
    }
  }

  void _showNext() {
    setState(() {
      _displayed = widget.state;
      _hasRead = widget.hasRead;
    });
    _visibility.animateTo(
      1,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _visibility.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = AnimatedBuilder(
      animation: _visibility,
      builder: (context, child) => IgnorePointer(
        ignoring: _visibility.value < .99 || _displayed != widget.state,
        child: ExcludeSemantics(
          excluding: _visibility.value < .5 || _displayed != widget.state,
          child: FadeTransition(
            key: const ValueKey('home-read-stage'),
            opacity: _visibility,
            child: Transform.translate(
              offset: Offset(0, 8 * (1 - _visibility.value)),
              child: child,
            ),
          ),
        ),
      ),
      child: widget.builder(_displayed, _hasRead),
    );
    return _reduced
        ? SizedBox(key: const ValueKey('home-read-layout'), child: content)
        : AnimatedSize(
            key: const ValueKey('home-read-layout'),
            duration: _GalleryMotion.readResult,
            curve: Curves.easeInOutCubicEmphasized,
            alignment: Alignment.topCenter,
            child: content,
          );
  }
}

/// The illustration stays mounted as the first step becomes the reading step.
class _GalleryReadPrompt extends StatefulWidget {
  const _GalleryReadPrompt({
    required this.reading,
    required this.failed,
    required this.compact,
  });
  final bool reading, failed;
  final bool compact;

  @override
  State<_GalleryReadPrompt> createState() => _GalleryReadPromptState();
}

class _GalleryReadPromptState extends State<_GalleryReadPrompt>
    with TickerProviderStateMixin {
  late final _morph = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
    value: widget.reading ? 1 : 0,
  );
  late final _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );
  late final _failure = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
    value: widget.failed ? 1 : 0,
  );
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _syncAnimation();
  }

  @override
  void didUpdateWidget(_GalleryReadPrompt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reading != oldWidget.reading ||
        widget.failed != oldWidget.failed) {
      if (widget.failed && !oldWidget.failed) _failure.value = 0;
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    final target = widget.reading || widget.failed ? 1.0 : 0.0;
    if (_reduceMotion) {
      _morph.value = target;
    } else if (_morph.value != target) {
      _morph.animateTo(target, curve: Curves.easeInOutCubicEmphasized);
    }
    if (widget.reading && !_reduceMotion) {
      if (!_loop.isAnimating) _loop.repeat();
    } else {
      _loop.stop();
      if (!widget.failed) _loop.value = 0;
    }
    if (_reduceMotion) {
      _failure.value = widget.failed ? 1 : 0;
    } else if (widget.failed) {
      _failure.forward();
    } else {
      _failure.value = 0;
    }
  }

  @override
  void dispose() {
    _morph.dispose();
    _loop.dispose();
    _failure.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GalleryTokens>()!;
    final title = widget.reading
        ? '把交通卡贴近手机背面'
        : widget.failed
        ? '未能读到卡片'
        : '贴卡，了解你的每一次出行';
    final subtitle = widget.reading
        ? '正在读取余额与行程\n请保持贴卡，直到读取完成'
        : widget.failed
        ? '调整卡片位置后再试一次'
        : '支持交通联合、城市一卡通\n及部分 FeliCa 卡片';
    return Column(
      key: const ValueKey('home-read-prompt'),
      children: [
        RepaintBoundary(
          child: ExcludeSemantics(
            child: AnimatedBuilder(
              animation: Listenable.merge([_morph, _loop, _failure]),
              builder: (context, _) {
                final morph = _morph.value;
                final phase = _loop.value;
                final approach = _reduceMotion
                    ? 1.0
                    : phase < .4
                    ? Curves.easeInOutCubicEmphasized.transform(phase / .4)
                    : phase < .78
                    ? 1.0
                    : 1 - Curves.easeInOutCubic.transform((phase - .78) / .22);
                return SizedBox(
                  key: const ValueKey('home-read-illustration'),
                  width: 240,
                  height: widget.compact ? 96 : 152,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: 240,
                      height: 152,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Opacity(
                            opacity: 1 - morph,
                            child: Transform.scale(
                              scale: 1 - .16 * morph,
                              child: Container(
                                width: 88,
                                height: 88,
                                decoration: BoxDecoration(
                                  color: t.tone,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  widget.failed
                                      ? Icons.contactless_outlined
                                      : Icons.nfc_rounded,
                                  size: 40,
                                  color: t.onTone,
                                ),
                              ),
                            ),
                          ),
                          Opacity(
                            opacity: morph,
                            child: Transform.translate(
                              offset: Offset(
                                -12 * morph +
                                    math.sin(_failure.value * math.pi * 4) *
                                        (1 - _failure.value) *
                                        5,
                                12 * (1 - morph),
                              ),
                              child: Container(
                                key: const ValueKey('home-read-phone'),
                                width: 64,
                                height: 116,
                                decoration: BoxDecoration(
                                  color: t.surface,
                                  borderRadius: BorderRadius.circular(17),
                                  border: Border.all(color: t.onTone, width: 2),
                                ),
                                child: Stack(
                                  children: [
                                    Positioned(
                                      top: 9,
                                      left: 9,
                                      child: Container(
                                        width: 9,
                                        height: 18,
                                        decoration: BoxDecoration(
                                          color: t.onTone,
                                          borderRadius: BorderRadius.circular(
                                            5,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Center(
                                      child: Icon(
                                        Icons.nfc_rounded,
                                        size: 24,
                                        color: t.onTone,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Opacity(
                            opacity: morph,
                            child: Transform.translate(
                              key: const ValueKey('home-read-card-position'),
                              offset: Offset(
                                64 - 44 * approach,
                                27 - 13 * approach + 14 * (1 - morph),
                              ),
                              child: Transform.rotate(
                                angle: -.32 + .2 * approach,
                                child: Container(
                                  width: 82,
                                  height: 52,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: t.action,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: t.onAction),
                                    boxShadow: t.shadows(GalleryElevation.card),
                                  ),
                                  alignment: Alignment.centerLeft,
                                  child: Icon(
                                    Icons.contactless_outlined,
                                    color: t.onAction,
                                    size: 25,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (widget.failed)
                            Positioned(
                              right: 48,
                              bottom: 12,
                              child: Transform.scale(
                                scale: Curves.easeOutCubic.transform(
                                  _failure.value,
                                ),
                                child: Container(
                                  key: const ValueKey('home-read-failure'),
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: t.dangerContainer,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: t.danger,
                                      width: 2,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.close_rounded,
                                    color: t.onDangerContainer,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        if (widget.reading)
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 12, 40, 0),
            child: TickerMode(
              enabled: !_reduceMotion,
              child: LinearProgressIndicator(
                key: const ValueKey('home-read-progress'),
                minHeight: 4,
                borderRadius: BorderRadius.circular(2),
                color: t.action,
                backgroundColor: t.tone,
                semanticsLabel: '正在读取卡片',
                semanticsValue: '读取中',
              ),
            ),
          )
        else
          const SizedBox(height: 16),
        const SizedBox(height: 18),
        Semantics(
          liveRegion: true,
          child: Column(
            key: ValueKey(title),
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: GalleryTypography.section.copyWith(color: t.text),
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: GalleryTypography.label.copyWith(
                  color: widget.failed ? t.warn : t.muted,
                  fontWeight: FontWeight.w400,
                  height: 22 / 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
