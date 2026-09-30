namespace FieldInspector.Api;

/// Один локальный процесс API: упорядочиваем записи и чтение снимка изменений.
/// Курсор — время последнего COMMIT, а не окончания HTTP-запроса.
/// Поэтому запись между чтениями таблиц не выпадет из следующей синхронизации.
public sealed class SyncGate : IDisposable
{
    public SemaphoreSlim Mutex { get; } = new(1, 1);
    public long LastCommittedTicks { get; private set; } = DateTimeOffset.UnixEpoch.UtcTicks;
    // Выравнивание до микросекунд: Dart DateTime не хранит остаток тактов по 100 нс.
    public long NextTimestamp() => Math.Max(DateTimeOffset.UtcNow.UtcTicks / 10 * 10, LastCommittedTicks + 10);
    public void Commit(long timestamp) => LastCommittedTicks = Math.Max(timestamp, LastCommittedTicks);
    public void Dispose() => Mutex.Dispose();
}
