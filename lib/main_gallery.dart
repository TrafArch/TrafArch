import 'package:flutter/widgets.dart';

import 'app/theme/safe_error_screen.dart';
import 'app/internal_preview_app.dart';
import 'app/third_party_licenses.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerThirdPartyLicenses();
  installReleaseErrorPresentation();
  runApp(const InternalPreviewApp());
}
