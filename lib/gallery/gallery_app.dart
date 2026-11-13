import 'dart:async';
import 'dart:io' show File;
import 'dart:math' as math;
import 'dart:ui' show ImageFilter, ImageByteFormat, instantiateImageCodec;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/app_info.dart';
import '../features/trips/journey_transport_icon.dart';
import '../features/trips/trip_filters.dart';
import '../platform/browser/feedback_browser.dart';
import '../platform/qr/qr_image_picker.dart';
import '../shared/app_support.dart';
import 'gallery_controller.dart';
import 'gallery_balance_presentation.dart';
import 'gallery_data.dart';
import 'gallery_theme.dart';
import 'gallery_design.dart';
import 'gallery_layout.dart';
import 'gallery_preferences.dart';
import 'gallery_feedback.dart';
import 'gallery_spending.dart';

part 'gallery_components.dart';
part 'gallery_pages.dart';
part 'gallery_inspection.dart';
part 'gallery_overlays.dart';
part 'gallery_information.dart';
part 'gallery_navigation.dart';
part 'gallery_navigation_item.dart';
part 'gallery_read_prompt.dart';
part 'gallery_wallet_item.dart';
part 'gallery_detail.dart';

class GalleryApp extends StatefulWidget {
  const GalleryApp({
    super.key,
    this.controller,
    this.onDisableBeta,
    this.openWebLink,
    this.openEmail,
    this.preferences,
  });
  final GalleryController? controller;
  final VoidCallback? onDisableBeta;
  final Future<void> Function(Uri)? openWebLink;
  final Future<bool> Function(String)? openEmail;
  final GalleryPreferences? preferences;

  @override
  State<GalleryApp> createState() => _GalleryAppState();
}

class _GalleryAppState extends State<GalleryApp> {
  late final Future<GalleryController> _ready;
  GalleryController? _owned;
  late final GalleryPreferences _preferences;

  @override
  void initState() {
    super.initState();
    _preferences = widget.preferences ?? GalleryPreferences();
    _ready = widget.controller != null
        ? Future.value(widget.controller!)
        : GalleryData.load().then((data) {
            final controller = GalleryController(data);
            if (!mounted) {
              controller.dispose();
            } else {
              _owned = controller;
            }
            return controller;
          });
  }

  @override
  void dispose() {
    _owned?.dispose();
    if (widget.preferences == null) _preferences.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<GalleryController>(
    future: _ready,
    builder: (context, snapshot) {
      final c = snapshot.data;
      if (c == null) {
        return MaterialApp(
          home: Scaffold(
            body: Center(
              child: snapshot.hasError
                  ? const Text('样例数据加载失败，请重新打开应用')
                  : const CircularProgressIndicator(),
            ),
          ),
        );
      }
      return AnimatedBuilder(
        animation: c,
        builder: (context, _) => _GallerySystemColors(
          builder: (lightDynamic, darkDynamic) => MaterialApp(
            title: 'TrafArch',
            debugShowCheckedModeBanner: false,
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            themeMode: c.themeMode,
            theme: GalleryTokens.from(
              c.data,
              false,
              c.monet ? 'blue' : c.palette,
              dynamicScheme: c.monet ? lightDynamic : null,
            ).theme(),
            darkTheme: GalleryTokens.from(
              c.data,
              true,
              c.monet ? 'blue' : c.palette,
              dynamicScheme: c.monet ? darkDynamic : null,
            ).theme(),
            builder: (context, child) {
              final tokens = Theme.of(context).extension<GalleryTokens>()!;
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value:
                    (tokens.dark
                            ? SystemUiOverlayStyle.light
                            : SystemUiOverlayStyle.dark)
                        .copyWith(
                          statusBarColor: Colors.transparent,
                          systemNavigationBarColor: c.docked && c.isMainPage
                              ? tokens.dockedNavigationSurface
                              : tokens.bg,
                          systemNavigationBarDividerColor: Colors.transparent,
                        ),
                child: ColoredBox(
                  color: tokens.bg,
                  child: GalleryWindow(
                    child: GalleryFeedbackHost(
                      key: ValueKey(c.generation),
                      mainPage: c.isMainPage,
                      docked: c.docked,
                      child: child!,
                    ),
                  ),
                ),
              );
            },
            home: _GalleryNavigator(
              key: ValueKey(c.generation),
              controller: c,
              preferences: _preferences,
              onDisableBeta: widget.onDisableBeta,
              openWebLink: widget.openWebLink,
              openEmail: widget.openEmail,
            ),
          ),
        ),
      );
    },
  );
}

