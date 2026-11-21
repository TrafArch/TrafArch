import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'dart:math' as math;
import 'dart:ui'
    show ImageFilter, ImageByteFormat, Size, instantiateImageCodec, lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/app_info.dart';
import '../app/app_dependencies.dart';
import '../app/beta_ui_scope.dart';
import '../features/archive/application/archive_history.dart';
import '../features/archive/application/archive_record_count.dart';
import '../features/archive/data/app_database.dart';
import '../features/archive/domain/card_name_extension.dart';
import '../features/archive/domain/card_types.dart';
import '../features/archive/presentation/archive_balance_display.dart';
import '../features/archive/presentation/archive_transfer_dialogs.dart';
import '../features/archive/presentation/card_detail_page.dart';
import '../features/cards/cards_page.dart';
import '../features/expert/expert_page.dart';
import '../features/home/presentation/result_labels.dart';
import '../features/home/presentation/pending_save_presenter.dart';
import '../features/home/presentation/transit_summary_panel.dart';
import '../features/scan/application/scan_controller.dart';
import '../features/settings/presentation/firebase_analytics_tile.dart';
import '../features/transit_analysis/balance_interpretation.dart';
import '../features/trips/journey_transport_icon.dart';
import '../features/trips/trip_filters.dart';
import '../features/trips/trips_page.dart';
import '../platform/browser/feedback_browser.dart';
import '../platform/qr/qr_image_picker.dart';
import '../platform/storage/archive_document_store.dart';
import '../protocols/felica/models/felica_card_type.dart';
import '../protocols/transit/card_parser.dart';
import '../shared/app_support.dart';
import '../shared/domain/archive_conflict_policy.dart';
import 'gallery_controller.dart';
import 'gallery_balance_presentation.dart';
import 'gallery_color_engine.dart';
import 'gallery_contributors.dart';
import 'gallery_data.dart';
import 'gallery_theme.dart';
import 'gallery_design.dart';
import 'gallery_layout.dart';
import 'gallery_monet.dart';
import 'gallery_preferences.dart';
import 'gallery_feedback.dart';
import 'gallery_knowledge_index.dart';
import 'gallery_motion.dart';
import 'gallery_spending.dart';
import 'gallery_archive_spending.dart';

part 'gallery_components.dart';
part 'gallery_pages.dart';
part 'gallery_inspection.dart';
part 'gallery_knowledge_search.dart';
part 'gallery_overlays.dart';
part 'gallery_information.dart';
part 'gallery_navigation.dart';
part 'gallery_navigation_item.dart';
part 'gallery_read_prompt.dart';
part 'gallery_wallet_item.dart';
part 'gallery_detail.dart';
part 'gallery_face_crop.dart';
part 'gallery_live_read.dart';
part 'gallery_live_archive.dart';

class GalleryApp extends StatefulWidget {
  const GalleryApp({
    super.key,
    this.controller,
    this.liveApp,
    this.onDisableBeta,
    this.openWebLink,
    this.openEmail,
    this.preferences,
    this.loadKnowledgeIndex = GalleryKnowledgeIndex.load,
  }) : assert(liveApp == null || controller == null);
  final GalleryController? controller;
  final AppDependencies? liveApp;
  final VoidCallback? onDisableBeta;
  final Future<void> Function(Uri)? openWebLink;
  final Future<bool> Function(String)? openEmail;
  final GalleryPreferences? preferences;
  final Future<GalleryKnowledgeIndex> Function() loadKnowledgeIndex;

  @override
  State<GalleryApp> createState() => _GalleryAppState();
}

class _GalleryAppState extends State<GalleryApp> {
  late final Future<GalleryController> _ready;
  GalleryController? _owned;
  _GalleryLiveRead? _liveRead;
  late final GalleryPreferences _preferences;
  final _appearance = _GalleryAppearance();
  Future<GalleryKnowledgeIndex>? _knowledgeIndex;

