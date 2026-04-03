import 'dart:convert';
import 'dart:typed_data';

import '../config/api_config.dart';

/// Backend bazen tam URL, bazen `/api/...` gibi göreli path döner.
String? resolveMediaUrl(String? raw) {
  if (raw == null) return null;
  final t = raw.trim();
  if (t.isEmpty) return null;
  if (t.startsWith('http://') || t.startsWith('https://')) return t;
  if (t.startsWith('data:')) return t;
  final base = ApiConfig.baseUrl.replaceAll(RegExp(r'/+$'), '');
  final path = t.startsWith('/') ? t : '/$t';
  return '$base$path';
}

/// `data:image/png;base64,...` veya düz base64 (ör. `/api/auth/me` → `profilePhotoData`) için byte dizisi.
/// Backend bazen çok uzun satırda boşluk/satır sonu ekleyebilir; padding eksik olabilir.
Uint8List? decodeProfilePhotoBytes(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  var s = raw.trim();
  final dataIdx = s.indexOf('base64,');
  if (dataIdx != -1) {
    s = s.substring(dataIdx + 7);
  }
  s = s.replaceAll(RegExp(r'\s+'), '');
  if (s.isEmpty) return null;
  while (s.length % 4 != 0) {
    s += '=';
  }
  try {
    return base64Decode(s);
  } catch (_) {
    try {
      return base64Url.decode(s);
    } catch (_) {
      return null;
    }
  }
}
