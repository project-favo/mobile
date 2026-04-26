import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../network/api_client.dart';
import 'resolve_media_url.dart';

/// Bellek içi avatar önbelleği (aynı URL tekrar açılınca anında boyanır).
final Map<String, Uint8List> _profileImageByteCache = <String, Uint8List>{};
const int _profileImageByteCacheMax = 96;

String? _profileImageCacheKey(String? raw) {
  final resolved = resolveMediaUrl(raw);
  if (resolved == null || resolved.isEmpty) return null;
  if (resolved.startsWith('data:')) return null;
  return resolved;
}

/// Senkron: ağ isteği öncesi [ProfileAvatar] / [ProfileAvatarImage] ilk karede kullanır.
Uint8List? peekProfileImageBytes(String? raw) {
  final k = _profileImageCacheKey(raw);
  if (k == null) return null;
  return _profileImageByteCache[k];
}

void _rememberProfileImageBytes(String? raw, Uint8List bytes) {
  final k = _profileImageCacheKey(raw);
  if (k == null || bytes.isEmpty) return;
  if (_profileImageByteCache.length >= _profileImageByteCacheMax &&
      !_profileImageByteCache.containsKey(k)) {
    _profileImageByteCache.remove(_profileImageByteCache.keys.first);
  }
  _profileImageByteCache[k] = bytes;
}

/// Aynı URL altında güncellenmiş görsel veya yanlış pozitif cache için bayt önbelleğini siler.
void evictProfileImageBytesCacheForRaw(String? raw) {
  final k = _profileImageCacheKey(raw);
  if (k != null) _profileImageByteCache.remove(k);
}

/// Profil / avatar görselleri için ham byte yükler.
/// Önce [ApiClient] (Authorization Bearer) ile dener; korumalı dosya uçları için gerekli.
/// Gerekirse yetkisiz [Dio] ile tekrar dener (herkese açık CDN vb.).
Future<Uint8List?> loadProfileImageBytesFromRaw(String? raw) async {
  final resolved = resolveMediaUrl(raw);
  if (resolved == null || resolved.isEmpty) return null;
  if (resolved.startsWith('data:')) {
    return decodeProfilePhotoBytes(resolved);
  }

  final k = _profileImageCacheKey(raw);
  if (k != null) {
    final hit = _profileImageByteCache[k];
    if (hit != null && hit.isNotEmpty) return hit;
  }

  Future<Uint8List?> fetchWith(Dio dio) async {
    try {
      final r = await dio.getUri<List<int>>(
        Uri.parse(resolved),
        options: Options(
          responseType: ResponseType.bytes,
          validateStatus: (c) => c != null && c > 0 && c < 600,
        ),
      );
      final body = r.data;
      if (body == null || body.isEmpty) return null;
      if (r.statusCode == 401 || r.statusCode == 403 || r.statusCode == 404) {
        return null;
      }
      if (body is Uint8List) return body;
      return Uint8List.fromList(body);
    } catch (_) {
      return null;
    }
  }

  try {
    final withAuth = await fetchWith(ApiClient().dio);
    if (withAuth != null && withAuth.isNotEmpty) {
      _rememberProfileImageBytes(raw, withAuth);
      return withAuth;
    }
  } catch (_) {
    // ApiClient henüz initialize değilse vb.
  }

  final plain = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
      validateStatus: (c) => c != null && c > 0 && c < 600,
    ),
  );
  final out = await fetchWith(plain);
  if (out != null && out.isNotEmpty) {
    _rememberProfileImageBytes(raw, out);
  }
  return out;
}
