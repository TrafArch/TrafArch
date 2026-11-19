import '../../../protocols/felica/models/amusement_ic_data.dart';

/// Display identity from one validated frozen capture. Scalar card names and
/// IDm never fill missing fields; a damaged capture remains explicitly unknown.
class AmusementIcArchiveIdentity {
  const AmusementIcArchiveIdentity._({this.issuer, this.formattedAccessCode});

  factory AmusementIcArchiveIdentity.fromCapturedData(AmusementIcData? data) {
    final issuer = data?.issuer?.trim();
    final formatted = data?.formattedAccessCode;
    if (issuer == null || issuer.isEmpty || formatted == null) {
      return const AmusementIcArchiveIdentity._();
    }
    return AmusementIcArchiveIdentity._(
      issuer: issuer,
      formattedAccessCode: formatted,
    );
  }

  final String? issuer;
  final String? formattedAccessCode;

  String get defaultName => 'Amusement IC ( ${issuer ?? '发行品牌未知'} )';

  String displayName(String? customName) {
    final custom = customName?.trim();
    return custom == null || custom.isEmpty ? defaultName : custom;
  }

  String? subtitle(String? customName) =>
      customName?.trim().isNotEmpty == true ? defaultName : null;

  @override
  bool operator ==(Object other) =>
      other is AmusementIcArchiveIdentity &&
      issuer == other.issuer &&
      formattedAccessCode == other.formattedAccessCode;

  @override
  int get hashCode => Object.hash(issuer, formattedAccessCode);
}
