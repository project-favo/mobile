import '../../features/auth/data/repositories/interaction_repository.dart';
import '../../features/auth/data/services/auth_service.dart';
import '../utils/session_helper.dart';

/// Tüm takip edilen kullanıcı id’leri (tek batch); bildirimde Follow/Following flash’ını önler.
class FollowingIdSetCache {
  FollowingIdSetCache._();
  static final FollowingIdSetCache instance = FollowingIdSetCache._();

  final Set<String> _ids = <String>{};
  bool _loaded = false;
  Future<void>? _inflight;
  String? _lastUserId;

  bool get isReady => _loaded;
  bool contains(String id) => _ids.contains(id);
  Set<String> get snapshot => Set<String>.unmodifiable(_ids);

  void invalidate() {
    _inflight = null;
    _loaded = false;
    _ids.clear();
    _lastUserId = null;
  }

  void applyToggle(String userId, bool nowFollowing) {
    if (userId.isEmpty) return;
    if (nowFollowing) {
      _ids.add(userId);
    } else {
      _ids.remove(userId);
    }
  }

  void replaceFromSet(Set<String> set) {
    _ids
      ..clear()
      ..addAll(set);
    _loaded = true;
  }

  /// Aynı anda tek istek; Home ve Notifications öncesi çağrılabilir.
  Future<void> ensureLoaded(
    InteractionRepository interactions,
    AuthService auth,
    SessionHelper session, {
    bool force = false,
  }) async {
    if (!force && _loaded && _inflight == null) return;
    if (_inflight != null) {
      await _inflight;
      return;
    }
    _inflight = _load(interactions, auth, session);
    try {
      await _inflight;
    } finally {
      _inflight = null;
    }
  }

  Future<void> _load(
    InteractionRepository interactions,
    AuthService auth,
    SessionHelper session,
  ) async {
    final t = await session.ensureSession();
    if (t == null) {
      _loaded = true;
      return;
    }
    try {
      final me = await auth.getMe();
      if (me.id != _lastUserId) {
        _ids.clear();
        _lastUserId = me.id;
      }
      if (me.id.isEmpty) {
        _loaded = true;
        return;
      }
      final s = await interactions.getFollowingIdSet(me.id);
      _ids
        ..clear()
        ..addAll(s);
    } catch (_) {
      // Ağ/401; boş set ile _loaded — ActivityController is-following yedeği
    } finally {
      _loaded = true;
    }
  }
}
