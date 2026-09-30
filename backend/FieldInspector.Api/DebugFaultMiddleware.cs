namespace FieldInspector.Api;

public sealed class DebugFaultMiddleware(RequestDelegate next, IWebHostEnvironment environment, IConfiguration configuration)
{
    public async Task InvokeAsync(HttpContext context)
    {
        if (!environment.IsDevelopment() || !configuration.GetValue<bool>("DebugFaults:Enabled"))
        {
            await next(context);
            return;
        }
        var mode = context.Request.Headers["X-Debug-Fault"].FirstOrDefault()
            ?? context.Request.Query["debug"].FirstOrDefault();
        if (string.IsNullOrEmpty(mode)) { await next(context); return; }
        context.Response.Headers["X-Debug-Fault"] = mode;
        if (mode is "500" or "409")
        {
            await Results.Problem(statusCode: int.Parse(mode), title: $"Simulated HTTP {mode}",
                detail: "Debug fault before endpoint execution; nothing was persisted.",
                extensions: new Dictionary<string, object?> { ["simulated"] = true }).ExecuteAsync(context);
            return;
        }
        if (mode is not ("delay" or "timeout"))
        {
            await Results.Problem(statusCode: 400, title: "Unknown debug mode").ExecuteAsync(context);
            return;
        }
        try
        {
            // Превышение времени ожидания — действительное отсутствие ответа, а не HTTP 408.
            // Отмена клиента освобождает ожидание и не запускает запись данных.
            if (mode == "timeout")
            {
                await Task.Delay(Timeout.Infinite, context.RequestAborted);
                return;
            }
            var rawDelay = context.Request.Headers["X-Debug-Delay-Ms"].FirstOrDefault()
                ?? context.Request.Query["delayMs"].FirstOrDefault() ?? "2000";
            if (!int.TryParse(rawDelay, out var milliseconds) || milliseconds is < 0 or > 30000)
            {
                await Results.Problem(statusCode: 400, title: "delayMs must be between 0 and 30000").ExecuteAsync(context);
                return;
            }
            await Task.Delay(milliseconds, context.RequestAborted);
            await next(context);
        }
        catch (OperationCanceledException) when (context.RequestAborted.IsCancellationRequested)
        {
            // Ожидаемое завершение искусственного ожидания или задержки, не ошибка сервера.
        }
    }
}