/// Refresh the wallpaper palette on returning from Android's wallpaper settings.
class _GallerySystemColors extends StatefulWidget {
  const _GallerySystemColors({required this.builder});
  final Widget Function(ColorScheme?, ColorScheme?) builder;
  @override
  State<_GallerySystemColors> createState() => _GallerySystemColorsState();
}

class _GallerySystemColorsState extends State<_GallerySystemColors>
    with WidgetsBindingObserver {
  final _builder = GlobalKey<DynamicColorBuilderState>();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _builder.currentState?.initPlatformState();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      DynamicColorBuilder(key: _builder, builder: widget.builder);
}

class _GalleryView extends StatefulWidget {
  const _GalleryView({
    super.key,
    required this.controller,
    required this.entry,
    required this.preferences,
    required this.anchors,
    this.onDisableBeta,
    this.openWebLink,
    this.openEmail,
  });
  final GalleryController controller;
  final GalleryRouteEntry entry;
  final GalleryPreferences preferences;
  final _GalleryAnchorRegistry anchors;
  final VoidCallback? onDisableBeta;
  final Future<void> Function(Uri)? openWebLink;
  final Future<bool> Function(String)? openEmail;
  @override
  State<_GalleryView> createState() => _GalleryViewState();
}

class _GalleryViewState extends State<_GalleryView> {
  GalleryController get c => widget.controller;
  GalleryTokens get t => Theme.of(context).extension<GalleryTokens>()!;
  GalleryRouteEntry get _entry => widget.entry;
  GalleryPage get _viewPage =>
      _buildingMainPage ??
      (_entry.kind == GalleryRouteKind.main ? c.mainPage : _entry.page);
  GalleryPage? _buildingMainPage;
  GalleryNavigationLayout get _navLayout =>
      GalleryNavigationLayout(MediaQuery.of(context), docked: c.docked);

  Widget _mainPage(GalleryPage page) {
    _buildingMainPage = page;
    try {
      return _page(page);
    } finally {
      _buildingMainPage = null;
    }
  }

  bool get _isMain => _entry.kind == GalleryRouteKind.main;
  GalleryCard get _selectedCard => c.cards.firstWhere(
    (card) => card.id == _entry.cardId,
    orElse: () => c.current,
  );
  GalleryPreferences get _preferences => widget.preferences;
  PageStorageBucket _bucket = PageStorageBucket();
  int _generation = -1;
  final _menuRoot = GlobalKey();
  Size _bodySize = Size.zero;
  bool get _compactHeight => _bodySize.height < 480;
  String? _openingLink;
  String? _linkError;
  bool _pickingFaceImage = false;
  String? _faceImageError;
  Set<String>? _walletCardIds;
  final Set<String> _walletArrivals = {};
  GallerySpendingSelection _spendingSelection =
      const GallerySpendingSelection.all();
  double _detailScrollDeficit = 0;
  double _detailMaxExtent = 0;
  double _detailShrinkDistance = 0;
  void _updateDetail(VoidCallback update) => setState(update);

