import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_dependencies.dart';
import '../../archive/domain/pending_card_save.dart';
import '../../archive/domain/card_session_snapshot.dart';
import '../../archive/domain/card_types.dart';
import '../../archive/domain/amusement_ic_archive_identity.dart';
import '../../archive/domain/suica_archive_identity.dart';
import '../../../protocols/felica/models/amusement_ic_data.dart';
import '../../../shared/presentation/amusement_ic_summary.dart';
import '../../../shared/presentation/suica_identity_summary.dart';
import '../../../shared/domain/archive_conflict_policy.dart';

/// One modal at a time, bound to the captured save ID and AppDependencies owner.
/// A new scan invalidates both queued effects and an already visible dialog.
class PendingSavePresenter extends StatefulWidget {
  const PendingSavePresenter({
    super.key,
    required this.app,
    required this.active,
    required this.child,
    this.manualRequest,
    this.onNotice,
    this.canPresent,
  });

  final AppDependencies app;
  final bool active;
  final Widget child;
  final int? manualRequest;
  final void Function(String message, bool failed)? onNotice;
  final bool Function()? canPresent;

  @override
  State<PendingSavePresenter> createState() => _PendingSavePresenterState();
}

class _PendingSavePresenterState extends State<PendingSavePresenter> {
  bool _scheduled = false;
  bool _inFlight = false;
  String? _shownId;
  String? _dialogId;
  AppDependencies? _dialogOwner;
  DialogRoute<bool>? _route;
  NavigatorState? _navigator;
  int _handledRequest = 0;
  bool _manualDialog = false;
  bool get _active => widget.active && (widget.canPresent?.call() ?? true);

