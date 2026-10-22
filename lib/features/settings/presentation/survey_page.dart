import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 应用内网页页：以内嵌 WebView 展示外部页面（反馈问卷 / QQ 加群等），
/// 用户无需跳出应用。
class SurveyPage extends StatefulWidget {
  const SurveyPage({super.key, required this.title, required this.url});

  final String title;
  final String url;

  @override
  State<SurveyPage> createState() => _SurveyPageState();
}

class _SurveyPageState extends State<SurveyPage> {
  late final WebViewController _controller;
  int _progress = 0;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            const webSchemes = {'http', 'https', 'about', 'data', 'blob'};
            if (uri == null || webSchemes.contains(uri.scheme)) {
              return NavigationDecision.navigate;
            }
            // 页面内唤起客户端等非网络 scheme（如加群页的 mqqapi://）：
            // 交给系统分发；WebView 直接加载会报 ERR_UNKNOWN_URL_SCHEME
            _openExternally(uri);
            return NavigationDecision.prevent;
          },
          onWebResourceError: (error) {
            // 仅主文档加载失败时切换到错误页（图片等子资源失败不打断）
            if ((error.isForMainFrame ?? false) && mounted) {
              setState(() => _failed = true);
            }
          },
        ),
      );
    _load();
  }

  void _load() {
    setState(() {
      _failed = false;
      _progress = 0;
    });
    _controller.loadRequest(Uri.parse(widget.url));
  }

  /// 将 WebView 无法处理的链接交给系统分发（如加群页内"打开 QQ"按钮）。
  Future<void> _openExternally(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // 无对应应用处理该链接：忽略
    }
  }

  @override
  Widget build(BuildContext context) {
    // PopScope：网页内可回退时先回退网页；canPop 需在手势开始前确定、
    // 无法按网页历史动态变化，故固定 false，统一在回调中处理。
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _controller.canGoBack()) {
          await _controller.goBack();
        } else if (mounted) {
          navigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          bottom: !_failed && _progress < 100
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(2),
                  child: LinearProgressIndicator(value: _progress / 100),
                )
              : null,
        ),
        body: _failed
            ? _LoadErrorView(onRetry: _load)
            : WebViewWidget(controller: _controller),
      ),
    );
  }
}

/// 页面加载失败提示（网络异常 / 证书错误等），支持重新加载。
class _LoadErrorView extends StatelessWidget {
  const _LoadErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.wifi_off_outlined,
            size: 48,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text('页面加载失败，请检查网络后重试', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onRetry, child: const Text('重新加载')),
        ],
      ),
    );
  }
}
