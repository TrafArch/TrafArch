import 'package:flutter/material.dart';

import '../../../app/app_dependencies.dart';
import '../../archive/domain/pending_card_save.dart';

/// One modal at a time, bound to the captured save ID and AppDependencies owner.
/// A new scan invalidates both queued effects and an already visible dialog.
class PendingSavePresenter extends StatefulWidget {
  const PendingSavePresenter({
    super.key,
    required this.app,
    required this.active,
    required this.child,
  });

  final AppDependencies app;
  final bool active;
  final Widget child;

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

  @override
  void initState() {
    super.initState();
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
      if (mounted) _presentNext();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  bool _isCurrent(AppDependencies owner, String id) =>
      mounted &&
      identical(widget.app, owner) &&
      widget.active &&
      !owner.autoSaveEnabled &&
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

  void _presentNext() {
    if (_inFlight) {
      final owner = _dialogOwner;
      final id = _dialogId;
      if (owner == null || id == null || !_isCurrent(owner, id)) {
        _dismissOwnedRoute();
      }
      return;
    }
    if (!widget.active) return;
    final app = widget.app;
    if (app.autoSaveEnabled) {
      final notice = app.autoSaveNotice;
      if (notice != null) {
        app.clearAutoSaveNotice();
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text(notice)));
      }
      return;
    }
    final pending = app.pendingCardSave;
    if (pending == null ||
        pending.pendingSaveId == _shownId ||
        !_isCurrent(app, pending.pendingSaveId)) {
      return;
    }
    _show(app, pending);
  }

  Future<void> _show(AppDependencies owner, PendingCardSave pending) async {
    final id = pending.pendingSaveId;
    _inFlight = true;
    _shownId = id;
    _dialogId = id;
    _dialogOwner = owner;
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SaveCardDialog(pending: pending),
    );
    _navigator = navigator;
    _route = route;
    try {
      final save = await navigator.push(route);
      // Wait for the outgoing modal to finish before presenting a newer one.
      await route.completed;
      if (!_isCurrent(owner, id)) return;
      if (save == true) {
        final ok = await owner.acceptPendingSave(id);
        if (!ok && mounted && _isCurrent(owner, id)) {
          _shownId =
              null; // The restored pending capture can be confirmed again.
          ScaffoldMessenger.maybeOf(context)
              ?.showSnackBar(const SnackBar(content: Text('卡片保存失败')));
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
  const SaveCardDialog({super.key, required this.pending});
  final PendingCardSave pending;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('保存卡片'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('是否将本次读取的卡片保存到卡片列表？'),
        const SizedBox(height: 12),
        _row(context, '卡片名称', pending.displayName),
        _row(context, '卡号', pending.cardNumberText),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('不保存'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('保存'),
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
