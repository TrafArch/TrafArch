part of 'gallery_app.dart';

/// Crop geometry relative to the centered-cover baseline (spec 2.4 §5.4).
/// [GalleryFaceCrop.scale] multiplies the cover fit; offsets are fractions of
/// the overflow margin so the same values render identically at any size.
({double width, double height, double dx, double dy}) _faceCropLayout(
  Size window,
  Size source,
  GalleryFaceCrop crop,
) {
  final cover = math.max(
    window.width / source.width,
    window.height / source.height,
  );
  final scale = crop.scale.clamp(1.0, 4.0);
  final width = source.width * cover * scale;
  final height = source.height * cover * scale;
  final overX = math.max(0.0, (width - window.width) / 2);
  final overY = math.max(0.0, (height - window.height) / 2);
  return (
    width: width,
    height: height,
    dx: crop.offsetX.clamp(-1.0, 1.0) * overX,
    dy: crop.offsetY.clamp(-1.0, 1.0) * overY,
  );
}

/// The cropped face image layer shared by the detail face, wallet rows and
/// the cropper previews so all of them render one set of parameters the same
/// way. The image always covers the window; no blank edge can appear.
class _FaceCropImage extends StatelessWidget {
  const _FaceCropImage({required this.card, this.crop});

  final GalleryCard card;
  final GalleryFaceCrop? crop;

  @override
  Widget build(BuildContext context) {
    final bytes = card.image;
    if (bytes == null) return const SizedBox.shrink();
    final source = card.imageSize;
    final effective = crop ?? card.detailCrop;
    return LayoutBuilder(
      builder: (context, constraints) {
        final window = constraints.biggest;
        Widget image;
        if (source == null || source.width <= 0 || source.height <= 0) {
          image = Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
        } else {
          final layout = _faceCropLayout(window, source, effective);
          image = Stack(
            children: [
              Positioned(
                left: (window.width - layout.width) / 2 + layout.dx,
                top: (window.height - layout.height) / 2 + layout.dy,
                width: layout.width,
                height: layout.height,
                child: Image.memory(
                  bytes,
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                ),
              ),
            ],
          );
        }
        return ClipRect(
          child: ColorFiltered(
            colorFilter: const ColorFilter.mode(
              Color(0x99070c16),
              BlendMode.darken,
            ),
            child: image,
          ),
        );
      },
    );
  }
}

/// Claims pointers as soon as they land inside a crop canvas so the page's
/// vertical scroll never steals an image drag (spec 2.4 §7.3).
class _CropScaleRecognizer extends ScaleGestureRecognizer {
  @override
  void addPointer(PointerDownEvent event) {
    super.addPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

/// One independent crop region: the real card surface is the crop window,
/// and gestures on it only change this region's parameters.
class _FaceCropRegion extends StatefulWidget {
  const _FaceCropRegion({
    super.key,
    required this.title,
    required this.crop,
    required this.source,
    required this.onChanged,
    required this.child,
  });

  final String title;
  final GalleryFaceCrop crop;
  final Size source;
  final ValueChanged<GalleryFaceCrop> onChanged;
  final Widget child;

  @override
  State<_FaceCropRegion> createState() => _FaceCropRegionState();
}

class _FaceCropRegionState extends State<_FaceCropRegion> {
  final _surfaceKey = GlobalKey();
  GalleryFaceCrop? _start;
  Offset _drag = Offset.zero;
  bool _active = false;

  Size get _window {
    final box = _surfaceKey.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize ? box.size : Size.zero;
  }

  void _onStart(ScaleStartDetails details) {
    _start = widget.crop;
    _drag = Offset.zero;
    setState(() => _active = true);
  }

  void _onUpdate(ScaleUpdateDetails details) {
    final start = _start;
    final window = _window;
    if (start == null || window.isEmpty) return;
    _drag += details.focalPointDelta;
    final scale = (start.scale * details.scale).clamp(1.0, 4.0);
    final scaled = _faceCropLayout(
      window,
      widget.source,
      start.copyWith(scale: scale),
    );
    final base = _faceCropLayout(window, widget.source, start);
    final overX = math.max(0.0, (scaled.width - window.width) / 2);
    final overY = math.max(0.0, (scaled.height - window.height) / 2);
    final startOverX = math.max(0.0, (base.width - window.width) / 2);
    final startOverY = math.max(0.0, (base.height - window.height) / 2);
    final px = (start.offsetX * startOverX + _drag.dx).clamp(-overX, overX);
    final py = (start.offsetY * startOverY + _drag.dy).clamp(-overY, overY);
    widget.onChanged(
      widget.crop.copyWith(
        scale: scale,
        offsetX: overX > 0 ? px / overX : 0,
        offsetY: overY > 0 ? py / overY : 0,
      ),
    );
  }

  void _onEnd(ScaleEndDetails details) {
    setState(() => _active = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<GalleryTokens>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.title,
          style: GalleryTypography.label.copyWith(
            color: t.text,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: _active ? t.onTone : t.line,
              width: _active ? 2 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(23),
            child: RawGestureDetector(
              gestures: {
                _CropScaleRecognizer:
                    GestureRecognizerFactoryWithHandlers<_CropScaleRecognizer>(
                      () => _CropScaleRecognizer(),
                      (recognizer) => recognizer
                        ..onStart = _onStart
                        ..onUpdate = _onUpdate
                        ..onEnd = _onEnd,
                    ),
              },
              child: KeyedSubtree(key: _surfaceKey, child: widget.child),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                '拖动图片 · 双指缩放',
                style: GalleryTypography.caption.copyWith(color: t.muted),
              ),
            ),
            TextButton(
              onPressed: () => widget.onChanged(const GalleryFaceCrop()),
              child: const Text('恢复默认'),
            ),
          ],
        ),
      ],
    );
  }
}

