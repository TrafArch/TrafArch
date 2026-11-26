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
        duration: _GalleryMotion.content,
        curve: _GalleryMotion.accelerate,
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
      duration: _GalleryMotion.slow,
      curve: _GalleryMotion.decelerate,
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
            curve: _GalleryMotion.readCurve,
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
    required this.nfcMessage,
    required this.noNfc,
    required this.felicaSupported,
    required this.failureMessage,
    this.progress,
  });
  final bool reading, failed;
  final bool compact;
  final String? nfcMessage;
  final bool noNfc;
  final bool? felicaSupported;
  final String? failureMessage;

  /// Reader percentage (0–100) of the attempt in flight. Null keeps the loop
  /// animation: the card has not been discovered yet, so there is no honest
  /// percentage to show.
  final int? progress;

  @override
  State<_GalleryReadPrompt> createState() => _GalleryReadPromptState();
}

class _GalleryReadPromptState extends State<_GalleryReadPrompt>
    with TickerProviderStateMixin {
  late final _morph = AnimationController(
    vsync: this,
    duration: _GalleryMotion.readMorph,
    value: widget.reading ? 1 : 0,
  );
  late final _loop = AnimationController(
    vsync: this,
    duration: _GalleryMotion.readLoop,
  );
  late final _failure = AnimationController(
    vsync: this,
    duration: _GalleryMotion.readFailure,
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
      _morph.animateTo(target, curve: _GalleryMotion.readCurve);
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
    final percent = widget.progress?.clamp(0, 100).toInt();
    final fraction = percent == null ? null : percent / 100;
    final title =
        widget.nfcMessage ??
        (widget.reading
            ? '把交通卡贴近手机背面'
            : widget.failed
            ? '未能读到卡片'
            : '贴卡，了解你的每一次出行');
    final subtitle = widget.noNfc
        ? '此设备无法读取实体交通卡，仍可查看已有记录'
        : widget.nfcMessage != null
        ? '打开 NFC 后即可读取实体交通卡'
        : widget.reading
        ? '正在读取余额与行程\n请保持贴卡，直到读取完成'
        : widget.failed
        ? widget.failureMessage ?? '调整卡片位置后再试一次'
        : switch (widget.felicaSupported) {
            true => '支持交通联合、城市一卡通\n及部分 FeliCa 卡片',
            false => '支持交通联合、城市一卡通\n此设备不支持 FeliCa 识别',
            null => '支持交通联合、城市一卡通\n无法确认此设备是否支持 FeliCa 识别',
          };
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
                    ? _GalleryMotion.readCurve.transform(phase / .4)
                    : phase < .78
                    ? 1.0
                    : 1 -
                          _GalleryMotion.standard.transform(
                            (phase - .78) / .22,
                          );
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
                                  widget.noNfc
                                      ? Icons.portable_wifi_off_rounded
                                      : widget.failed
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
                                scale: _GalleryMotion.decelerate.transform(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The caption row is reserved even before the first real
                // percentage, so null → value does not move the bar.
                SizedBox(
                  height: 18,
                  child: Align(
                    alignment: Alignment.centerRight,
                    // The bar announces the same percentage; this caption is
                    // the visual copy only.
                    child: ExcludeSemantics(
                      child: Text(
                        percent == null ? '' : '$percent%',
                        key: const ValueKey('home-read-percent'),
                        style: GalleryTypography.caption.copyWith(
                          color: t.muted,
                        ),
                      ),
                    ),
                  ),
                ),
                TickerMode(
                  enabled: !_reduceMotion,
                  child: LinearProgressIndicator(
                    key: const ValueKey('home-read-progress'),
                    // A reported percentage is real progress; until the card is
                    // discovered the bar keeps its indeterminate loop.
                    value: fraction,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(2),
                    color: t.action,
                    backgroundColor: t.tone,
                    semanticsLabel: '正在读取卡片',
                    semanticsValue: percent == null ? '读取中' : '$percent%',
                  ),
                ),
              ],
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
