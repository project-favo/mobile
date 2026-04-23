import 'package:intl/intl.dart';

final RegExp _timezoneSuffixPattern = RegExp(
  r'(Z|[+-]\d{2}:\d{2}|[+-]\d{4})$',
  caseSensitive: false,
);

/// Parses backend timestamp safely and always returns local time.
///
/// Backend timestamps without timezone are treated as UTC.
DateTime? parseBackendDateTimeToLocal(String? timestamp) {
  final raw = timestamp?.trim();
  if (raw == null || raw.isEmpty) return null;
  try {
    final hasTimezone = _timezoneSuffixPattern.hasMatch(raw);
    final parsed = DateTime.parse(raw);
    if (!hasTimezone) {
      final asUtc = DateTime.utc(
        parsed.year,
        parsed.month,
        parsed.day,
        parsed.hour,
        parsed.minute,
        parsed.second,
        parsed.millisecond,
        parsed.microsecond,
      );
      return asUtc.toLocal();
    }
    return parsed.toLocal();
  } catch (_) {
    return null;
  }
}

String formatShortTime(DateTime dateTime) => DateFormat('HH:mm').format(dateTime);

String formatDateTime(DateTime dateTime) =>
    DateFormat('dd.MM.yyyy HH:mm').format(dateTime);

String formatShortTimeFromBackend(
  String? timestamp, {
  String fallback = '-',
}) {
  final dt = parseBackendDateTimeToLocal(timestamp);
  if (dt == null) return fallback;
  return formatShortTime(dt);
}

String formatDateTimeFromBackend(
  String? timestamp, {
  String fallback = '-',
}) {
  final dt = parseBackendDateTimeToLocal(timestamp);
  if (dt == null) return fallback;
  return formatDateTime(dt);
}
