/// Compare issuing and accepting cities within the same code namespace.
/// Missing cities and all-zero/F placeholders cannot establish remote use.
bool isRemoteCardUse(String? cardCityCode, String? acceptingCityCode) {
  String? knownCity(String? code) {
    final city = code?.trim().toUpperCase();
    return city == null || city.isEmpty || RegExp(r'^[0F]+$').hasMatch(city)
        ? null
        : city;
  }

  final home = knownCity(cardCityCode);
  final destination = knownCity(acceptingCityCode);
  return home != null && destination != null && home != destination;
}
