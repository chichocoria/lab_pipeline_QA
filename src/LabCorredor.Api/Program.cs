using Azure.Identity;

var builder = WebApplication.CreateBuilder(args);

// Cargar Key Vault solo si se configuró su nombre.
// En local normalmente no se usa Key Vault; en Azure App Service sí.
var keyVaultName = builder.Configuration["KeyVault:Name"];
if (!string.IsNullOrWhiteSpace(keyVaultName))
{
    builder.Configuration.AddAzureKeyVault(
        new Uri($"https://{keyVaultName}.vault.azure.net/"),
        new DefaultAzureCredential());
}

var app = builder.Build();

app.MapGet("/", () => new
{
    Message = "Lab Corredor API funcionando",
    Environment = Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT") ?? "(no seteado)",
    Version = "1.0.0"
});

app.MapGet("/health", () => Results.Ok(new { Status = "Healthy", Timestamp = DateTime.UtcNow }));

// Endpoint de diagnóstico para verificar que los secretos llegan correctamente.
// Los valores se enmascaran para poder mostrarlos sin filtrarlos en logs o pantalla.
app.MapGet("/config", (IConfiguration config) => new
{
    DatabaseConnectionString = Mask(config["DatabaseSettings__ConnectionString"]),
    MailserverPassword = Mask(config["Mailserver__Password"]),
    SunatApiKey = Mask(config["ExternalServices__Sunat__ApiKey"]),
    KeyVaultName = config["KeyVault:Name"]
});

app.Run();

static string Mask(string? value)
{
    if (string.IsNullOrEmpty(value))
        return "(vacío)";

    if (value.Length <= 6)
        return "***";

    return $"{value[..3]}...{value[^3..]}";
}
