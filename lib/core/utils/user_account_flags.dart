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

/// Askı / ban sinyali — `suspended` yanında çoğu backend `isSuspended`, `is_suspended`
/// veya `status: account_suspended` döndürür; sadece `m['suspended'] == true` yeterli değil.
bool isUserSuspendedSignalInMap(Map<String, dynamic> m) {
  if (m['suspended'] == true || m['isSuspended'] == true) return true;
  if (_truthy(m['suspended']) ||
      _truthy(m['isSuspended']) ||
      _truthy(m['is_suspended'])) {
    return true;
  }
  final st = (m['status'] ?? m['accountStatus'] ?? m['userStatus'] ?? '')
      .toString()
      .toLowerCase();
  if (st == 'suspended' ||
      st == 'account_suspended' ||
      st == 'user_suspended') {
    return true;
  }
  return false;
}

/// Listelerde / başka kullanıcı JSON’unda “görünmemeli” sinyali.
///
/// **Dikkat:** `isActive: false` veya `active: false` **kullanma** — bazı API’ler her
/// `/api/users/{id}` cevabında bu alanları yanıltıcı döndürebiliyor; tüm profilleri
/// askıda sanıyorduk. Sadece açık askı/uzaklaştırma sinyalleri.
bool isUserAccountInactiveInMap(Map<String, dynamic> m) {
  if (isUserSuspendedSignalInMap(m)) return true;
  if (_truthy(m['deactivated']) ||
      _truthy(m['banned']) ||
      _truthy(m['disabled'])) {
    return true;
  }
  if (m['isAccountInactive'] == true) return true;
  final st = (m['status'] ?? m['accountStatus'] ?? m['userStatus'] ?? '')
      .toString()
      .toLowerCase();
  if (st == 'inactive' ||
      st == 'disabled' ||
      st == 'banned' ||
      st == 'deactivated' ||
      st == 'closed') {
    return true;
  }
  return false;
}
