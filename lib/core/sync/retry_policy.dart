class RetryPolicy {
  const RetryPolicy({
    this.initial = const Duration(seconds: 5),
    this.maximum = const Duration(minutes: 15),
  });
  final Duration initial;
  final Duration maximum;

  Duration delay(int attemptCount) {
    // Ограничиваем степень до сдвига: бесконечная очередь без сети не переполнит int.
    final exponent = (attemptCount - 1).clamp(0, 30);
    return Duration(
      milliseconds: (initial.inMilliseconds * (1 << exponent)).clamp(
        0,
        maximum.inMilliseconds,
      ),
    );
  }
}
