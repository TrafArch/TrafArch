import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:dynamic_color/dynamic_color.dart';

import '../app/app_info.dart';
import '../shared/app_support.dart';
import 'gallery_controller.dart';
import 'gallery_balance_presentation.dart';
import 'gallery_data.dart';
import 'gallery_theme.dart';
import 'gallery_design.dart';
import 'gallery_layout.dart';
import 'gallery_preferences.dart';

part 'gallery_components.dart';
part 'gallery_pages.dart';
part 'gallery_inspection.dart';
part 'gallery_overlays.dart';
part 'gallery_information.dart';
part 'gallery_navigation.dart';
part 'gallery_navigation_item.dart';

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
    this.onDisableBeta,
    this.openWebLink,
    this.openEmail,
  });
  final GalleryController controller;
  final GalleryRouteEntry entry;
  final GalleryPreferences preferences;
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
  final Map<String, BuildContext> _menuAnchors = {};
  final Map<String, Rect> _menuRects = {};
  Size? _viewport;
  bool _menuMeasureScheduled = false;
  String? _openingLink;
  String? _linkError;
  Future<List<LicenseEntry>>? _licenses;
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
      } else {
        final open = widget.openWebLink;
        if (open == null) throw StateError('browser unavailable');
        await open(Uri.parse(value));
      }
    } catch (_) {
      if (mounted && c.page == page && c.generation == generation) {
        setState(
          () => _linkError = email
              ? '无法打开邮件应用，请安装或启用邮件应用，或复制邮箱地址。'
              : '无法打开页面，请安装或启用 Edge 或 Chrome 后重试，也可复制链接自行打开。',
        );
      }
    } finally {
      if (mounted) setState(() => _openingLink = null);
    }
  }

  void _reloadLicenses() => setState(() => _licenses = null);

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  Widget _fade(Object identity, Widget child) => _GalleryFade(
    identity: identity,
    reduceMotion: _reduceMotion,
    child: child,
  );

  Widget _collapse(bool open, WidgetBuilder builder) => _GalleryCollapse(
    open: open,
    builder: builder,
    reduceMotion: _reduceMotion,
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
      _menuAnchors.clear();
      _menuRects.clear();
    }
    final viewport = MediaQuery.sizeOf(context);
    if (_viewport != viewport) {
      _viewport = viewport;
      _scheduleMenuMeasure();
    }
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
            systemNavigationBarColor: c.docked && _isMain ? t.surface2 : t.bg,
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
              child: Stack(
                key: _menuRoot,
                fit: StackFit.expand,
                children: [
                  if (_entry.overlay != null)
                    ..._overlay()
                  else ...[
                    PageStorage(
                      bucket: _bucket,
                      child: _isMain
                          ? _GalleryMainTransition(
                              page: _viewPage,
                              reduceMotion: _reduceMotion,
                              builder: _mainPage,
                            )
                          : KeyedSubtree(
                              key: ValueKey(_viewPage),
                              child: _page(_viewPage),
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
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuAnchor(String id, Widget child) => Builder(
    builder: (anchorContext) {
      _menuAnchors[id] = anchorContext;
      _scheduleMenuMeasure();
      return child;
    },
  );

  void _scheduleMenuMeasure() {
    if (_menuMeasureScheduled) return;
    _menuMeasureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _menuMeasureScheduled = false;
      if (!mounted) return;
      var changed = false;
      for (final id in _menuAnchors.keys) {
        final rect = _measureMenuBounds(id);
        if (rect != null && rect != _menuRects[id]) {
          _menuRects[id] = rect;
          changed = true;
        }
      }
      if (changed && c.overlay != null) setState(() {});
    });
  }

  Rect? _measureMenuBounds(String id) {
    final anchorContext = _menuAnchors[id];
    final anchor = anchorContext?.mounted == true
        ? anchorContext!.findRenderObject()
        : null;
    final root = _menuRoot.currentContext?.findRenderObject();
    if (anchor is RenderBox && anchor.hasSize && root is RenderBox) {
      return anchor.localToGlobal(Offset.zero, ancestor: root) & anchor.size;
    }
    return null;
  }

  Rect _menuBounds(String id) =>
      _menuRects[id] ?? const Rect.fromLTWH(16, 64, 36, 36);

  void _openDropdown(GalleryOverlay type, String anchor, {GalleryCard? card}) {
    final rect = _measureMenuBounds(anchor);
    if (rect != null) _menuRects[anchor] = rect;
    c.showOverlay(type, card: card, anchor: rect);
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

  void _toast(String text) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          c.isMainPage ? _navLayout.toastBottom : 16 + _navLayout.safeBottom,
        ),
      ),
    );
  }
}
