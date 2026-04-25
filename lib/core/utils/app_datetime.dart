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

/// Conversation list trailing: human-friendly date line + time on second line.
class ConversationPreviewTimeParts {
  const ConversationPreviewTimeParts({
    required this.dateLine,
    required this.timeLine,
  });

  /// e.g. `Today`, `Yesterday`, `24 Apr`, `24 Apr 2025` (never bare weekday — avoids ambiguity).
  final String dateLine;

  /// Always `HH:mm` (local).
  final String timeLine;
}

/// Today / Yesterday / always a real calendar date (`d MMM` or `d MMM y`) + time.
///
/// We do **not** show bare weekday names (`Wed`): two different Wednesdays would
/// look identical. Anything before yesterday uses explicit day–month (year if needed).
ConversationPreviewTimeParts conversationPreviewTimePartsFromBackend(
  String? timestamp, {
  String fallback = '—',
}) {
  final dt = parseBackendDateTimeToLocal(timestamp);
  if (dt == null) {
    return ConversationPreviewTimeParts(dateLine: fallback, timeLine: '');
  }
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final msgDay = DateTime(dt.year, dt.month, dt.day);
  final timeLine = DateFormat('HH:mm').format(dt);

  if (msgDay == today) {
    return ConversationPreviewTimeParts(dateLine: 'Today', timeLine: timeLine);
  }
  final yesterday = today.subtract(const Duration(days: 1));
  if (msgDay == yesterday) {
    return ConversationPreviewTimeParts(
      dateLine: 'Yesterday',
      timeLine: timeLine,
    );
  }
  if (dt.year == now.year) {
    return ConversationPreviewTimeParts(
      dateLine: DateFormat('d MMM').format(dt),
      timeLine: timeLine,
    );
  }
  return ConversationPreviewTimeParts(
    dateLine: DateFormat('d MMM y').format(dt),
    timeLine: timeLine,
  );
}

/// Single-line fallback (e.g. logging).
String formatConversationPreviewTimeFromBackend(
  String? timestamp, {
  String fallback = '',
}) {
  final p = conversationPreviewTimePartsFromBackend(timestamp, fallback: fallback);
  if (p.timeLine.isEmpty) return p.dateLine;
  return '${p.dateLine} · ${p.timeLine}';
}

String formatDateTimeFromBackend(
  String? timestamp, {
  String fallback = '-',
}) {
  final dt = parseBackendDateTimeToLocal(timestamp);
  if (dt == null) return fallback;
  return formatDateTime(dt);
}
