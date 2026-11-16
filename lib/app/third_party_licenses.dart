import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Makes the bundled decoder table's attribution available in app licenses.
void registerThirdPartyLicenses() {
  LicenseRegistry.addLicense(() async* {
    final attribution = await rootBundle.loadString(
      'third_party/amusement_ic/README.md',
    );
    final license = await rootBundle.loadString(
      'third_party/amusement_ic/MPL-2.0.txt',
    );
    yield LicenseEntryWithLineBreaks([
      'PN532-Aime-Reader / Amusement IC substitution tables',
    ], '$attribution\n\n$license');
  });
}
