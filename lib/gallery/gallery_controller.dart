import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'gallery_data.dart';

enum GalleryPage {
  home,
  trips,
  expert,
  cards,
  footprints,
  detail,
  settings,
  knowledge,
  qr,
  scenes,
}

enum GalleryOverlay {
  save,
  face,
  trip,
  cardMenu,
  rename,
  delete,
  source,
  mode,
  about,
  export,
  rawFeedback,
}

enum GalleryReadState { unread, reading, success, failed }

/// UI-only session. No repositories, platform channels, IO or real card models.
class GalleryController extends ChangeNotifier {
  GalleryController(this.data) {
    qr = GalleryQrController(data)..addListener(_qrChanged);
    _reset();
  }

  final GalleryData data;
  late final GalleryQrController qr;
  static final clock = DateTime.parse('2026-10-27T09:41:00+08:00');
  late List<GalleryCard> cards;
  late List<GalleryRecord> trips;
  late List<GalleryRecord> footprints;
  GalleryPage page = GalleryPage.home;
  final List<GalleryPage> _history = [];
  GalleryOverlay? overlay;
  GalleryReadState readState = GalleryReadState.unread;
  bool hasRead = false;
  bool autoSave = false;
  bool includeOverdraft = false;
  bool monet = true;
  bool logsEnabled = false;
  bool docked = false;
  ThemeMode themeMode = ThemeMode.system;
  String palette = 'blue';
  String selectedCardId = 'shanghai';
  String expertKind = 'card';
  int expertTab = 0;
  int detailTab = 0;
  String source = '全部来源';
  String mode = '全部方式';
  String knowledgeTab = 'tu';
  bool knowledgeMetadata = false;
  final Set<String> knowledgeExpanded = {};
  final Set<String> expanded = {};
  final List<String> logs = [];
  GalleryRecord? selectedTrip;
  String exportText = '';
  String exportTitle = '导出预览';
  String? sceneId;
  int generation = 0;
  Timer? _readTimer;
  bool _disposed = false;

  GalleryCard get current => cards.firstWhere((c) => c.id == 'shanghai');
  GalleryCard get selectedCard =>
      cards.firstWhere((c) => c.id == selectedCardId, orElse: () => current);
  List<GalleryCard> get savedCards => cards.where((c) => c.saved).toList();
  bool get isMainPage => page.index < 5;
  bool get canGoBack =>
      overlay != null ||
      qr.view != 'inspect' && page == GalleryPage.qr ||
      _history.isNotEmpty;

  void _qrChanged() {
    if (!_disposed) notifyListeners();
  }

  void _reset() {
    cancelRead();
    qr.reset();
    cards = data.cards.map(GalleryCard.fromJson).toList();
    trips = data.trips.map((r) => Map<String, dynamic>.from(r)).toList();
    footprints = data.footprints
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
    page = GalleryPage.home;
    _history.clear();
    overlay = null;
    readState = GalleryReadState.unread;
    hasRead = autoSave = includeOverdraft = logsEnabled = docked = false;
    monet = true;
    themeMode = ThemeMode.system;
    palette = 'blue';
    selectedCardId = 'shanghai';
    expertKind = 'card';
    expertTab = detailTab = 0;
    source = '全部来源';
    mode = '全部方式';
    knowledgeTab = 'tu';
    knowledgeMetadata = false;
    knowledgeExpanded.clear();
    expanded.clear();
    logs.clear();
    selectedTrip = null;
    sceneId = null;
    generation++;
  }

  void reset() {
    _reset();
    notifyListeners();
  }

  void record(String action) {
    if (!logsEnabled) return;
    logs.add('2026-10-27 09:41:00 ${page.name} $action');
    if (logs.length > 500) logs.removeAt(0);
  }

  void update(VoidCallback change, [String action = '界面操作']) {
    change();
    record(action);
    notifyListeners();
  }

  void navigate(GalleryPage target) {
    if (target == page) return;
    if (target == GalleryPage.qr) cancelRead();
    if (target.index < 5) {
      _history.clear();
    } else {
      _history.add(page);
    }
    overlay = null;
    page = target;
    record('打开 ${target.name}');
    notifyListeners();
  }

  void back() {
    if (overlay != null) {
      overlay = null;
    } else if (page == GalleryPage.qr && qr.view != 'inspect') {
      qr.cancel();
      return;
    } else if (_history.isNotEmpty) {
      if (page == GalleryPage.qr) qr.cancel(notify: false);
      page = _history.removeLast();
    }
    notifyListeners();
  }

  void showOverlay(
    GalleryOverlay value, {
    GalleryCard? card,
    GalleryRecord? trip,
  }) {
    if (card != null) selectedCardId = card.id;
    if (trip != null) selectedTrip = trip;
    overlay = value;
    record('打开 ${value.name}');
    notifyListeners();
  }

