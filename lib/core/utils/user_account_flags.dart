// Kullanıcı JSON'unda deaktif / askı sinyali (isActive, status vb.).

bool _truthy(dynamic v) {
  if (v == true) return true;
  if (v is String) {
    final s = v.toLowerCase().trim();
    if (s == 'true' || s == '1' || s == 'yes') return true;
  }
  if (v is num && v == 1) return true;
  return false;
}

bool _falsy(dynamic v) {
  if (v == false) return true;
  if (v is String) {
    final s = v.toLowerCase().trim();
    if (s == 'false' || s == '0' || s == 'no') return true;
  }
  return false;
}

/// Hesap vitrin dışı / deaktif (başka kullanıcı profilinden çık).
bool isUserAccountInactiveInMap(Map<String, dynamic> m) {
  if (m['isActive'] is bool && (m['isActive'] as bool) == false) return true;
  if (m['active'] is bool && (m['active'] as bool) == false) return true;
  if (_falsy(m['isActive']) || _falsy(m['active']) || _falsy(m['enabled'])) {
    return true;
  }
  if (_truthy(m['deactivated']) ||
      _truthy(m['banned']) ||
      _truthy(m['suspended']) ||
      _truthy(m['disabled'])) {
    return true;
  }
  final st = (m['status'] ?? m['accountStatus'] ?? m['userStatus'] ?? '')
      .toString()
      .toLowerCase();
  if (st == 'inactive' ||
      st == 'disabled' ||
      st == 'banned' ||
      st == 'suspended' ||
      st == 'deactivated' ||
      st == 'closed') {
    return true;
  }
  return false;
}
