using System.Text.Json;
using FieldInspector.Api.Data;

namespace FieldInspector.Api;

public sealed record ObjectDto(string Id, string Name, string Address, double Latitude,
    double Longitude, ObjectStatus Status, ObjectPriority Priority, DateTimeOffset UpdatedAt, long ServerVersion);
// Полный набор редактируемых полей; geometry пока остаётся локальной.
public sealed record ObjectPatchRequest(string Id, string Name, string Address, double Latitude,
    double Longitude, ObjectStatus Status, ObjectPriority Priority, long? ServerVersion);
public sealed record RouteDto(string Id, string Name, DateOnly Date, RouteStatus Status,
    string[] ObjectIds, DateTimeOffset UpdatedAt);
public sealed record RegisterRouteRequest(string Id, string Name, DateOnly Date);
public sealed record VisitRequest(string Id, string ObjectId, string? RouteId, VisitStatus Status,
    double Latitude, double Longitude, double Accuracy, DateTimeOffset CreatedAt, long? ServerVersion);
public sealed record VisitDto(string Id, string ObjectId, string? RouteId, VisitStatus Status,
    double Latitude, double Longitude, double Accuracy, DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt, long ServerVersion);
public sealed record LocationPointRequest(string Id, string RouteId, double Latitude,
    double Longitude, double Accuracy, double? Speed, DateTimeOffset Timestamp);
public sealed record LocationBatchRequest(List<LocationPointRequest>? Points);
public sealed record LocationPointDto(string Id, string RouteId, double Latitude,
    double Longitude, double Accuracy, double? Speed, DateTimeOffset Timestamp, DateTimeOffset UpdatedAt);
public sealed record LocationBatchResponse(int Inserted, int Existing, LocationPointDto[] Accepted);
public sealed record SyncResponse(DateTimeOffset Cursor, DateTimeOffset ServerTime,
    ObjectDto[] Objects, RouteDto[] Routes, VisitDto[] Visits, LocationPointDto[] LocationPoints);

public static class Dto
{
    public static DateTimeOffset Time(long ticks) => new(ticks, TimeSpan.Zero);
    public static ObjectDto ToDto(this TechnicalObject x) => new(x.Id, x.Name, x.Address,
        x.Latitude, x.Longitude, x.Status, x.Priority, Time(x.UpdatedAtTicks), x.ServerVersion);
    public static RouteDto ToDto(this FieldRoute x) => new(x.Id, x.Name, x.Date, x.Status,
        JsonSerializer.Deserialize<string[]>(x.ObjectIdsJson)!, Time(x.UpdatedAtTicks));
    public static VisitDto ToDto(this Visit x) => new(x.Id, x.ObjectId, x.RouteId, x.Status,
        x.Latitude, x.Longitude, x.Accuracy, Time(x.CreatedAtTicks), Time(x.UpdatedAtTicks), x.ServerVersion);
    public static LocationPointDto ToDto(this LocationPoint x) => new(x.Id, x.RouteId,
        x.Latitude, x.Longitude, x.Accuracy, x.Speed, Time(x.TimestampTicks), Time(x.UpdatedAtTicks));
}