  void openCard(GalleryCard card) {
    selectedCardId = card.id;
    detailTab = 0;
    navigate(GalleryPage.detail);
  }

  void cancelRead() {
    _readTimer?.cancel();
    _readTimer = null;
    if (readState == GalleryReadState.reading) {
      readState = hasRead ? GalleryReadState.success : GalleryReadState.unread;
    }
  }

  void read({bool fail = false}) {
    if (readState == GalleryReadState.reading) return;
    cancelRead();
    readState = GalleryReadState.reading;
    record('开始模拟读取');
    notifyListeners();
    final request = generation;
    _readTimer = Timer(const Duration(milliseconds: 1600), () {
      if (_disposed || request != generation) return;
      _readTimer = null;
      if (fail) {
        readState = GalleryReadState.failed;
      } else {
        readState = GalleryReadState.success;
        hasRead = true;
        if (autoSave) current.saved = true;
      }
      record(fail ? '模拟读取失败' : '模拟读取完成');
      notifyListeners();
    });
  }

  void save(String name) {
    if (!hasRead || readState == GalleryReadState.reading) return;
    update(() {
      if (name.trim().isNotEmpty) current.name = name.trim();
      current.saved = true;
      overlay = null;
    }, '保存模拟卡片');
  }

  void rename(String name) {
    if (name.trim().isEmpty) return;
    update(() {
      selectedCard.name = name.trim();
      overlay = null;
    }, '重命名模拟卡片');
  }

  void deleteCard() {
    update(() {
      selectedCard.saved = false;
      overlay = null;
      if (page == GalleryPage.detail) {
        page = GalleryPage.cards;
        _history.clear();
      }
    }, '删除模拟卡片');
  }

  void setAutoSave(bool value) => update(() {
    autoSave = value;
    if (value && hasRead && readState != GalleryReadState.reading) {
      current.saved = true;
    }
  }, '修改自动保存');

  void setLogs(bool value) {
    if (value) {
      logsEnabled = true;
      record('logging-enabled');
    } else {
      record('logging-disabled');
      logsEnabled = false;
    }
    notifyListeners();
  }

  void export({bool all = false, bool log = false}) {
    if (log && !logsEnabled) return;
    exportTitle = log ? '日志导出预览' : '卡片记录导出预览';
    exportText = log
        ? 'TrafArch Gallery · Demo 2.4.0\n${logs.join('\n')}'
        : const JsonEncoder.withIndent('  ').convert({
            'demo': true,
            'designVersion': '2.4.0',
            'cards': (all ? savedCards : [selectedCard])
                .map(
                  (c) => {
                    'name': c.name,
                    'number': c.pan,
                    'rawBalance': c.rawBalance,
                    'records': ledger(c),
                  },
                )
                .toList(),
          });
    showOverlay(GalleryOverlay.export);
  }

  List<GalleryRecord> ledger(GalleryCard card) => card.id == 'shanghai'
      ? trips.where((t) => t['kind'] != 'event').toList()
      : data.ledger(card.id);

  List<GalleryRecord> get filteredTrips {
    if (!hasRead) return [];
    return trips.where((t) {
      final sources = (t['sources'] as List?) ?? [t['source']];
      final matchesSource = source == '全部来源' || sources.contains(source);
      final matchesMode = mode == '全部方式' || t['mode'] == mode;
      if (source == '全部来源' && t['kind'] == 'event') return false;
      return matchesSource && matchesMode;
    }).toList();
  }

