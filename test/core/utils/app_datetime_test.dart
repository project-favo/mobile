import 'package:flutter_test/flutter_test.dart';
import 'package:favo_mobile/core/utils/app_datetime.dart';

void main() {
  group('parseBackendDateTimeToLocal', () {
    test('treats timestamp without timezone suffix as UTC', () {
      final actual = parseBackendDateTimeToLocal('2026-04-23T15:40:00');
      final expected = DateTime.utc(2026, 4, 23, 15, 40, 0).toLocal();
      expect(actual, expected);
    });

    test('converts Z timestamp to local', () {
      final actual = parseBackendDateTimeToLocal('2026-04-23T15:40:00Z');
      final expected = DateTime.utc(2026, 4, 23, 15, 40, 0).toLocal();
      expect(actual, expected);
    });

    test('converts +03:00 timestamp correctly', () {
      final raw = '2026-04-23T18:40:00+03:00';
      final actual = parseBackendDateTimeToLocal(raw);
      final expected = DateTime.parse(raw).toLocal();
      expect(actual, expected);
    });

    test('returns null for null, empty and invalid input', () {
      expect(parseBackendDateTimeToLocal(null), isNull);
      expect(parseBackendDateTimeToLocal(''), isNull);
      expect(parseBackendDateTimeToLocal('not-a-date'), isNull);
    });
  });
}
