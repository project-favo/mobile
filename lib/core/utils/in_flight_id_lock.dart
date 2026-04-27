/// Aynı id için (ürün beğeni, yorum beğeni, follow vb.) hızlı ardışık isteği
/// yoksayar — state ve sunucu çift `toggle` ile bozulmaz.
class InFlightIdLock {
  final Set<String> _ids = <String>{};

  bool tryEnter(String id) {
    if (id.isEmpty) return true;
    if (_ids.contains(id)) return false;
    _ids.add(id);
    return true;
  }

  void leave(String id) {
    if (id.isNotEmpty) _ids.remove(id);
  }

  bool isHeld(String id) => id.isNotEmpty && _ids.contains(id);
}

/// Tek bir işlem (ör. detaydaki product like) için global kilitle.
class InFlightFlag {
  bool _busy = false;

  bool tryEnter() {
    if (_busy) return false;
    _busy = true;
    return true;
  }

  void leave() {
    _busy = false;
  }

  bool get isHeld => _busy;
}
