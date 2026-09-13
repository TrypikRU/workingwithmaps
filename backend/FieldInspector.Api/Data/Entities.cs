namespace FieldInspector.Api.Data;

public enum ObjectStatus { Planned, Visited, Error }
public enum ObjectPriority { Low, Normal, High, Critical }
public enum RouteStatus { Planned, Active, Completed }
public enum VisitStatus { Completed, Failed }

public sealed class TechnicalObject
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    public string Address { get; set; } = "";
    public double Latitude { get; set; }
    public double Longitude { get; set; }
    public ObjectStatus Status { get; set; }
    public ObjectPriority Priority { get; set; }
    public long UpdatedAtTicks { get; set; }
}

public sealed class FieldRoute
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    public DateOnly Date { get; set; }
    public RouteStatus Status { get; set; }
    // Для read-only тестовых обходов достаточно упорядоченного JSON-массива ID.
    public string ObjectIdsJson { get; set; } = "[]";
    public long UpdatedAtTicks { get; set; }
}

public sealed class Visit
{
    public string Id { get; set; } = "";
    public string ObjectId { get; set; } = "";
    public string? RouteId { get; set; }
    public VisitStatus Status { get; set; }
    public double Latitude { get; set; }
    public double Longitude { get; set; }
    public double Accuracy { get; set; }
    public long CreatedAtTicks { get; set; }
    public long UpdatedAtTicks { get; set; }
    public long ServerVersion { get; set; }
}

public sealed class LocationPoint
{
    public string Id { get; set; } = "";
    public string RouteId { get; set; } = "";
    public double Latitude { get; set; }
    public double Longitude { get; set; }
    public double Accuracy { get; set; }
    public double? Speed { get; set; }
    public long TimestampTicks { get; set; }
    public long UpdatedAtTicks { get; set; }
}