extension _GalleryFaceCropper on _GalleryViewState {
  /// The face overlay hosts both the change-face sheet and the cropper as
  /// internal states of one route (spec 2.4 §3.2); no second sheet is pushed.
  Widget _faceOverlay() {
    final session = c.faceCrop;
    final cropping = session?.editing ?? false;
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = math.max(
          0.0,
          constraints.maxHeight - MediaQuery.paddingOf(context).bottom,
        );
        final gap = available < 240 ? 0.0 : (cropping ? 8.0 : 16.0);
        final route = ModalRoute.of(context);
        Widget faceBody() => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: _text(
                    '更换卡面',
                    role: GalleryTypography.section,
                    weight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: c.back,
                  icon: const Icon(Icons.close_rounded, size: 21),
                ),
              ],
            ),
            _gap(12),
            _faceSheet(),
          ],
        );

        Widget sheetBody() => SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: faceBody(),
        );

        Widget content;
        if (session != null && cropping) {
          final animation =
              route?.animation ?? const AlwaysStoppedAnimation(1.0);
          content = AnimatedBuilder(
            animation: animation,
            builder: (context, _) {
              final value = animation.value;
              if (value >= 1) return _faceCropper(session);
              // Predictive back crossfades the cropper back into the sheet
              // without moving or flickering the route itself.
              return Stack(
                children: [
                  Opacity(
                    opacity: 1 - value,
                    child: IgnorePointer(child: sheetBody()),
                  ),
                  Opacity(opacity: value, child: _faceCropper(session)),
                ],
              );
            },
          );
        } else {
          content = sheetBody();
        }
        return Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            top: true,
            child: Padding(
              padding: EdgeInsets.fromLTRB(0, gap, 0, 0),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 520,
                  maxHeight: math.max(
                    0.0,
                    cropping
                        ? available - gap
                        : math.min(available * .9, available - gap),
                  ),
                ),
                child: FocusScope(
                  autofocus: true,
                  child: Focus(
                    autofocus: true,
                    skipTraversal: true,
                    onKeyEvent: (_, event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.escape) {
                        c.back();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: FocusTraversalGroup(
                      child: Semantics(
                        scopesRoute: true,
                        namesRoute: true,
                        label: cropping ? '调整图片' : '更换卡面',
                        explicitChildNodes: true,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(24),
                            ),
                            boxShadow: t.shadows(GalleryElevation.modal),
                          ),
                          child: Material(
                            color: t.raised,
                            shape: RoundedRectangleBorder(
                              side: BorderSide(color: t.line),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(24),
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: AnimatedSize(
                              duration: _reduceMotion
                                  ? Duration.zero
                                  : _GalleryMotion.sheet,
                              curve: _GalleryMotion.curve,
                              alignment: Alignment.topCenter,
                              child: content,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _faceCropper(GalleryFaceCropSession session) {
    final card = c.cards.firstWhere(
      (card) => card.id == session.cardId,
      orElse: () => c.current,
    );
    final preview = GalleryCard.preview(
      card,
      image: session.image,
      imageSize: session.sourceSize,
      detailCrop: session.detail,
      listCrop: session.list,
    );
    final balance = _balancePresentation(preview);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 8, 0),
          child: Row(
            children: [
              IconButton(
                tooltip: '返回更换卡面',
                onPressed: c.exitFaceCrop,
                icon: const Icon(Icons.arrow_back_rounded, size: 21),
              ),
              Expanded(
                child: _text(
                  '调整图片',
                  role: GalleryTypography.section,
                  weight: FontWeight.w600,
                ),
              ),
              TextButton(
                onPressed: () => _confirmResetAllCrops(),
                child: const Text('重置全部'),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: t.line),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _text(
                  '分别调整图片在两个页面中的显示范围',
                  role: GalleryTypography.caption,
                  color: t.muted,
                ),
                if (session.sourceSize.width < 600) ...[
                  _gap(6),
                  _text(
                    '图片分辨率较低，放大后可能不够清晰',
                    role: GalleryTypography.caption,
                    color: t.warn,
                  ),
                ],
                _gap(16),
                LayoutBuilder(
                  builder: (context, box) {
                    final layout = _DetailCardLayout(
                      context,
                      preview,
                      balance,
                      box.maxWidth,
                    );
                    return _FaceCropRegion(
                      key: const ValueKey('face-crop-region-detail'),
                      title: '卡片详情页',
                      crop: session.detail,
                      source: session.sourceSize,
                      onChanged: (crop) => c.updateFaceCrop(detail: crop),
                      child: _GalleryDetailFace(
                        card: preview,
                        balance: balance,
                        layout: layout,
                      ),
                    );
                  },
                ),
                _gap(14),
                _FaceCropRegion(
                  key: const ValueKey('face-crop-region-list'),
                  title: '卡包列表页',
                  crop: session.list,
                  source: session.sourceSize,
                  onChanged: (crop) => c.updateFaceCrop(list: crop),
                  child: _walletCardSurface(preview, id: 'crop-list'),
                ),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
            child: SizedBox(
              width: double.infinity,
              child: _button('完成', c.exitFaceCrop, primary: true),
            ),
          ),
        ),
      ],
    );
  }

  void _confirmResetAllCrops() {
    _toast(
      '重置两个区域的裁切？',
      type: GalleryFeedbackType.info,
      actionLabel: '重置',
      onAction: () => c.updateFaceCrop(
        detail: const GalleryFaceCrop(),
        list: const GalleryFaceCrop(),
      ),
    );
  }

  /// The outer sheet's 完成 is the only place that commits the image and both
  /// crop parameter sets onto the card (spec 2.4 §8.2).
  void _commitFaceSheet(GalleryFaceCropSession? session) {
    if (session != null) {
      final card = c.cards.firstWhere(
        (card) => card.id == session.cardId,
        orElse: () => c.current,
      );
      c.update(() {
        card.image = session.image;
        card.imageSize = session.sourceSize;
        card.detailCrop = session.detail;
        card.listCrop = session.list;
        c.faceCrop = null;
      }, '保存卡面图片');
    }
    c.back();
  }

  Widget _walletAmount(GalleryCard card, {double? numberWidth}) {
    final value = _balancePresentation(card);
    final numberStyle = GalleryTypography.lead.copyWith(
      inherit: false,
      color: _faceForeground(card),
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final currencyStyle = GalleryTypography.caption.copyWith(
      inherit: false,
      color: _faceForeground(card, secondary: true),
    );
    double measure(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final width = painter.width.ceilToDouble() + 2;
      painter.dispose();
      return width;
    }

    final unitWidth = value.currencyLabel.isEmpty
        ? 0.0
        : measure(value.currencyLabel, currencyStyle);
    final resolvedNumberWidth =
        numberWidth ?? measure(value.number, numberStyle);
    final amountWidth =
        resolvedNumberWidth + (unitWidth > 0 ? unitWidth + 4 : 0);
    return Semantics(
      label: '余额，${value.displayText}',
      excludeSemantics: true,
      child: !value.known
          ? _text(
              value.displayText,
              role: GalleryTypography.label,
              color: _faceForeground(card, secondary: true),
            )
          : FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: amountWidth,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    if (unitWidth > 0) ...[
                      SizedBox(
                        width: unitWidth,
                        child: Text(
                          value.currencyLabel,
                          key: ValueKey('wallet-currency-${card.id}'),
                          maxLines: 1,
                          softWrap: false,
                          textAlign: TextAlign.left,
                          style: currencyStyle,
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    SizedBox(
                      width: resolvedNumberWidth,
                      child: Text(
                        value.number,
                        key: ValueKey('wallet-number-${card.id}'),
                        maxLines: 1,
                        softWrap: false,
                        textAlign: TextAlign.left,
                        style: numberStyle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  /// The real wallet row surface, shared by the wallet list, the cropper's
  /// list region and the face sheet preview so the crop window always matches
  /// the component that renders it (spec 2.4 §6.2).
  Widget _walletCardSurface(
    GalleryCard card, {
    required String id,
    double? numberWidth,
    Widget? trailing,
    VoidCallback? onTap,
  }) => Container(
    key: ValueKey('$id-card-${card.id}'),
    clipBehavior: Clip.antiAlias,
    decoration: card.image != null
        ? _faceDecoration(card, radius: 24)
        : BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: t.line.withValues(alpha: .65)),
          ),
    child: Stack(
      children: [
        if (card.image != null)
          Positioned.fill(
            child: _FaceCropImage(card: card, crop: card.listCrop),
          ),
        Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _cardBadge(card, id: id),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _text(
                              card.name,
                              role: GalleryTypography.card,
                              color: card.image != null
                                  ? _faceForeground(card)
                                  : t.text,
                            ),
                            _gap(4),
                            _walletAmount(card, numberWidth: numberWidth),
                          ],
                        ),
                      ),
                      if (trailing != null) ...[
                        const SizedBox(width: 8),
                        trailing,
                      ],
                    ],
                  ),
                  _cardMetadata(card, id: id),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