  void _notice(String message, {bool failed = false}) {
    final onNotice = widget.onNotice;
    if (onNotice != null) {
      onNotice(message, failed);
    } else {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  void initState() {
    super.initState();
    _handledRequest = widget.manualRequest ?? 0;
    widget.app.addListener(_schedule);
    _schedule();
  }

  @override
  void didUpdateWidget(covariant PendingSavePresenter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app != widget.app) {
      oldWidget.app.removeListener(_schedule);
      widget.app.addListener(_schedule);
      _shownId = null;
    }
    _schedule();
  }

  void _schedule() {
    if (!mounted || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) unawaited(_presentNext());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  bool _isCurrent(AppDependencies owner, String id) =>
      mounted &&
      identical(widget.app, owner) &&
      _active &&
      (_manualDialog ||
          !owner.autoSaveEnabled ||
          owner.archiveConflictPolicy == ArchiveConflictPolicy.ask) &&
      !owner.scanning &&
      owner.pendingCardSave?.pendingSaveId == id;

  void _dismissOwnedRoute() {
    final route = _route;
    final navigator = _navigator;
    if (route != null && route.isActive && navigator?.mounted == true) {
      // Remove only this route, even if another screen now sits above it.
      _shownId = null;
      navigator!.removeRoute(route);
    }
  }

  Future<void> _presentNext() async {
    if (_inFlight) {
      final owner = _dialogOwner;
      final id = _dialogId;
      if (owner == null || id == null || !_isCurrent(owner, id)) {
        _dismissOwnedRoute();
      }
      return;
    }
    if (!_active) return;
    final app = widget.app;
    final request = widget.manualRequest;
    final manual = request != null && request != _handledRequest;
    if (app.autoSaveEnabled) {
      final notice = app.autoSaveNotice;
      if (notice != null) {
        app.clearAutoSaveNotice();
        _notice(notice, failed: notice.startsWith('自动保存失败'));
      }
      if (!manual && app.archiveConflictPolicy != ArchiveConflictPolicy.ask) {
        return;
      }
    } else if (request != null && !manual) {
      return;
    }
    final pending = app.pendingCardSave;
    if (pending == null || app.scanning) return;
    final exists = await app.archiveCardExists(pending.fingerprint);
    if (!mounted ||
        !identical(app, widget.app) ||
        app.pendingCardSave?.pendingSaveId != pending.pendingSaveId ||
        !_active) {
      return;
    }
    if (app.autoSaveEnabled && !exists && !manual) return;
    if (manual) {
      if (request == _handledRequest || request != widget.manualRequest) return;
      _handledRequest = request;
      _shownId = null;
    }
    if (exists && app.archiveConflictPolicy == ArchiveConflictPolicy.skip) {
      app.declinePendingSave(pending.pendingSaveId);
      _notice('已跳过已存在的记录：${pending.displayName}');
      return;
    }
    if (_inFlight ||
        pending.pendingSaveId == _shownId ||
        app.scanning ||
        (!manual &&
            app.autoSaveEnabled &&
            app.archiveConflictPolicy != ArchiveConflictPolicy.ask)) {
      return;
    }
    await _show(app, pending, exists: exists, manual: manual);
  }

  Future<void> _show(
    AppDependencies owner,
    PendingCardSave pending, {
    required bool exists,
    required bool manual,
  }) async {
    final id = pending.pendingSaveId;
    _inFlight = true;
    _manualDialog = manual;
    _shownId = id;
    _dialogId = id;
    _dialogOwner = owner;
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SaveCardDialog(
        pending: pending,
        conflict: exists,
        askEachTime: owner.archiveConflictPolicy == ArchiveConflictPolicy.ask,
      ),
    );
    _navigator = navigator;
    _route = route;
    try {
      final save = await navigator.push(route);
      // Wait for the outgoing modal to finish before presenting a newer one.
      await route.completed;
      if (!_isCurrent(owner, id)) return;
      if (save == true) {
        final ok = await owner.acceptPendingSave(
          id,
          conflictPolicy: exists ? ArchiveConflictPolicy.overwrite : null,
        );
        if (!ok && mounted && _isCurrent(owner, id)) {
          if (widget.manualRequest == null) _shownId = null;
          _notice('卡片保存失败', failed: true);
        } else if (ok && mounted && widget.manualRequest != null) {
          _notice('本次读取已保存');
        }
      } else {
        owner.declinePendingSave(id);
      }
    } finally {
      _route = null;
      _navigator = null;
      _dialogId = null;
      _dialogOwner = null;
      _inFlight = false;
      _manualDialog = false;
      _schedule();
    }
  }

  @override
  void dispose() {
    widget.app.removeListener(_schedule);
    final route = _route;
    final navigator = _navigator;
    // Navigator can be locked while the containing page is being disposed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route != null && route.isActive && navigator?.mounted == true) {
        navigator!.removeRoute(route);
      }
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class SaveCardDialog extends StatelessWidget {
  const SaveCardDialog({
    super.key,
    required this.pending,
    this.conflict = false,
    this.askEachTime = false,
  });
  final PendingCardSave pending;
  final bool conflict;
  final bool askEachTime;

  AmusementIcData? get _amusementIc {
    final raw = pending.sessionDataJson;
    if (raw == null) return null;
    final section = CardSessionSnapshot.decode(raw)?.extensions['amusementIc'];
    if (section is! Map || section['version'] != 1) return null;
    return AmusementIcData.fromJson(section['data']);
  }

  SuicaArchiveIdentity get _suicaIdentity {
    final raw = pending.sessionDataJson;
    final snapshot = raw == null ? null : CardSessionSnapshot.decode(raw);
    return SuicaArchiveIdentity.resolve(
      cardType: pending.identity.cardType,
      fingerprint: pending.fingerprint,
      snapshots: [?snapshot],
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(conflict ? '记录已存在' : '保存卡片'),
    scrollable: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          conflict
              ? askEachTime
                    ? '这张卡已有记录，请选择跳过，或用本次读取更新该卡。已有历史记录会保留。'
                    : '这张卡已有记录，是否用本次读取更新？已有历史记录会保留。'
              : '是否将本次读取的卡片保存到卡片列表？',
        ),
        const SizedBox(height: 12),
        _row(
          context,
          '卡片名称',
          pending.identity.cardType == CardTypes.amusementIc
              ? AmusementIcArchiveIdentity.fromCapturedData(_amusementIc)
                    .defaultName
              : pending.displayName,
        ),
        if (pending.identity.cardType == CardTypes.amusementIc)
          AmusementIcSummary(data: _amusementIc, showRawAccessCode: false)
        else if (pending.identity.cardType == CardTypes.suica)
          SuicaIdentitySummary(
            idm: _suicaIdentity.idm,
            hasConflict: _suicaIdentity.hasConflict,
          )
        else
          _row(context, '卡号', pending.cardNumberText),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: Text(
          conflict && askEachTime
              ? '跳过'
              : conflict
              ? '取消'
              : '不保存',
        ),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: Text(conflict ? '覆盖' : '保存'),
      ),
    ],
  );

  Widget _row(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
