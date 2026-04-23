// Yorum JSON'unda pasif / moderasyon / silinmiş sinyalleri (isActive=false vb.) tespit eder.

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

/// Yorum artık herkese açık değil / pasif (moderasyon, soft-delete, isActive=false).
bool isReviewDataInactiveOrHiddenInMap(Map<String, dynamic> m) {
  if (m['isActive'] is bool && (m['isActive'] as bool) == false) return true;
  if (m['active'] is bool && (m['active'] as bool) == false) return true;
  if (m['reviewActive'] is bool && (m['reviewActive'] as bool) == false) {
    return true;
  }
  for (final k in ['is_active', 'review_active', 'visible', 'published', 'public']) {
    if (_falsy(m[k])) return true;
  }
  if (_truthy(m['hidden']) ||
      _truthy(m['deleted']) ||
      _truthy(m['removed']) ||
      _truthy(m['softDeleted']) ||
      _truthy(m['rejected']) ||
      _truthy(m['suppressed'])) {
    return true;
  }
  final st = (m['status'] ??
          m['reviewStatus'] ??
          m['moderationStatus'] ??
          m['state'] ??
          '')
      .toString()
      .toLowerCase();
  if (st.contains('reject') ||
      st.contains('hidden') ||
      st == 'removed' ||
      st == 'deleted' ||
      st == 'inactive' ||
      st == 'banned' ||
      st == 'suppressed' ||
      st == 'dismissed') {
    return true;
  }
  return false;
}
