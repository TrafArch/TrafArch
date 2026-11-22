import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app/trafarch_app.dart';
import 'app/legal_consent_gate.dart';
import 'app/theme/safe_error_screen.dart';
import 'app/third_party_licenses.dart';
import 'gallery/gallery_consent_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerThirdPartyLicenses();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  installReleaseErrorPresentation();
  runApp(
    const LegalConsentGate(
      screenBuilder: GalleryConsentScreen.new,
      child: TransitCardAnalyzerApp(enableLiveBeta: true, initialLiveUi: true),
    ),
  );
}
