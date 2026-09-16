using FieldInspector.Api.Data;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.EntityFrameworkCore;

namespace FieldInspector.Api;

public static class ApiEndpoints
{
    public static void MapInspectorApi(this WebApplication app)
    {
        app.MapGet("/objects", async (InspectorDbContext db, CancellationToken ct) =>
            (await db.Objects.AsNoTracking().OrderBy(x => x.Id).ToArrayAsync(ct)).Select(x => x.ToDto()))
            .WithSummary("All technical objects").Produces<ObjectDto[]>();
        app.MapGet("/objects/{id}", async (string id, InspectorDbContext db, CancellationToken ct) =>
            await db.Objects.AsNoTracking().SingleOrDefaultAsync(x => x.Id == id, ct) is { } entity
                ? Results.Ok(entity.ToDto()) : Results.NotFound());
        app.MapGet("/visits/{id}", async (string id, InspectorDbContext db, CancellationToken ct) =>
            await db.Visits.AsNoTracking().SingleOrDefaultAsync(x => x.Id == id, ct) is { } entity
                ? Results.Ok(entity.ToDto()) : Results.NotFound());

        app.MapGet("/routes/today", async (InspectorDbContext db, CancellationToken ct) =>
        {
            var today = DateOnly.FromDateTime(DateTime.UtcNow);
            return (await db.Routes.AsNoTracking().Where(x => x.Date == today).OrderBy(x => x.Id).ToArrayAsync(ct))
                .Select(x => x.ToDto());
        }).WithSummary("Today's routes (UTC date)").Produces<RouteDto[]>();

        app.MapPatch("/objects/{id}", PatchObject).WithSummary("Versioned object edit; Idempotency-Key required").Produces<ObjectDto>().ProducesProblem(409);
        app.MapPost("/visits", SaveVisit).WithSummary("Create immutable visit; safe to retry the same payload")
            .Produces<VisitDto>(201).Produces<VisitDto>().ProducesProblem(400).ProducesProblem(409);
        app.MapPost("/routes", RegisterRoute).WithSummary("Idempotently register a locally created route")
            .Produces<RouteDto>(201).Produces<RouteDto>().ProducesProblem(400).ProducesProblem(409);
        app.MapPost("/location/batch", SavePoints).WithSummary("Atomic, idempotent batch of up to 500 location points")
            .Produces<LocationBatchResponse>().ProducesProblem(400).ProducesProblem(409);
        app.MapGet("/sync", ReadChanges).WithSummary("Delta since a previous cursor; omit since for initial sync")
            .Produces<SyncResponse>().ProducesProblem(400);
    }

