namespace FieldInspector.Api;

/// Один локальный процесс API: сериализуем записи и чтение delta snapshot.
/// Cursor — timestamp последнего COMMIT, а не время окончания HTTP-запроса.
/// Поэтому запись между чтениями таблиц не выпадет из следующей синхронизации.
public sealed class SyncGate : IDisposable
{
    public SemaphoreSlim Mutex { get; } = new(1, 1);
    public long LastCommittedTicks { get; private set; } = DateTimeOffset.UnixEpoch.UtcTicks;
    // Выравнивание до микросекунд: Dart DateTime не хранит остаток 100 ns ticks.
    public long NextTimestamp() => Math.Max(DateTimeOffset.UtcNow.UtcTicks / 10 * 10, LastCommittedTicks + 10);
    public void Commit(long timestamp) => LastCommittedTicks = Math.Max(timestamp, LastCommittedTicks);
    public void Dispose() => Mutex.Dispose();
}
