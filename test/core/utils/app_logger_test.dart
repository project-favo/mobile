import 'package:favo_mobile/core/utils/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppLogger.debug does not throw', () {
    expect(() => AppLogger.debug('msg'), returnsNormally);
    expect(() => AppLogger.debug('with err', StateError('x')), returnsNormally);
  });

  test('AppLogger.warnSilencedError does not throw', () {
    expect(
      () => AppLogger.warnSilencedError('ctx', Exception('e')),
      returnsNormally,
    );
  });
}
