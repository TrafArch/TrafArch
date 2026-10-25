enum RecentResultKind { card, bank }

/// Tracks identity of completed results, independently of UI subscriptions.
/// Each surface owns an instance so manual selection stays local to that page.
class RecentResultSelection {
  Object? _card;
  Object? _bank;
  RecentResultKind selected = RecentResultKind.card;

  RecentResultSelection({Object? card, Object? bank})
    : _card = card,
      _bank = bank {
    if (card == null && bank != null) {
      selected = RecentResultKind.bank;
    }
  }

  void observe({Object? card, Object? bank}) {
    if (!identical(card, _card) && card != null) {
      selected = RecentResultKind.card;
    }
    if (!identical(bank, _bank) && bank != null) {
      selected = RecentResultKind.bank;
    }
    _card = card;
    _bank = bank;
  }

  RecentResultKind resolve(List<RecentResultKind> available) =>
      available.contains(selected) ? selected : available.first;
}
