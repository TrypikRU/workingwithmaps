using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;

namespace FieldInspector.Api.Data;

public static class SeedData
{
    public static async Task Initialize(InspectorDbContext db, SyncGate gate)
    {
        // EnsureCreated достаточно для одноразового локального test backend.
        // База Flutter никогда не открывается этим процессом.
        await db.Database.EnsureCreatedAsync();
        await using var transaction = await db.Database.BeginTransactionAsync();
        // Маленькая additive migration для уже существующих pet-баз. EnsureCreated
        // не обновляет таблицы. Проверка схемы и ALTER выполняются без удаления данных.
        var connection = db.Database.GetDbConnection();
        await using (var command = connection.CreateCommand())
        {
            command.Transaction = transaction.GetDbTransaction();
            command.CommandText = "PRAGMA table_info(Objects)";
            var hasVersion = false;
            await using (var reader = await command.ExecuteReaderAsync())
                while (await reader.ReadAsync()) hasVersion |= reader.GetString(1) == "ServerVersion";
            if (!hasVersion)
                await db.Database.ExecuteSqlRawAsync("ALTER TABLE Objects ADD COLUMN ServerVersion INTEGER NOT NULL DEFAULT 1");
        }
        await db.Database.ExecuteSqlRawAsync("CREATE TABLE IF NOT EXISTS OperationReceipts (Key TEXT NOT NULL PRIMARY KEY, RequestJson TEXT NOT NULL, ResponseJson TEXT NOT NULL)");
        var timestamp = DateTimeOffset.UtcNow.UtcTicks / 10 * 10;
        if (!await db.Objects.AnyAsync())
        {
            db.Objects.AddRange(
                Object("demo-1", "Тепловой пункт № 1", "Москва, ул. Покровка, 10", 55.7586, 37.6442, ObjectStatus.Planned, ObjectPriority.High),
                Object("demo-2", "Распределительный шкаф № 2", "Москва, Чистопрудный бульвар, 12", 55.7618, 37.6425, ObjectStatus.Visited, ObjectPriority.Normal),
                Object("demo-3", "Насосная станция № 3", "Москва, ул. Маросейка, 8", 55.7573, 37.6359, ObjectStatus.Error, ObjectPriority.Critical),
                Object("demo-4", "Узел связи № 4", "Москва, Архангельский переулок, 7", 55.7602, 37.6363, ObjectStatus.Planned, ObjectPriority.Low),
                Object("demo-5", "Электрощитовая № 5", "Москва, ул. Жуковского, 4", 55.7634, 37.6495, ObjectStatus.Visited, ObjectPriority.High));
            await db.SaveChangesAsync();
        }
        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        if (!await db.Routes.AnyAsync(x => x.Date == today))
        {
            var ids = await db.Objects.OrderBy(x => x.Id).Select(x => x.Id).ToArrayAsync();
            db.Routes.Add(new FieldRoute { Id = $"demo-route-{today:yyyyMMdd}", Name = "Тестовый обход",
                Date = today, ObjectIdsJson = JsonSerializer.Serialize(ids), UpdatedAtTicks = timestamp });
            await db.SaveChangesAsync();
        }
        await transaction.CommitAsync();
        // Восстанавливаем high-water mark из диска после перезапуска API.
        foreach (var latest in new[] {
            await db.Objects.MaxAsync(x => (long?)x.UpdatedAtTicks),
            await db.Routes.MaxAsync(x => (long?)x.UpdatedAtTicks),
            await db.Visits.MaxAsync(x => (long?)x.UpdatedAtTicks),
            await db.LocationPoints.MaxAsync(x => (long?)x.UpdatedAtTicks) })
            gate.Commit(latest ?? DateTimeOffset.UnixEpoch.UtcTicks);

        TechnicalObject Object(string id, string name, string address, double lat, double lon, ObjectStatus status, ObjectPriority priority)
            => new() { Id = id, Name = name, Address = address, Latitude = lat, Longitude = lon,
                Status = status, Priority = priority, UpdatedAtTicks = timestamp };
    }
}

