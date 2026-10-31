import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../app/app_info.dart';
import 'gallery_controller.dart';
import 'gallery_data.dart';
import 'gallery_theme.dart';

part 'gallery_components.dart';
part 'gallery_pages.dart';
part 'gallery_inspection.dart';
part 'gallery_overlays.dart';

class GalleryApp extends StatefulWidget {
  const GalleryApp({super.key, this.controller, this.onDisableBeta});
  final GalleryController? controller;
  final VoidCallback? onDisableBeta;

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
                  ? const Text('演示数据加载失败，请重新打开应用')
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
          ),
        ),
      );
    },
  );
}

class _GalleryView extends StatefulWidget {
  const _GalleryView({required this.controller, this.onDisableBeta});
  final GalleryController controller;
  final VoidCallback? onDisableBeta;
  @override
  State<_GalleryView> createState() => _GalleryViewState();
}

class _GalleryViewState extends State<_GalleryView> {
  GalleryController get c => widget.controller;
  GalleryTokens get t => Theme.of(context).extension<GalleryTokens>()!;
  PageStorageBucket _bucket = PageStorageBucket();
  int _generation = -1;

  @override
  Widget build(BuildContext context) {
    if (_generation != c.generation) {
      _generation = c.generation;
      _bucket = PageStorageBucket();
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
                  children: [
                    ExcludeFocus(
                      excluding: c.overlay != null,
                      child: ExcludeSemantics(
                        excluding: c.overlay != null,
                        child: PageStorage(
                          bucket: _bucket,
                          child: KeyedSubtree(
                            key: ValueKey(c.generation),
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
