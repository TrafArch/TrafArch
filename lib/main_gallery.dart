import 'package:flutter/widgets.dart';

import 'app/theme/safe_error_screen.dart';
import 'app/internal_preview_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  installReleaseErrorPresentation();
  runApp(const InternalPreviewApp());
}
