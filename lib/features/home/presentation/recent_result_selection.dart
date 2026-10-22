enum RecentResultKind { card, qr, bank }

/// Tracks identity of completed results, independently of UI subscriptions.
/// Each surface owns an instance so manual selection stays local to that page.
class RecentResultSelection {
  Object? _card;
  Object? _qr;
  Object? _bank;
  RecentResultKind selected = RecentResultKind.card;

  RecentResultSelection({Object? card, Object? qr, Object? bank})
    : _card = card,
      _qr = qr,
      _bank = bank {
    if (card == null && qr == null && bank != null) {
      selected = RecentResultKind.bank;
    } else if (card == null && qr != null) {
      selected = RecentResultKind.qr;
    }
  }

  void observe({Object? card, Object? qr, Object? bank}) {
    if (!identical(card, _card) && card != null) {
      selected = RecentResultKind.card;
    }
    if (!identical(qr, _qr) && qr != null) selected = RecentResultKind.qr;
    if (!identical(bank, _bank) && bank != null) {
      selected = RecentResultKind.bank;
    }
    _card = card;
    _qr = qr;
    _bank = bank;
  }

  RecentResultKind resolve(List<RecentResultKind> available) =>
      available.contains(selected) ? selected : available.first;
}
