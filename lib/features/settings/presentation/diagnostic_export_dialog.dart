import 'package:flutter/material.dart';

import '../../../app/app_dependencies.dart';
import '../../../platform/storage/app_logger.dart';
import '../../../shared/diagnostics/diagnostic_event.dart';

Future<void> showDiagnosticExportDialog(
  BuildContext context,
  AppDependencies app,
) async {
  try {
    final sessions = await app.diagnostics.sessions();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _DiagnosticExportDialog(app: app, sessions: sessions),
    );
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('日志读取失败，请稍后重试。')));
    }
  }
}

class _DiagnosticExportDialog extends StatefulWidget {
  const _DiagnosticExportDialog({required this.app, required this.sessions});
  final AppDependencies app;
  final List<DiagnosticSession> sessions;
  @override
  State<_DiagnosticExportDialog> createState() =>
      _DiagnosticExportDialogState();
}

class _DiagnosticExportDialogState extends State<_DiagnosticExportDialog> {
  late List<DiagnosticSession> sessions = widget.sessions;
  late final Set<String> selected = {
    if (sessions.isNotEmpty)
      sessions.where((s) => s.isScan).firstOrNull?.id ?? sessions.first.id,
  };
  bool busy = false;
  String? error;

  Future<void> _export() async {
    setState(() {
      busy = true;
      error = null;
    });
    await widget.app.exportLog(sessionIds: Set.of(selected));
    if (!mounted) return;
    if (widget.app.logExportFailed) {
      setState(() {
        busy = false;
        error = widget.app.logExportMessage;
      });
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清理所选日志？'),
        content: const Text('将删除所选的本地日志文件。已导出的文件仍保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.app.diagnostics.deleteSessions(Set.of(selected));
      final remaining = await widget.app.diagnostics.sessions();
      if (!mounted) return;
      setState(() {
        sessions = remaining;
        selected.clear();
        busy = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '日志清理失败，请稍后重试。';
        });
      }
    }
  }

  Widget _sessionTile(DiagnosticSession session) {
    final time = session.startedAt;
    final card = session.cardInfo;
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      value: selected.contains(session.id),
      title: Text(
        session.legacy
            ? '旧版日志'
            : '${session.isScan
                  ? '读卡'
                  : session.isQr
                  ? '二维码'
                  : '应用'} · ${time == null ? '时间未知' : AppLogger.formatTimestamp(time.toLocal())}',
      ),
      subtitle: Text(
        '${session.statusText} · ${(session.bytes / 1024).toStringAsFixed(1)} KiB'
        '${card == null ? '' : '\n${card['cardName'] ?? '卡片名称未知'} · ${card['cardTypeLabel'] ?? card['cardType'] ?? '卡种未知'}\n卡号：${card['cardNumber'] ?? '未读取'}'}',
      ),
      onChanged: busy
          ? null
          : (value) => setState(() {
              if (value == true) {
                selected.add(session.id);
              } else {
                selected.remove(session.id);
              }
            }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canDelete =
        selected.isNotEmpty &&
        sessions.where((s) => selected.contains(s.id)).every((s) => !s.running);
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: const Text('日志管理器'),
        scrollable: true,
        insetPadding: const EdgeInsets.all(16),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '选择需要排查的读取记录。完整诊断包含已读取的卡号、卡片名称、卡种；按解析器和字段分类，附带卡片或二维码原始数据，请检查后再分享。',
              ),
              const SizedBox(height: 12),
              const Text('导出所选读卡及二维码记录中已支持解析器的当次解析字段与原始响应，保存在本机下载目录。'),
              if (sessions.isNotEmpty)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                            if (selected.length == sessions.length) {
                              selected.clear();
                            } else {
                              selected.addAll(sessions.map((s) => s.id));
                            }
                          }),
                    child: Text(
                      selected.length == sessions.length ? '取消全选' : '全选记录',
                    ),
                  ),
                ),
              const Divider(),
              if (sessions.isEmpty)
                const Center(child: Text('暂无日志记录'))
              else
                for (final session in sessions) _sessionTile(session),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
        actions: [
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
              TextButton(
                onPressed: busy || !canDelete ? null : _delete,
                child: const Text('清理所选'),
              ),
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: busy || selected.isEmpty ? null : _export,
                child: Text(busy ? '正在处理…' : '导出'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
