import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../app/app_info.dart';
import '../shared/app_support.dart';
import 'gallery_controller.dart';
import 'gallery_data.dart';
import 'gallery_theme.dart';

part 'gallery_components.dart';
part 'gallery_pages.dart';
part 'gallery_inspection.dart';
part 'gallery_overlays.dart';
part 'gallery_information.dart';

class GalleryApp extends StatefulWidget {
  const GalleryApp({
    super.key,
    this.controller,
    this.onDisableBeta,
    this.openWebLink,
    this.openEmail,
  });
  final GalleryController? controller;
  final VoidCallback? onDisableBeta;
  final Future<void> Function(Uri)? openWebLink;
  final Future<bool> Function(String)? openEmail;

  @override
  State<GalleryApp> createState() => _GalleryAppState();
}

class _GalleryAppState extends State<GalleryApp> {
  late final Future<GalleryController> _ready;
  GalleryController? _owned;

  @override
  void initState() {
    super.initState();
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
        builder: (context, _) => MaterialApp(
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
          ).theme(),
          darkTheme: GalleryTokens.from(
            c.data,
            true,
            c.monet ? 'blue' : c.palette,
          ).theme(),
          home: _GalleryView(
            controller: c,
            onDisableBeta: widget.onDisableBeta,
            openWebLink: widget.openWebLink,
            openEmail: widget.openEmail,
          ),
        ),
      );
    },
  );
}

class _GalleryView extends StatefulWidget {
  const _GalleryView({
    required this.controller,
    this.onDisableBeta,
    this.openWebLink,
    this.openEmail,
  });
  final GalleryController controller;
  final VoidCallback? onDisableBeta;
  final Future<void> Function(Uri)? openWebLink;
  final Future<bool> Function(String)? openEmail;
  @override
  State<_GalleryView> createState() => _GalleryViewState();
}

class _GalleryViewState extends State<_GalleryView> {
  GalleryController get c => widget.controller;
  GalleryTokens get t => Theme.of(context).extension<GalleryTokens>()!;
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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (t.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: c.docked && c.isMainPage
                ? t.surface2
                : t.bg,
            systemNavigationBarDividerColor: Colors.transparent,
          ),
      child: PopScope(
        canPop: !c.canGoBack,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) c.back();
        },
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
              resizeToAvoidBottomInset: true,
              body: SafeArea(
                bottom: false,
                child: Stack(
                  key: _menuRoot,
                  children: [
                    ExcludeFocus(
                      excluding: c.overlay != null,
                      child: ExcludeSemantics(
                        excluding: c.overlay != null,
                        child: PageStorage(
                          bucket: _bucket,
                          child: KeyedSubtree(
                            key: ValueKey(c.page),
                            child: _page(),
                          ),
                        ),
                      ),
                    ),
                    if (c.isMainPage)
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: _navigation(),
                      ),
                    if (c.overlay != null) ..._overlay(),
                  ],
                ),
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
    c.showOverlay(type, card: card);
  }

  Widget _page() => switch (c.page) {
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

  Widget _list(List<Widget> children, {String? id, double? bottom}) => ListView(
    key: PageStorageKey('gallery-${c.generation}-${id ?? c.page.name}'),
    padding: EdgeInsets.fromLTRB(
      16,
      6,
      16,
      bottom ??
          (c.isMainPage
              ? (c.docked ? 80 : 108) + MediaQuery.paddingOf(context).bottom
              : 30 + MediaQuery.paddingOf(context).bottom),
    ),
    children: children,
  );

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
          (c.isMainPage ? 100 : 16) + MediaQuery.paddingOf(context).bottom,
        ),
      ),
    );
  }
}