  void applyScene(GalleryScene scene) {
    _reset();
    sceneId = scene.id;
    final q = scene.query;
    page = switch (q['screen']) {
      'trips' => GalleryPage.trips,
      'expert' => GalleryPage.expert,
      'cards' => GalleryPage.cards,
      'footprints' => GalleryPage.footprints,
      'card-detail' => GalleryPage.detail,
      'settings' => GalleryPage.settings,
      'knowledge' => GalleryPage.knowledge,
      'qr' => GalleryPage.qr,
      _ => GalleryPage.home,
    };
    if (!isMainPage) {
      _history.add(
        page == GalleryPage.detail
            ? GalleryPage.cards
            : page == GalleryPage.knowledge
            ? GalleryPage.settings
            : GalleryPage.home,
      );
    }
    hasRead = q['read'] == 1 || q['saved'] == 1;
    current.saved = q['saved'] == 1;
    autoSave = q['autosave'] == 1;
    if (hasRead) readState = GalleryReadState.success;
    if (autoSave && hasRead) current.saved = true;
    if (q['fail'] == 1) readState = GalleryReadState.failed;
    monet = q['monet'] != 0;
    palette = q['palette'] as String? ?? 'blue';
    docked =
        q['bar'] !=
        'float'; // The exported reference scenes use dock by default.
    detailTab = q['detailTab'] as int? ?? 0;
    knowledgeTab = q['kb'] as String? ?? 'tu';
    if (q['edge'] == 'long') {
      current.name = '上海公共交通卡 交通联合纪念版';
      current.rawBalance = '1,234,567.89';
      cards[1].name = '深圳通 全国交通一卡通互联互通版';
      cards[1].rawBalance = '123,456.78';
      cards[3].rawBalance = 'HK\$1,234,567.00';
      trips[2]['sub'] = '延安东路中山东一路外滩枢纽站 → 静安寺常德路南京西路';
      footprints[0]['name'] = '人民广场（地铁 1 / 2 / 8 号线换乘枢纽）';
    } else if (q['edge'] == 'unknown') {
      current.rawBalance = '—';
      cards[2].rawBalance = '—';
    } else if (q['edge'] == 'empty') {
      trips.clear();
    }
    overlay = switch (q['modal']) {
      'face' => GalleryOverlay.face,
      'about' => GalleryOverlay.about,
      _ => null,
    };
    final v = scene.variant;
    if (v == 'reading') readState = GalleryReadState.reading;
    if (v == 'logs') {
      logsEnabled = true;
      record('logging-enabled');
    }
    if (v == 'save') overlay = GalleryOverlay.save;
    if (v == 'trip') {
      overlay = GalleryOverlay.trip;
      selectedTrip = trips.first;
    }
    if (v == 'card-menu') overlay = GalleryOverlay.cardMenu;
    if (v == 'rename') overlay = GalleryOverlay.rename;
    if (v == 'delete') overlay = GalleryOverlay.delete;
    if (v == 'filter') overlay = GalleryOverlay.source;
    if (v?.startsWith('expert-') ?? false) {
      expertTab = int.parse(v!.split('-').last);
    }
    if (v == 'bank' || v == 'felica') expertKind = v!;
    if (v == 'knowledge') {
      knowledgeMetadata = true;
      knowledgeExpanded.addAll(['tu:0', 'tu:0:0']);
    }
    if (v == 'camera' || v == 'gallery' || v == 'camera-error') qr.view = v!;
    if (v == 'qr-valid' || v == 'qr-expired' || v == 'certificate') {
      qr.setSample(v == 'qr-expired' ? 'expired' : 'valid', notify: false);
      if (v == 'certificate') {
        expanded.addAll([
          'qr:info',
          'qr:time',
          'qr:key',
          'qr:certificate',
          'qr:raw',
        ]);
      }
    }
    if (v == 'qr-invalid') qr.setSample('invalid', notify: false);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    cancelRead();
    qr.removeListener(_qrChanged);
    qr.dispose();
    super.dispose();
  }
}

class GalleryQrController extends ChangeNotifier {
  GalleryQrController(this.data);
  final GalleryData data;
  String view = 'inspect';
  bool busy = false;
  bool torch = false;
  String origin = 'gallery';
  GalleryRecord? result;
  String? error;
  List<dynamic> raw = [];
  Timer? _timer;
  int _request = 0;

  void reset() {
    _request++;
    _timer?.cancel();
    view = 'inspect';
    busy = torch = false;
    result = null;
    error = null;
    raw = [];
  }

  void cancel({bool notify = true}) {
    _request++;
    _timer?.cancel();
    busy = torch = false;
    view = 'inspect';
    if (notify) notifyListeners();
  }

  void open(String target) {
    cancel(notify: false);
    view = target;
    notifyListeners();
  }

  void clear() {
    reset();
    notifyListeners();
  }

  void toggleTorch() {
    torch = !torch;
    notifyListeners();
  }

  void acquire(String sample) {
    if (busy) return;
    busy = true;
    final request = ++_request;
    origin = view == 'camera' ? 'camera' : 'gallery';
    notifyListeners();
    _timer = Timer(const Duration(milliseconds: 700), () {
      if (request != _request) return;
      busy = torch = false;
      if (sample == 'no-code') {
        error = '图片中未识别到二维码，已保留上次结果';
        view = 'inspect';
      } else {
        setSample(sample, notify: false);
      }
      notifyListeners();
    });
  }

  void setSample(String sample, {bool notify = true}) {
    view = 'inspect';
    busy = torch = false;
    if (sample == 'invalid') {
      result = null;
      error = '二维码版本错误：应不小于 0x80，实际为 0x68';
      raw = [0x68, 0x74, 0x74, 0x70, 0x73, 0x3a, 0x2f, 0x2f];
    } else {
      result =
          data.json[sample == 'expired' ? 'qrExpired' : 'qrValid']
              as GalleryRecord;
      raw = result!['raw'] as List;
      error = null;
    }
    if (notify) notifyListeners();
  }

  @override
  void dispose() {
    _request++;
    _timer?.cancel();
    super.dispose();
  }
}
