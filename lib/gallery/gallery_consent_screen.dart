import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../app/app_info.dart';
import '../app/legal_consent_gate.dart';
import 'gallery_design.dart';
import 'gallery_feedback.dart';
import 'gallery_layout.dart';
import 'gallery_theme.dart';

class GalleryConsentScreen extends StatelessWidget {
  const GalleryConsentScreen(this.prompt, {super.key});

  final LegalConsentPrompt? prompt;
  static final _light = GalleryTokens.forPalette('blue', dark: false).theme();
  static final _dark = GalleryTokens.forPalette('blue', dark: true).theme();

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: AppInfo.appName,
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: _light,
    darkTheme: _dark,
    themeAnimationDuration: const Duration(milliseconds: 240),
    themeAnimationCurve: Curves.easeInOut,
    builder: (context, child) => GalleryWindow(
      child: GalleryFeedbackHost(mainPage: false, docked: false, child: child!),
    ),
    home: Scaffold(
      body: prompt == null
          ? const Center(child: CircularProgressIndicator())
          : _ConsentDialog(prompt: prompt!),
    ),
  );
}

class _ConsentDialog extends StatefulWidget {
  const _ConsentDialog({required this.prompt});
  final LegalConsentPrompt prompt;

  @override
  State<_ConsentDialog> createState() => _ConsentDialogState();
}

class _ConsentDialogState extends State<_ConsentDialog>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: GalleryDialogMotion.enter,
    reverseDuration: GalleryDialogMotion.exit,
  );
  late final _progress = CurvedAnimation(
    parent: _motion,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  late final _scale = Tween<double>(
    begin: GalleryDialogMotion.initialScale,
    end: 1,
  ).animate(_progress);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.value = _motion.status == AnimationStatus.reverse ? 0 : 1;
    } else if (_motion.isDismissed) {
      _motion.forward();
    }
  }

  Future<void> _close() async {
    if (MediaQuery.disableAnimationsOf(context)) return;
    await _motion.reverse().orCancel.onError<TickerCanceled>((_, _) {});
  }

  @override
  void dispose() {
    _progress.dispose();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GalleryTokens>()!;
    const radius = BorderRadius.all(Radius.circular(24));
    return FadeTransition(
      opacity: _progress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ModalBarrier(dismissible: false, color: Color(0x99000000)),
          SafeArea(
            minimum: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: ScaleTransition(
                  scale: _scale,
                  child: Semantics(
                    scopesRoute: true,
                    namesRoute: true,
                    explicitChildNodes: true,
                    label: LegalConsentPrompt.title,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        boxShadow: tokens.shadows(GalleryElevation.modal),
                      ),
                      child: Material(
                        color: tokens.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: radius,
                          side: BorderSide(color: tokens.line),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                LegalConsentPrompt.title,
                                style: GalleryTypography.section.copyWith(
                                  color: tokens.text,
                                ),
                              ),
                              const SizedBox(height: 12),
                              widget.prompt.content(
                                onLinkNotice:
                                    (context, message, {required copied}) =>
                                        GalleryFeedbackHost.show(
                                          context,
                                          message,
                                          type: copied
                                              ? GalleryFeedbackType.info
                                              : GalleryFeedbackType.error,
                                        ),
                              ),
                              const SizedBox(height: 16),
                              OverflowBar(
                                alignment: MainAxisAlignment.end,
                                overflowAlignment: OverflowBarAlignment.end,
                                spacing: 8,
                                overflowSpacing: 4,
                                children: widget.prompt.actions(
                                  afterSave: _close,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
