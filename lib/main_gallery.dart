import 'package:flutter/widgets.dart';

import 'app/theme/safe_error_screen.dart';
import 'app/legal_consent_gate.dart';
import 'app/third_party_licenses.dart';
import 'app/trafarch_app.dart';
import 'gallery/gallery_consent_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerThirdPartyLicenses();
  installReleaseErrorPresentation();
  runApp(
    const LegalConsentGate(
      screenBuilder: GalleryConsentScreen.new,
      child: TransitCardAnalyzerApp(
        enableLiveBeta: true,
        initialLiveUi: true,
        enableUpdateChecks: false,
      ),
    ),
  );
}
