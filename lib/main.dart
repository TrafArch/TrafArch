import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app/trafarch_app.dart';
import 'app/theme/safe_error_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  installReleaseErrorPresentation();
  runApp(const TransitCardAnalyzerApp());
}
