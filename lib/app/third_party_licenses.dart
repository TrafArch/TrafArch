import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Makes bundled third-party resources available in the app license registry.
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
  LicenseRegistry.addLicense(() async* {
    final attribution = await rootBundle.loadString(
      'third_party/railmapgen_palette/README.md',
    );
    final license = await rootBundle.loadString(
      'third_party/railmapgen_palette/GPL-3.0.txt',
    );
    yield LicenseEntryWithLineBreaks([
      'Rail Map Generator Palette data',
    ], '$attribution\n\n$license');
  });
}
