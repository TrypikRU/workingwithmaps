using System.Text.Json;
using System.Text.Json.Serialization;
using FieldInspector.Api;
using FieldInspector.Api.Data;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Swashbuckle.AspNetCore.SwaggerGen;

var builder = WebApplication.CreateBuilder(args);
builder.Services.ConfigureHttpJsonOptions(options =>
    options.SerializerOptions.Converters.Add(new JsonStringEnumConverter(JsonNamingPolicy.CamelCase, allowIntegerValues: false)));
builder.Services.AddProblemDetails();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options => options.SwaggerDoc("v1", new() { Title = "Полевой инспектор — тестовый API", Version = "v1" }));
// Swagger использует те же строковые перечисления, что JSON запросов и ответов Minimal API.
builder.Services.AddSingleton<ISerializerDataContractResolver>(services =>
    new JsonSerializerDataContractResolver(services.GetRequiredService<IOptions<Microsoft.AspNetCore.Http.Json.JsonOptions>>().Value.SerializerOptions));
builder.Services.AddSingleton<SyncGate>();
var databasePath = Path.GetFullPath(builder.Configuration["Storage:Path"] ?? "Data/field-inspector.sqlite", builder.Environment.ContentRootPath);
Directory.CreateDirectory(Path.GetDirectoryName(databasePath)!);
var connection = new SqliteConnectionStringBuilder { DataSource = databasePath, ForeignKeys = true }.ToString();
builder.Services.AddDbContext<InspectorDbContext>(options => options.UseSqlite(connection));

var app = builder.Build();
// Ошибки привязки некорректного JSON или параметров запроса остаются клиентскими и в Development.
app.UseExceptionHandler(new ExceptionHandlerOptions
{
    StatusCodeSelector = error => error is BadHttpRequestException badRequest
        ? badRequest.StatusCode : StatusCodes.Status500InternalServerError
});
app.UseMiddleware<DebugFaultMiddleware>();
app.UseSwagger();
app.UseSwaggerUI();
app.MapGet("/", () => Results.Redirect("/swagger"));
app.MapInspectorApi();
await using (var scope = app.Services.CreateAsyncScope())
    await SeedData.Initialize(scope.ServiceProvider.GetRequiredService<InspectorDbContext>(), app.Services.GetRequiredService<SyncGate>());
await app.RunAsync();
