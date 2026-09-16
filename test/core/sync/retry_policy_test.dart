import 'package:flutter_test/flutter_test.dart';
import 'package:workingwithmaps/core/sync/retry_policy.dart';

void main() {
  test('Backoff doubles and stays capped after prolonged offline use', () {
    const policy = RetryPolicy();
    expect([1, 2, 3, 4].map((n) => policy.delay(n).inSeconds), [5, 10, 20, 40]);
    var previous = Duration.zero;
    for (var attempt = 1; attempt <= 1000; attempt++) {
      final delay = policy.delay(attempt);
      expect(delay, greaterThanOrEqualTo(previous));
      expect(delay, lessThanOrEqualTo(const Duration(minutes: 15)));
      previous = delay;
    }
    expect(previous, const Duration(minutes: 15));
  });

  test(
    'Custom cap and zero-based legacy attempt do not skip initial delay',
    () {
      const policy = RetryPolicy(
        initial: Duration(seconds: 3),
        maximum: Duration(seconds: 10),
      );
      expect(policy.delay(0), const Duration(seconds: 3));
      expect(policy.delay(2), const Duration(seconds: 6));
      expect(policy.delay(3), const Duration(seconds: 10));
    },
  );
}
