import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../network/api_client.dart';
import 'resolve_media_url.dart';

/// Profil / avatar görselleri için ham byte yükler.
/// Önce [ApiClient] (Authorization Bearer) ile dener; korumalı dosya uçları için gerekli.
/// Gerekirse yetkisiz [Dio] ile tekrar dener (herkese açık CDN vb.).
Future<Uint8List?> loadProfileImageBytesFromRaw(String? raw) async {
  final resolved = resolveMediaUrl(raw);
  if (resolved == null || resolved.isEmpty) return null;
  if (resolved.startsWith('data:')) {
    return decodeProfilePhotoBytes(resolved);
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
    if (withAuth != null && withAuth.isNotEmpty) return withAuth;
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
  return fetchWith(plain);
}
