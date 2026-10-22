import 'package:flutter/widgets.dart';

import 'app/trafarch_app.dart';
import 'app/theme/safe_error_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  installReleaseErrorPresentation();
  runApp(const TransitCardAnalyzerApp());
}
