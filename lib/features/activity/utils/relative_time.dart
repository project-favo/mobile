/// Short relative time labels: 2s, 5m, 1h, 3d.
String formatActivityRelativeTime(DateTime time, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  var diff = reference.difference(time);
  if (diff.isNegative) diff = Duration.zero;

  if (diff.inSeconds < 60) return '${diff.inSeconds}s';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return '${time.day}/${time.month}/${time.year % 100}';
}