    private static readonly JsonSerializerOptions SyncJson = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) }
    };

    private static async Task<IResult> PatchObject(string id, ObjectPatchRequest request,
        HttpRequest http, InspectorDbContext db, SyncGate gate, CancellationToken ct)
    {
        var key = http.Headers["Idempotency-Key"].ToString();
        if (!ValidId(key) || id != request.Id || !ValidId(id) || string.IsNullOrWhiteSpace(request.Name)
            || request.Name.Length > 200 || request.Address is null
            || !ValidCoordinates(request.Latitude, request.Longitude, 0)
            || !Enum.IsDefined(request.Status) || !Enum.IsDefined(request.Priority) || request.ServerVersion is < 1)
            return Invalid("Valid object fields and Idempotency-Key are required.");
        await gate.Mutex.WaitAsync(ct);
        try
        {
            var requestJson = JsonSerializer.Serialize(request, SyncJson);
            var receipt = await db.OperationReceipts.AsNoTracking().SingleOrDefaultAsync(x => x.Key == key, ct);
            if (receipt is not null)
                return receipt.RequestJson == requestJson
                    ? Results.Content(receipt.ResponseJson, "application/json")
                    : Conflict("Idempotency-Key was already used for a different request.");
            var entity = await db.Objects.SingleOrDefaultAsync(x => x.Id == id, ct);
            if (entity is null) return Results.NotFound();
            if (request.ServerVersion != entity.ServerVersion)
                return Results.Problem(statusCode: 409, title: "Object version conflict",
                    extensions: new Dictionary<string, object?> { ["current"] = entity.ToDto() });
            entity.Name = request.Name;
            entity.Address = request.Address;
            entity.Latitude = request.Latitude;
            entity.Longitude = request.Longitude;
            entity.Status = request.Status;
            entity.Priority = request.Priority;
            entity.ServerVersion++;
            entity.UpdatedAtTicks = gate.NextTimestamp();
            var responseJson = JsonSerializer.Serialize(entity.ToDto(), SyncJson);
            db.OperationReceipts.Add(new OperationReceipt { Key = key, RequestJson = requestJson, ResponseJson = responseJson });
            // EF SaveChanges commits the versioned entity and durable receipt atomically.
            // No receipt for 409: explicit resolution must create a NEW operation key.
            try { await db.SaveChangesAsync(ct); }
            catch (DbUpdateConcurrencyException)
            {
                db.ChangeTracker.Clear();
                var current = await db.Objects.AsNoTracking().SingleAsync(x => x.Id == id, ct);
                return Results.Problem(statusCode: 409, title: "Object version conflict",
                    extensions: new Dictionary<string, object?> { ["current"] = current.ToDto() });
            }
            gate.Commit(entity.UpdatedAtTicks);
            return Results.Content(responseJson, "application/json");
        }
        finally { gate.Mutex.Release(); }
    }
    private static async Task<IResult> RegisterRoute(RegisterRouteRequest request, InspectorDbContext db, SyncGate gate, CancellationToken ct)
    {
        if (!ValidId(request.Id) || string.IsNullOrWhiteSpace(request.Name) || request.Name.Length > 200 || request.Date == default)
            return Invalid("Route id, name and date are required.");
        await gate.Mutex.WaitAsync(ct);
        try
        {
            var route = await db.Routes.SingleOrDefaultAsync(r => r.Id == request.Id, ct);
            if (route is not null)
                return route.Name == request.Name && route.Date == request.Date ? Results.Ok(route.ToDto()) : Conflict("Route id already has different registration data.");
            route = new FieldRoute { Id = request.Id, Name = request.Name, Date = request.Date, UpdatedAtTicks = gate.NextTimestamp() };
            db.Routes.Add(route);
            await db.SaveChangesAsync(ct);
            gate.Commit(route.UpdatedAtTicks);
            return Results.Json(route.ToDto(), statusCode: 201);
        }
        finally { gate.Mutex.Release(); }
    }

    private static async Task<IResult> SaveVisit(VisitRequest request, InspectorDbContext db, SyncGate gate, CancellationToken ct)
    {
        if (!ValidId(request.Id) || !ValidId(request.ObjectId) || (request.RouteId is not null && !ValidId(request.RouteId))
            || !ValidCoordinates(request.Latitude, request.Longitude, request.Accuracy)
            || !Enum.IsDefined(request.Status) || request.CreatedAt == default || request.ServerVersion is < 1)
            return Invalid("Valid id, objectId, coordinates, accuracy, status and createdAt are required; serverVersion must be null or positive.");

        await gate.Mutex.WaitAsync(ct);
        try
        {
            if (!await db.Objects.AnyAsync(x => x.Id == request.ObjectId, ct)) return Invalid("Unknown objectId.");
            if (request.RouteId is not null && !await db.Routes.AnyAsync(x => x.Id == request.RouteId, ct)) return Invalid("Unknown routeId.");
            var visit = await db.Visits.SingleOrDefaultAsync(x => x.Id == request.Id, ct);
            // При потере ответа повторный POST возвращает прежний результат,
            // даже если клиент ещё не успел получить serverVersion.
            if (visit is not null && Same(visit, request)) return Results.Ok(visit.ToDto());
            if (visit is null && request.ServerVersion is not null)
                return Conflict("Visit does not exist. Create with serverVersion=null.");
            if (visit is not null)
                return Results.Problem(statusCode: 409, title: "Immutable visit conflict",
                    extensions: new Dictionary<string, object?> { ["current"] = visit.ToDto() });

            var created = visit is null;
            visit ??= new Visit { Id = request.Id };
            visit.ObjectId = request.ObjectId;
            visit.RouteId = request.RouteId;
            visit.Status = request.Status;
            visit.Latitude = request.Latitude;
            visit.Longitude = request.Longitude;
            visit.Accuracy = request.Accuracy;
            visit.CreatedAtTicks = request.CreatedAt.UtcTicks;
            visit.UpdatedAtTicks = gate.NextTimestamp();
            visit.ServerVersion++;
            if (created) db.Visits.Add(visit);
            // Visit and object status share EF's SaveChanges transaction. A later
            // GET /objects must not undo the mobile app's completed check-in.
            if (request.Status == VisitStatus.Completed)
            {
                var target = await db.Objects.SingleAsync(x => x.Id == request.ObjectId, ct);
                target.Status = ObjectStatus.Visited;
                target.ServerVersion++;
                target.UpdatedAtTicks = visit.UpdatedAtTicks;
            }
            try { await db.SaveChangesAsync(ct); }
            catch (DbUpdateConcurrencyException) { return Conflict("Visit was changed by another writer."); }
            gate.Commit(visit.UpdatedAtTicks);
            return Results.Json(visit.ToDto(), statusCode: created ? 201 : 200);
        }
        finally { gate.Mutex.Release(); }
    }

    private static async Task<IResult> SavePoints(LocationBatchRequest request, InspectorDbContext db, SyncGate gate, CancellationToken ct)
    {
        if (request.Points is not { Count: > 0 and <= 500 } points) return Invalid("points must contain 1 to 500 items.");
        if (points.Any(x => x is null || !ValidId(x.Id) || !ValidId(x.RouteId)
                || !ValidCoordinates(x.Latitude, x.Longitude, x.Accuracy)
                || (x.Speed is double speed && (!double.IsFinite(speed) || speed < 0)) || x.Timestamp == default))
            return Invalid("Every point needs valid id, routeId, coordinates, accuracy and timestamp; speed is null or non-negative.");
        if (points.Select(x => x.Id).Distinct(StringComparer.Ordinal).Count() != points.Count)
            return Invalid("Duplicate point IDs inside one batch.");

        await gate.Mutex.WaitAsync(ct);
        try
        {
            var routeIds = points.Select(x => x.RouteId).Distinct().ToArray();
            if (await db.Routes.CountAsync(x => routeIds.Contains(x.Id), ct) != routeIds.Length) return Invalid("Unknown routeId in batch.");
            var ids = points.Select(x => x.Id).ToArray();
            var existing = await db.LocationPoints.Where(x => ids.Contains(x.Id)).ToDictionaryAsync(x => x.Id, ct);
            // Сначала валидируем весь batch, затем делаем один commit. Частично
            // принятых пакетов и скрытых дубликатов при повторе не возникает.
            foreach (var point in points)
                if (existing.TryGetValue(point.Id, out var previous) && !Same(previous, point))
                    return Conflict($"Point '{point.Id}' already exists with a different payload. Points are immutable.");
            var timestamp = gate.NextTimestamp();
            var accepted = new List<LocationPoint>();
            foreach (var point in points)
            {
                if (existing.TryGetValue(point.Id, out var previous)) { accepted.Add(previous); continue; }
                var entity = new LocationPoint { Id = point.Id, RouteId = point.RouteId,
                    Latitude = point.Latitude, Longitude = point.Longitude, Accuracy = point.Accuracy,
                    Speed = point.Speed, TimestampTicks = point.Timestamp.UtcTicks, UpdatedAtTicks = timestamp };
                db.LocationPoints.Add(entity);
                accepted.Add(entity);
            }
            var inserted = points.Count - existing.Count;
            if (inserted > 0)
            {
                await using var transaction = await db.Database.BeginTransactionAsync(ct);
                await db.SaveChangesAsync(ct);
                await transaction.CommitAsync(ct);
                gate.Commit(timestamp);
            }
            return Results.Ok(new LocationBatchResponse(inserted, existing.Count, accepted.Select(x => x.ToDto()).ToArray()));
        }
        finally { gate.Mutex.Release(); }
    }

    private static async Task<IResult> ReadChanges(DateTimeOffset? since, InspectorDbContext db, SyncGate gate, CancellationToken ct)
    {
        var timestamp = (since ?? DateTimeOffset.UnixEpoch).UtcTicks;
        await gate.Mutex.WaitAsync(ct);
        try
        {
            if (timestamp > Math.Max(DateTimeOffset.UtcNow.UtcTicks, gate.LastCommittedTicks))
                return Invalid("since cannot be in the future. Use cursor from the previous sync response.");
            var objects = await db.Objects.AsNoTracking().Where(x => x.UpdatedAtTicks > timestamp).OrderBy(x => x.Id).ToArrayAsync(ct);
            var routes = await db.Routes.AsNoTracking().Where(x => x.UpdatedAtTicks > timestamp).OrderBy(x => x.Id).ToArrayAsync(ct);
            var visits = await db.Visits.AsNoTracking().Where(x => x.UpdatedAtTicks > timestamp).OrderBy(x => x.Id).ToArrayAsync(ct);
            var points = await db.LocationPoints.AsNoTracking().Where(x => x.UpdatedAtTicks > timestamp).OrderBy(x => x.Id).ToArrayAsync(ct);
            return Results.Ok(new SyncResponse(Dto.Time(gate.LastCommittedTicks), DateTimeOffset.UtcNow,
                objects.Select(x => x.ToDto()).ToArray(), routes.Select(x => x.ToDto()).ToArray(),
                visits.Select(x => x.ToDto()).ToArray(), points.Select(x => x.ToDto()).ToArray()));
        }
        finally { gate.Mutex.Release(); }
    }

    private static bool ValidId(string? id) => !string.IsNullOrWhiteSpace(id) && id.Length <= 100;
    private static bool ValidCoordinates(double latitude, double longitude, double accuracy) =>
        double.IsFinite(latitude) && latitude is >= -90 and <= 90
        && double.IsFinite(longitude) && longitude is >= -180 and <= 180 && double.IsFinite(accuracy) && accuracy >= 0;
    private static IResult Invalid(string detail) => Results.Problem(statusCode: 400, title: "Invalid request", detail: detail);
    private static IResult Conflict(string detail) => Results.Problem(statusCode: 409, title: "Conflict", detail: detail);
    private static bool Same(Visit x, VisitRequest y) => x.ObjectId == y.ObjectId && x.RouteId == y.RouteId
        && x.Status == y.Status && x.Latitude == y.Latitude && x.Longitude == y.Longitude
        && x.Accuracy == y.Accuracy && x.CreatedAtTicks == y.CreatedAt.UtcTicks;
    private static bool Same(LocationPoint x, LocationPointRequest y) => x.RouteId == y.RouteId
        && x.Latitude == y.Latitude && x.Longitude == y.Longitude && x.Accuracy == y.Accuracy
        && x.Speed == y.Speed && x.TimestampTicks == y.Timestamp.UtcTicks;
}

