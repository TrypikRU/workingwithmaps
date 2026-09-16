using Microsoft.EntityFrameworkCore;

namespace FieldInspector.Api.Data;

public sealed class InspectorDbContext(DbContextOptions<InspectorDbContext> options) : DbContext(options)
{
    public DbSet<TechnicalObject> Objects => Set<TechnicalObject>();
    public DbSet<FieldRoute> Routes => Set<FieldRoute>();
    public DbSet<Visit> Visits => Set<Visit>();
    public DbSet<OperationReceipt> OperationReceipts => Set<OperationReceipt>();
    public DbSet<LocationPoint> LocationPoints => Set<LocationPoint>();

    protected override void OnModelCreating(ModelBuilder model)
    {
        model.Entity<TechnicalObject>().ToTable("Objects");
        model.Entity<TechnicalObject>().Property(x => x.ServerVersion).IsConcurrencyToken().HasDefaultValue(1L);
        model.Entity<OperationReceipt>().ToTable("OperationReceipts").HasKey(x => x.Key);
        model.Entity<FieldRoute>().ToTable("Routes");
        model.Entity<Visit>().ToTable("Visits");
        model.Entity<LocationPoint>().ToTable("LocationPoints");
        model.Entity<TechnicalObject>().Property(x => x.Status).HasConversion<string>();
        model.Entity<TechnicalObject>().Property(x => x.Priority).HasConversion<string>();
        model.Entity<FieldRoute>().Property(x => x.Status).HasConversion<string>();
        model.Entity<Visit>().Property(x => x.Status).HasConversion<string>();
        model.Entity<Visit>().Property(x => x.ServerVersion).IsConcurrencyToken();
        model.Entity<Visit>().HasOne<TechnicalObject>().WithMany().HasForeignKey(x => x.ObjectId).OnDelete(DeleteBehavior.Restrict);
        model.Entity<Visit>().HasOne<FieldRoute>().WithMany().HasForeignKey(x => x.RouteId).OnDelete(DeleteBehavior.Restrict);
        model.Entity<LocationPoint>().HasOne<FieldRoute>().WithMany().HasForeignKey(x => x.RouteId).OnDelete(DeleteBehavior.Restrict);
        model.Entity<FieldRoute>().HasIndex(x => x.Date);
        model.Entity<LocationPoint>().HasIndex(x => new { x.RouteId, x.TimestampTicks });
        model.Entity<TechnicalObject>().HasIndex(x => x.UpdatedAtTicks);
        model.Entity<FieldRoute>().HasIndex(x => x.UpdatedAtTicks);
        model.Entity<Visit>().HasIndex(x => x.UpdatedAtTicks);
        model.Entity<LocationPoint>().HasIndex(x => x.UpdatedAtTicks);
    }
}