  Future<GalleryKnowledgeIndex> _loadKnowledge() =>
      _knowledgeIndex ??= Future.sync(widget.loadKnowledgeIndex).then(
        (index) => index,
        onError: (Object error, StackTrace stack) {
          _knowledgeIndex = null;
          Error.throwWithStackTrace(error, stack);
        },
      );

  @override
  void initState() {
    super.initState();
    _preferences = widget.preferences ?? GalleryPreferences();
    if (widget.liveApp case final app?) {
      final controller = _owned = GalleryController(GalleryData.empty());
      _liveRead = _GalleryLiveRead(app, controller);
      _ready = Future.value(controller);
      return;
    }
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
    _liveRead?.dispose();
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
                  ? const Text('界面加载失败，请重新打开应用')
                  : const CircularProgressIndicator(),
            ),
          ),
        );
      }
      return AnimatedBuilder(
        animation: c,
        builder: (context, _) {
          // Monet follows the home card. Until a newly chosen photo has been
          // sampled, use the user's preset instead of flashing an old theme.
          final monetSeed = _liveRead == null && c.monet && c.hasCardSeed
              ? c.themeSeed
              : null;
          return MaterialApp(
            title: 'TrafArch',
            debugShowCheckedModeBanner: false,
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            themeMode: c.themeMode,
            themeAnimationDuration: GalleryMotion.duration(
              context,
              GalleryMotion.theme,
            ),
            themeAnimationCurve: GalleryMotion.standard,
            theme: _appearance.theme(c, false, monetSeed),
            darkTheme: _appearance.theme(c, true, monetSeed),
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
                              : tokens.canvas,
                          systemNavigationBarDividerColor: Colors.transparent,
                        ),
                child: ColoredBox(
                  color: tokens.canvas,
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
            home: _GalleryLiveScope(
              notifier: _liveRead,
              child: _GalleryNavigator(
                key: ValueKey(c.generation),
                controller: c,
                preferences: _preferences,
                loadKnowledge: _loadKnowledge,
                onDisableBeta: widget.onDisableBeta,
                openWebLink: widget.openWebLink,
                openEmail: widget.openEmail,
              ),
            ),
          );
        },
      );
    },
  );
}

/// Theme inputs are stable between notifications, so the same [ThemeData]
/// instance is reused. MaterialApp animates a cross-fade whenever the incoming
/// theme differs; a fresh instance per notification restarts that fade and
/// rebuilds every Theme-dependent widget on each frame of a transition.
class _GalleryAppearance {
  final _themes = <(int, bool, String, Color?), ThemeData>{};

  ThemeData theme(GalleryController controller, bool dark, Color? monetSeed) =>
      _themes.putIfAbsent(
        (
          identityHashCode(controller.data),
          dark,
          controller.palette,
          monetSeed,
        ),
        () => GalleryTokens.from(
          controller.data,
          dark,
          controller.palette,
          monetSeed: monetSeed,
        ).theme(),
      );
}