  Future<void> _pickFaceImage() async {
    if (_pickingFaceImage) return;
    final card = _selectedCard;
    final generation = c.generation;
    bool active() =>
        mounted &&
        c.generation == generation &&
        c.navigationStack.last.id == _entry.id;
    setState(() {
      _pickingFaceImage = true;
      _faceImageError = null;
    });
    try {
      final path = await pickQrImageFromGallery();
      if (path == null || !active()) return;
      final file = File(path);
      if (await file.length() > 20 * 1024 * 1024) {
        if (active()) setState(() => _faceImageError = '图片过大，请选择小于 20 MB 的图片');
        return;
      }
      final codec = await instantiateImageCodec(
        await file.readAsBytes(),
        targetWidth: 1200,
        allowUpscaling: false,
      );
      try {
        final frame = await codec.getNextFrame();
        try {
          final data = await frame.image.toByteData(
            format: ImageByteFormat.png,
          );
          if (data != null && active()) {
            // The native picker clears its previous cache on each selection.
            c.update(
              () => card.image = data.buffer.asUint8List(
                data.offsetInBytes,
                data.lengthInBytes,
              ),
            );
          }
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } on MissingPluginException {
      if (active()) {
        setState(() => _faceImageError = '当前平台不支持系统相册，请在 Android 上选择图片');
      }
    } on TimeoutException {
      if (active()) setState(() => _faceImageError = '相册选择超时，请重试');
    } catch (_) {
      if (active()) setState(() => _faceImageError = '无法读取所选图片，请选择其他图片重试');
    } finally {
      if (mounted) setState(() => _pickingFaceImage = false);
    }
  }

  Future<List<LicenseEntry>>? _licenses;
  final _licenseParagraphs =
      Map<LicenseEntry, List<LicenseParagraph>>.identity();
  Future<void> _openContact(String value, {bool email = false}) async {
    if (_openingLink != null) return;
    final page = c.page;
    final generation = c.generation;
    setState(() {
      _openingLink = value;
      _linkError = null;
    });
    try {
      if (email) {
        final opened = await widget.openEmail?.call(value) ?? false;
        if (!opened) throw StateError('email unavailable');
      } else if (value == AppSupport.qqJoin) {
        // 与 1.x 一致：优先唤起 QQ 加群卡片，失败再打开邀请页。
        if (!await _openQqGroup()) {
          throw const FeedbackBrowserException('无法打开 QQ 或加群页，请安装 QQ 后重试。');
        }
      } else {
        final open = widget.openWebLink;
        if (open == null) throw StateError('browser unavailable');
        await open(Uri.parse(value));
      }
    } on FeedbackBrowserException catch (error) {
      if (mounted && c.page == page && c.generation == generation) {
        if (error.copiedToClipboard) {
          // 无可用浏览器时链接已复制到剪贴板，与 1.x 一样以气泡提示。
          _toast(error.message, type: GalleryFeedbackType.info);
        } else {
          setState(() => _linkError = error.message);
        }
      }
    } catch (_) {
      if (mounted && c.page == page && c.generation == generation) {
        setState(
          () => _linkError = email
              ? '无法打开邮件应用，请安装或启用邮件应用。'
              : '无法打开页面，请安装或启用浏览器后重试。',
        );
      }
    } finally {
      if (mounted) setState(() => _openingLink = null);
    }
  }

  Future<bool> _openQqGroup() async {
    final qqUrl = Uri(
      scheme: 'mqqapi',
      host: 'card',
      path: '/show_pslcard',
      queryParameters: {
        'src_type': 'internal',
        'version': '1',
        'uin': AppSupport.qqGroup,
        'card_type': 'group',
        'source': 'qrcode',
      },
    );
    for (final url in [qqUrl, Uri.parse(AppSupport.qqJoin)]) {
      try {
        if (await launchUrl(url, mode: LaunchMode.externalApplication)) {
          return true;
        }
      } catch (_) {
        // 未安装 QQ 或无法唤起时继续尝试邀请页。
      }
    }
    return false;
  }

  void _reloadLicenses() => setState(() {
    _licenses = null;
    _licenseParagraphs.clear();
  });

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  Widget _fade(Object identity, Widget child) => _GalleryFade(
    identity: identity,
    reduceMotion: _reduceMotion,
    child: child,
  );

  Widget _collapse(
    bool open,
    WidgetBuilder builder, {
    bool adaptiveDuration = false,
  }) => _GalleryCollapse(
    open: open,
    builder: builder,
    reduceMotion: _reduceMotion,
    adaptiveDuration: adaptiveDuration,
  );

  Widget _expandArrow(bool open, {double size = 18}) => AnimatedRotation(
    turns: open ? .25 : 0,
    duration: _reduceMotion ? Duration.zero : _GalleryMotion.expand,
    curve: _GalleryMotion.curve,
    child: Icon(Icons.chevron_right_rounded, size: size),
  );

  @override
  Widget build(BuildContext context) {
    if (_generation != c.generation) {
      _generation = c.generation;
      _bucket = PageStorageBucket();
    }
    widget.anchors.scheduleMeasure();
    if (_entry.overlay != null) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          bottom: false,
          child: Stack(
            key: _menuRoot,
            fit: StackFit.expand,
            children: _overlay(),
          ),
        ),
      );
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (t.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: c.docked && _isMain
                ? t.dockedNavigationSurface
                : t.bg,
            systemNavigationBarDividerColor: Colors.transparent,
          ),
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
        },
        child: Actions(
          actions: {
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (_) {
                c.back();
                return null;
              },
            ),
          },
          child: Scaffold(
            backgroundColor: _entry.overlay != null ? Colors.transparent : t.bg,
            resizeToAvoidBottomInset: true,
            body: SafeArea(
              bottom: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _bodySize = constraints.biggest;
                  return NotificationListener<ScrollNotification>(
                    onNotification: (_) {
                      widget.anchors.scheduleMeasure();
                      return false;
                    },
                    child: Stack(
                      key: _menuRoot,
                      fit: StackFit.expand,
                      children: [
                        if (_entry.overlay != null)
                          ..._overlay()
                        else ...[
                          GalleryReadingSurface(
                            child: PageStorage(
                              bucket: _bucket,
                              child: _isMain
                                  ? Column(
                                      children: [
                                        ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxHeight: math.max(
                                              0.0,
                                              _bodySize.height -
                                                  _navLayout.occupiedHeight -
                                                  72,
                                            ),
                                          ),
                                          child: SingleChildScrollView(
                                            key: const PageStorageKey(
                                              'gallery-main-header-scroll',
                                            ),
                                            primary: false,
                                            child: _mainHeader(),
                                          ),
                                        ),
                                        Expanded(
                                          child: _GalleryMainTransition(
                                            page: _viewPage,
                                            reduceMotion: _reduceMotion,
                                            builder: _mainPage,
                                          ),
                                        ),
                                      ],
                                    )
                                  : KeyedSubtree(
                                      key: ValueKey(_viewPage),
                                      child: _page(_viewPage),
                                    ),
                            ),
                          ),
                          if (_isMain)
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: RepaintBoundary(
                                key: const ValueKey('gallery-navigation'),
                                child: _navigation(),
                              ),
                            ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuAnchor(String id, Widget child) =>
      _GalleryMenuAnchor(registry: widget.anchors, id: id, child: child);

  Rect? _measureMenuBounds(String id) {
    final root = _menuRoot.currentContext?.findRenderObject();
    final rect = widget.anchors.boundsOf(id);
    if (rect != null && root is RenderBox && root.attached) {
      return root.globalToLocal(rect.topLeft) & rect.size;
    }
    return null;
  }

  Rect _menuBounds(String id) =>
      _measureMenuBounds(id) ?? const Rect.fromLTWH(16, 64, 36, 36);

  void _openDropdown(GalleryOverlay type, String anchor, {GalleryCard? card}) {
    final rect = _measureMenuBounds(anchor);
    c.showOverlay(type, card: card, anchor: rect, anchorId: anchor);
  }

  Widget _page(GalleryPage page) => switch (page) {
    GalleryPage.home => _home(),
    GalleryPage.trips => _trips(),
    GalleryPage.expert => _expert(),
    GalleryPage.cards => _cards(),
    GalleryPage.footprints => _footprints(),
    GalleryPage.detail => _detail(),
    GalleryPage.settings => _settings(),
    GalleryPage.knowledge => _knowledge(),
    GalleryPage.qr => _qr(),
    GalleryPage.scenes => _scenes(),
    GalleryPage.about => _about(),
    GalleryPage.feedback => _feedback(),
    GalleryPage.acknowledgements => _acknowledgements(),
    GalleryPage.licenses => _licensePage(),
  };

  Widget _list(
    List<Widget> children, {
    String? id,
    double? bottom,
    String? positionId,
  }) {
    final key = PageStorageKey(
      'gallery-${c.generation}-${id ?? '${_viewPage.name}-${_entry.qrView}'}',
    );
    final padding = EdgeInsets.fromLTRB(
      16,
      6,
      16,
      bottom ??
          (_isMain
              ? _navLayout.listBottom
              : 30 + MediaQuery.paddingOf(context).bottom),
    );
    if (positionId != null) {
      return _GalleryTabbedList(
        key: ValueKey('tabbed-${key.value}'),
        listKey: key,
        positionId: positionId,
        padding: padding,
        children: children,
      );
    }
    return ListView(key: key, padding: padding, children: children);
  }

  void _toast(
    String text, {
    GalleryFeedbackType type = GalleryFeedbackType.success,
    String? title,
    String? actionLabel,
    VoidCallback? onAction,
  }) => GalleryFeedbackHost.show(
    context,
    text,
    type: type,
    title: title,
    actionLabel: actionLabel,
    onAction: onAction,
  );
}
