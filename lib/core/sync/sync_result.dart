class SyncResult {
  const SyncResult({
    this.succeeded = 0,
    this.failed = 0,
    this.deferred = false,
  });
  final int succeeded;
  final int failed;
  final bool deferred;
}