class _GalleryView extends StatefulWidget {
  const _GalleryView({
    super.key,
    required this.controller,
    required this.entry,
    required this.preferences,
    required this.anchors,
    required this.loadKnowledge,
    this.visible = true,
    this.onDisableBeta,
    this.openWebLink,
    this.openEmail,
  });
  final GalleryController controller;
  final GalleryRouteEntry entry;
  final GalleryPreferences preferences;
  final _GalleryAnchorRegistry anchors;
  final Future<GalleryKnowledgeIndex> Function() loadKnowledge;
  final bool visible;
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
  Widget? _cachedLayout;
  Set<String>? _walletCardIds;
  final Set<String> _walletArrivals = {};
  GallerySpendingSelection _spendingSelection =
      const GallerySpendingSelection.all();
  Stream<List<ArchiveCardSummary>>? _archiveCards;
  Stream<ArchiveHistoryResult>? _archiveHistory;
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
          if (data != null) {
            // The native picker clears its previous cache on each selection.
            // The bytes stay in a crop session until the sheet's 完成 commits
            // them (spec 2.4 §8.2). Sample the Monet seed now, while the picker
            // is still busy, so the committed theme switches exactly once.
            final bytes = data.buffer.asUint8List(
              data.offsetInBytes,
              data.lengthInBytes,
            );
            final seed = await GalleryMonet.seedFromImage(bytes);
            if (active()) {
              c.beginFaceCrop(
                card.id,
                bytes,
                Size(
                  frame.image.width.toDouble(),
                  frame.image.height.toDouble(),
                ),
                seed: seed,
              );
            }
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

  bool _importingRecords = false;

  /// 导入与导出一样停留在预览层：读取用户选择的备份文件并展示内容，
  /// 不覆盖当前内置样例。
  Future<void> _importCardRecords() async {
    if (_importingRecords) return;
    setState(() => _importingRecords = true);
    try {
      final document = await const MethodChannelArchiveDocumentStore()
          .openJson();
      if (document == null || !mounted) return;
      String summary;
      try {
        final decoded = jsonDecode(document.content);
        final cards = decoded is Map ? decoded['cards'] : null;
        summary = cards is List ? '识别到 ${cards.length} 张卡片记录' : '未识别到卡片记录字段';
      } catch (_) {
        summary = '文件不是有效的 JSON';
      }
      c.update(() {
        c.exportTitle = '导入预览';
        c.exportText = '${document.name}\n$summary\n\n${document.content}';
      }, '预览导入文件');
      c.showOverlay(GalleryOverlay.importPreview);
    } on MissingPluginException {
      _toast('当前平台不支持文件选择，请在 Android 上导入', type: GalleryFeedbackType.error);
    } on PlatformException catch (error) {
      _toast(error.message ?? '无法读取所选文件，请重试', type: GalleryFeedbackType.error);
    } catch (_) {
      _toast('无法读取所选文件，请重试', type: GalleryFeedbackType.error);
    } finally {
      if (mounted) setState(() => _importingRecords = false);
    }
  }

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
    c.licenseParagraphs.clear();
  });

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
    turns: open ? .5 : 0,
    duration: GalleryMotion.duration(context, GalleryMotion.arrow),
    curve: GalleryMotion.standard,
    child: Icon(Icons.keyboard_arrow_down_rounded, size: size),
  );

  @override
  Widget build(BuildContext context) {
    if (!widget.visible && _cachedLayout != null) return _cachedLayout!;
    return _cachedLayout = _buildLayout(context);
  }

  Widget _buildLayout(BuildContext context) {
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
                : t.canvas,
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
            backgroundColor: _entry.overlay != null
                ? Colors.transparent
                : t.canvas,
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

  Widget _page(GalleryPage page) {
    if (_GalleryLiveScope.of(context) case final live?) {
      return _livePage(page, live);
    }
    return switch (page) {
      GalleryPage.home => _home(),
      GalleryPage.trips => _trips(),
      GalleryPage.expert => _expert(),
      GalleryPage.cards => _cards(),
      GalleryPage.footprints => _footprints(),
      GalleryPage.detail => _detail(),
      GalleryPage.settings => _settings(),
      GalleryPage.knowledge => _knowledge(),
      GalleryPage.knowledgeSearch => _GalleryKnowledgeSearch(
        load: widget.loadKnowledge,
        onBack: c.back,
        onResult: c.openKnowledgeResult,
      ),
      GalleryPage.knowledgeCity ||
      GalleryPage.knowledgeLine ||
      GalleryPage.knowledgeStation => _knowledgeDetails(
        _entry.knowledgeResult!,
      ),
      GalleryPage.qr => _qr(),
      GalleryPage.feedback => _feedback(),
      GalleryPage.acknowledgements => _acknowledgements(),
      GalleryPage.licenses => _licensePage(),
    };
  }

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
