using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using FluentAssertions;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using ZayPOS.Application.Abstractions;
using ZayPOS.Application.Auth;
using ZayPOS.Application.Sync;
using ZayPOS.Domain.Common;
using ZayPOS.Infrastructure.Persistence;
using ZayPOS.Infrastructure.Sms;

namespace ZayPOS.Api.Tests;

/// <summary>
/// Phase 4 deploy: the migrate step, the API's own SQL login, the pending-migrations gate, /health,
/// the production guards (SMS, not sa, HTTPS only, no Swagger) and the Caddy → API forwarding.
/// </summary>
[Collection(SqlServerCollection.Name)]
public class DeploymentTests(SqlServerFixture sql)
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    private const string Caddy = "172.30.0.10"; // the proxy's fixed address in docker-compose.prod.yml
    private static int _seq = Random.Shared.Next(1_000_000, 9_000_000);

    /// <summary>sa on the test container, pointed at <paramref name="database"/>.</summary>
    private string Admin(string database) =>
        new SqlConnectionStringBuilder(sql.ConnectionString) { InitialCatalog = database }.ConnectionString;

    private string AppLogin(string database, string login, string password) =>
        new SqlConnectionStringBuilder(sql.ConnectionString)
            { InitialCatalog = database, UserID = login, Password = password }.ConnectionString;

    private static string NewDb() => "zp_" + Guid.NewGuid().ToString("N")[..12];
    private static string NewLogin() => "zaypos_app_" + Guid.NewGuid().ToString("N")[..8];
    private static string NewPassword() => "Aa1" + Convert.ToBase64String(Guid.NewGuid().ToByteArray()).Replace("/", "").Replace("+", "").TrimEnd('=');

    /// <summary>Migrated database + app login, as the deploy's migrate step leaves it.</summary>
    private async Task<(string Db, string AppCs)> MigratedDatabase()
    {
        var db = NewDb();
        var app = AppLogin(db, NewLogin(), NewPassword());
        await DatabaseMigrator.MigrateAsync(Admin(db), app, NullLogger.Instance);
        return (db, app);
    }

    private static Dictionary<string, string?> ProductionSettings(string connectionString) => new()
    {
        ["ConnectionStrings:ZayPOS"] = connectionString,
        ["Sms:Provider"] = "SmsPoh",
        ["Sms:SmsPoh:Token"] = "test-token",
        ["ForwardedHeaders:TrustedNetworksOverride"] = Caddy + "/32",
        ["Auth:Google:ClientIds"] = FakeGoogleVerifier.ClientId,
    };

    // ------------------------------------------------------------ migrate step

    [Fact]
    public async Task Migrate_creates_the_database_applies_every_migration_and_is_repeatable()
    {
        var (db, app) = await MigratedDatabase();

        await using var ctx = new ZayPosDbContext(
            new DbContextOptionsBuilder<ZayPosDbContext>().UseSqlServer(app).Options, new NoTenant());
        (await ctx.Database.GetPendingMigrationsAsync()).Should().BeEmpty();
        (await ctx.Database.GetAppliedMigrationsAsync()).Should().Equal(ctx.Database.GetMigrations());

        // Second run (every deploy runs it): nothing to do, no error.
        await DatabaseMigrator.MigrateAsync(Admin(db), app, NullLogger.Instance);
    }

    [Fact]
    public async Task App_login_can_read_and_write_but_not_change_the_schema()
    {
        var (_, app) = await MigratedDatabase();
        await using var conn = new SqlConnection(app);
        await conn.OpenAsync();

        (await Scalar(conn, "SELECT IS_SRVROLEMEMBER('sysadmin')")).Should().Be(0);
        (await Scalar(conn, "SELECT IS_ROLEMEMBER('db_owner')")).Should().Be(0);
        (await Scalar(conn, "SELECT IS_ROLEMEMBER('db_datareader')")).Should().Be(1);
        (await Scalar(conn, "SELECT IS_ROLEMEMBER('db_datawriter')")).Should().Be(1);

        var ddl = () => new SqlCommand("CREATE TABLE dbo.Evil (Id int)", conn).ExecuteNonQueryAsync();
        (await ddl.Should().ThrowAsync<SqlException>()).Which.Number.Should().Be(262); // CREATE TABLE permission denied
        var drop = () => new SqlCommand("DROP TABLE dbo.Sales", conn).ExecuteNonQueryAsync();
        await drop.Should().ThrowAsync<SqlException>();
    }

    [Fact]
    public async Task Migrate_updates_the_app_password_and_removes_rights_added_by_hand()
    {
        var db = NewDb();
        var login = NewLogin();
        var oldApp = AppLogin(db, login, NewPassword());
        await DatabaseMigrator.MigrateAsync(Admin(db), oldApp, NullLogger.Instance);
        await using (var admin = new SqlConnection(Admin(db)))
        {
            await admin.OpenAsync();
            await new SqlCommand($"ALTER ROLE db_owner ADD MEMBER [{login}]", admin).ExecuteNonQueryAsync();
        }

        var newApp = AppLogin(db, login, NewPassword());
        await DatabaseMigrator.MigrateAsync(Admin(db), newApp, NullLogger.Instance);

        await using (var conn = new SqlConnection(newApp))
        {
            await conn.OpenAsync();
            (await Scalar(conn, "SELECT IS_ROLEMEMBER('db_owner')")).Should().Be(0);
        }
        SqlConnection.ClearAllPools();
        var old = async () => { await using var c = new SqlConnection(oldApp); await c.OpenAsync(); };
        (await old.Should().ThrowAsync<SqlException>()).Which.Number.Should().Be(18456);
    }

    [Theory]
    [InlineData("sa")]
    [InlineData("app; DROP LOGIN x")]
    [InlineData("1abc")]
    public async Task Migrate_refuses_sa_or_odd_names_as_the_app_login(string login)
    {
        var db = NewDb();
        var run = () => DatabaseMigrator.MigrateAsync(Admin(db), AppLogin(db, login, NewPassword()), NullLogger.Instance);
        await run.Should().ThrowAsync<InvalidOperationException>();
    }

    [Fact]
    public async Task The_whole_api_works_on_the_app_login()
    {
        var (_, app) = await MigratedDatabase();
        await using var api = new ApiFactory(app);
        var http = api.CreateClient();
        var phone = "+9597" + Interlocked.Increment(ref _seq).ToString("D8");

        (await http.PostAsJsonAsync("/api/v1/auth/otp", new OtpRequest(phone, OtpPurpose.Register), Json)).EnsureSuccessStatusCode();
        var reg = await http.PostAsJsonAsync("/api/v1/auth/register", new RegisterRequest(phone, api.Sms.LastCode(phone), "Login test",
            "grocery", null, "123456", new DeviceInfo(Guid.CreateVersion7(), "A")), Json);
        reg.StatusCode.Should().Be(HttpStatusCode.OK, await reg.Content.ReadAsStringAsync());
        var auth = (await reg.Content.ReadFromJsonAsync<AuthResponse>(Json))!;
        http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", auth.AccessToken);

        var now = SyncJson.ToUtcMs(DateTime.UtcNow);
        var push = await http.PostAsJsonAsync("/api/v1/sync/push", new
        {
            deviceId = auth.Device.Id,
            units = new[]
            {
                new
                {
                    unitId = Guid.CreateVersion7(), kind = "upsertCustomer", clientTime = now,
                    rows = new { customers = new[] { new { id = Guid.CreateVersion7(), name = "ဒေါ်ခင်မာ", phone = "09777123456",
                        creditLimit = (long?)null, createdAt = now, updatedAt = now } } },
                },
            },
        }, Json);
        push.StatusCode.Should().Be(HttpStatusCode.OK, await push.Content.ReadAsStringAsync());
        (await push.Content.ReadAsStringAsync()).Should().Contain("\"applied\"");

        (await http.GetAsync("/api/v1/sync/pull?cursor=0")).StatusCode.Should().Be(HttpStatusCode.OK);
        (await http.GetAsync("/api/v1/me")).StatusCode.Should().Be(HttpStatusCode.OK);
        (await http.PostAsJsonAsync("/api/v1/auth/refresh", new RefreshRequest(auth.RefreshToken), Json))
            .StatusCode.Should().Be(HttpStatusCode.OK);
    }

    // ------------------------------------------------------------ startup gate

    [Fact]
    public async Task Api_refuses_to_start_when_migrations_are_pending()
    {
        var db = NewDb();
        await using (var admin = new SqlConnection(Admin("master")))
        {
            await admin.OpenAsync();
            await new SqlCommand($"CREATE DATABASE [{db}]", admin).ExecuteNonQueryAsync();
        }
        await using var api = new ApiFactory(Admin(db));

        var start = () => api.CreateClient();
        var error = start.Should().Throw<PendingMigrationsException>().Which;
        error.Pending.Should().NotBeEmpty().And.Contain(m => m.EndsWith("_InitialSchema"));
        error.Message.Should().Contain("pending EF migration").And.Contain("run --rm migrate");
    }

    // ------------------------------------------------------------ /health

    [Fact]
    public async Task Health_checks_the_database_and_shows_nothing_else()
    {
        var res = await sql.Api.CreateClient().GetAsync("/health");

        res.StatusCode.Should().Be(HttpStatusCode.OK);
        var body = await res.Content.ReadAsStringAsync();
        JsonDocument.Parse(body).RootElement.GetRawText().Should().Be("""{"status":"healthy","checks":{"database":"healthy"}}""");
        res.Headers.CacheControl!.NoStore.Should().BeTrue();
    }

    [Fact]
    public async Task Health_is_503_without_details_when_the_database_is_unreachable()
    {
        var bad = new SqlConnectionStringBuilder(sql.ConnectionString) { Password = "wrong-password-123", ConnectTimeout = 2 }.ConnectionString;
        await using var api = new ApiFactory(bad, settings: new Dictionary<string, string?> { ["Database:CheckMigrationsOnStartup"] = "false" });

        var res = await api.CreateClient().GetAsync("/health");

        res.StatusCode.Should().Be(HttpStatusCode.ServiceUnavailable);
        var body = await res.Content.ReadAsStringAsync();
        body.Should().Be("""{"status":"unhealthy","checks":{"database":"unhealthy"}}""");
        body.Should().NotContainAny("Login failed", "sa", "Password", "Server=");
    }

    // ------------------------------------------------------------ production guards

    [Theory]
    [InlineData("SmsPho", "test-token", false, "Sms:Provider must be 'SmsPoh' or 'Console'")] // a typo never falls back to logging codes
    [InlineData("SmsPoh", "", false, "SMSPoh credential missing")]
    [InlineData("SmsPoh", "test-token", true, "not sa")]
    public async Task Production_refuses_unsafe_configuration(string provider, string token, bool asSa, string expected)
    {
        var (_, app) = await MigratedDatabase();
        var settings = ProductionSettings(asSa ? sql.ConnectionString : app);
        settings["Sms:Provider"] = provider;
        settings["Sms:SmsPoh:Token"] = token;
        await using var api = new ApiFactory(app, settings: settings, environment: "Production");

        var start = () => api.CreateClient();
        start.Should().Throw<InvalidOperationException>().WithMessage($"*{expected}*");
    }

    [Theory]
    [InlineData("")]
    [InlineData(" , ")]
    public async Task Production_refuses_to_start_without_google_client_ids(string clientIds)
    {
        var (_, app) = await MigratedDatabase();
        var settings = ProductionSettings(app);
        settings["Auth:Google:ClientIds"] = clientIds;
        await using var api = new ApiFactory(app, settings: settings, environment: "Production");

        var start = () => api.CreateClient();
        start.Should().Throw<InvalidOperationException>().WithMessage("*Auth:Google:ClientIds*");
    }

    [Theory]
    [InlineData("SmsPoh")]
    [InlineData("SmsPho")]
    public async Task Production_with_OTP_off_needs_no_SMS_settings(string provider)
    {
        var (_, app) = await MigratedDatabase();
        var settings = ProductionSettings(app);
        settings["Auth:OtpEnabled"] = "false";
        settings["Sms:Provider"] = provider;
        settings["Sms:SmsPoh:Token"] = "";
        await using var api = new ApiFactory(app, remoteIp: IPAddress.Loopback, settings: settings, environment: "Production");

        (await api.CreateClient().GetAsync("/health")).StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Theory]
    [InlineData("Console")]
    [InlineData("console")]
    [InlineData("Log")]
    public async Task Production_starts_with_console_sms_and_no_smspoh_token(string provider)
    {
        var (_, app) = await MigratedDatabase();
        var settings = ProductionSettings(app);
        settings["Sms:Provider"] = provider;
        settings["Sms:SmsPoh:Token"] = "";
        await using var api = new ApiFactory(app, remoteIp: IPAddress.Loopback, settings: settings, environment: "Production");

        (await api.CreateClient().GetAsync("/health")).StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Theory]
    [InlineData("Console", "LoggingSmsSender")]
    [InlineData("SmsPoh", "SmsPohSmsSender")]
    public void Sms_provider_picks_the_sender(string provider, string expected)
    {
        var config = new Microsoft.Extensions.Configuration.ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ConnectionStrings:ZayPOS"] = sql.ConnectionString,
                ["Jwt:SigningKey"] = ApiFactory.SigningKey,
                ["Sms:Provider"] = provider,
                ["Sms:SmsPoh:Token"] = "t",
            }).Build();
        var services = new Microsoft.Extensions.DependencyInjection.ServiceCollection().AddLogging();
        ZayPOS.Infrastructure.DependencyInjection.AddInfrastructure(services, config);
        services.AddSingleton<ICurrentTenant>(new NoTenant());

        using var sp = services.BuildServiceProvider();
        sp.GetRequiredService<ISmsSender>().GetType().Name.Should().Be(expected);
    }

    [Fact]
    public async Task Production_rejects_plain_http_trusts_only_the_proxy_and_hides_swagger()
    {
        var (_, app) = await MigratedDatabase();

        // Request straight to the API over HTTP (not through Caddy): refused.
        await using (var direct = new ApiFactory(app, remoteIp: IPAddress.Parse("203.0.113.9"),
                         settings: ProductionSettings(app), environment: "Production"))
        {
            var res = await direct.CreateClient().GetAsync("/api/v1/health");
            res.StatusCode.Should().Be(HttpStatusCode.BadRequest);
            (await res.Content.ReadAsStringAsync()).Should().Contain("https_required");

            // A spoofed X-Forwarded-Proto from a non-proxy address is ignored.
            var spoof = new HttpRequestMessage(HttpMethod.Get, "/api/v1/health");
            spoof.Headers.Add("X-Forwarded-Proto", "https");
            (await direct.CreateClient().SendAsync(spoof)).StatusCode.Should().Be(HttpStatusCode.BadRequest);
        }

        // Through Caddy (trusted; it REPLACES X-Forwarded-For / -Proto with the real peer and https): served;
        // Swagger is off.
        await using (var viaCaddy = new ApiFactory(app, authPerIp: 1, remoteIp: IPAddress.Parse(Caddy),
                         settings: ProductionSettings(app), environment: "Production"))
        {
            var http = viaCaddy.CreateClient();
            HttpRequestMessage Req(HttpMethod method, string path, string clientIp, string? spoofedCfIp = null)
            {
                var m = new HttpRequestMessage(method, path);
                m.Headers.Add("X-Forwarded-Proto", "https");
                m.Headers.Add("X-Forwarded-For", clientIp);
                // Caddy strips it; even if it got through, the API must not read it.
                if (spoofedCfIp is not null) m.Headers.Add("CF-Connecting-IP", spoofedCfIp);
                m.Headers.Host = "api.zaypos.app"; // HSTS is never sent for "localhost"
                if (method == HttpMethod.Post) m.Content = JsonContent.Create(new RefreshRequest("garbage"), options: Json);
                return m;
            }

            var ok = await http.SendAsync(Req(HttpMethod.Get, "/health", "203.0.113.1"));
            ok.StatusCode.Should().Be(HttpStatusCode.OK);
            ok.Headers.Contains("Strict-Transport-Security").Should().BeTrue();
            (await http.SendAsync(Req(HttpMethod.Get, "/swagger/v1/swagger.json", "203.0.113.1"))).StatusCode.Should().Be(HttpStatusCode.NotFound);
            (await http.SendAsync(Req(HttpMethod.Get, "/swagger/index.html", "203.0.113.1"))).StatusCode.Should().Be(HttpStatusCode.NotFound);

            // Rate limits key on the real client IP that Caddy passes on (X-Forwarded-For); CF-Connecting-IP changes
            // nothing.
            (await http.SendAsync(Req(HttpMethod.Post, "/api/v1/auth/refresh", "203.0.113.1"))).StatusCode.Should().Be(HttpStatusCode.Unauthorized);
            (await http.SendAsync(Req(HttpMethod.Post, "/api/v1/auth/refresh", "203.0.113.2"))).StatusCode.Should().Be(HttpStatusCode.Unauthorized);
            (await http.SendAsync(Req(HttpMethod.Post, "/api/v1/auth/refresh", "203.0.113.1", spoofedCfIp: "198.51.100.99")))
                .StatusCode.Should().Be(HttpStatusCode.TooManyRequests, "the bucket is X-Forwarded-For's, whatever CF-Connecting-IP says");
        }

        // Container health check: plain HTTP on loopback is allowed.
        await using (var loopback = new ApiFactory(app, remoteIp: IPAddress.Loopback,
                         settings: ProductionSettings(app), environment: "Production"))
        {
            (await loopback.CreateClient().GetAsync("/health")).StatusCode.Should().Be(HttpStatusCode.OK);
        }
    }

    [Fact]
    public async Task Production_refuses_to_start_without_caddy_as_the_trusted_proxy()
    {
        // Without it every phone would share Caddy's rate-limit bucket (and Https:Require would refuse all).
        var (_, app) = await MigratedDatabase();
        var settings = ProductionSettings(app);
        settings.Remove("ForwardedHeaders:TrustedNetworksOverride");
        await using var api = new ApiFactory(app, settings: settings, environment: "Production");
        var start = () => api.CreateClient();
        start.Should().Throw<InvalidOperationException>().WithMessage("*ForwardedHeaders*TrustedNetworksOverride*");
    }

    [Fact]
    public async Task With_the_override_cloudflare_addresses_are_not_trusted()
    {
        var settings = new Dictionary<string, string?> { ["ForwardedHeaders:TrustedNetworksOverride"] = Caddy + "/32" };
        await using var api = new ApiFactory(sql.ConnectionString, authPerIp: 1, remoteIp: IPAddress.Parse("173.245.48.10"), settings: settings);
        var http = api.CreateClient();
        HttpRequestMessage Req(string ip)
        {
            var m = new HttpRequestMessage(HttpMethod.Post, "/api/v1/auth/refresh") { Content = JsonContent.Create(new RefreshRequest("garbage"), options: Json) };
            m.Headers.Add("X-Forwarded-For", ip);
            m.Headers.Add("CF-Connecting-IP", ip);
            return m;
        }

        (await http.SendAsync(Req("203.0.113.1"))).StatusCode.Should().Be(HttpStatusCode.Unauthorized);
        (await http.SendAsync(Req("203.0.113.2"))).StatusCode.Should().Be(HttpStatusCode.TooManyRequests);
    }

    // ------------------------------------------------------------ SMSPoh

    [Fact]
    public async Task SmsPoh_posts_bearer_json_and_never_logs_the_code()
    {
        var handler = new RecordingHandler(HttpStatusCode.OK);
        var log = new ListLogger();
        var sender = new SmsPohSmsSender(Options.Create(new SmsOptions
        {
            Provider = "SmsPoh",
            SmsPoh = new SmsPohOptions { Token = "tok123", Sender = "ZayPOS" },
        }), new HttpClient(handler), log);

        await sender.SendAsync("+959790011002", "ZayPOS code: 482913", CancellationToken.None);

        handler.Request!.Method.Should().Be(HttpMethod.Post);
        handler.Request.RequestUri.Should().Be(new Uri("https://v3.smspoh.com/api/rest/send"));
        handler.Request.Headers.Authorization.Should().Be(new AuthenticationHeaderValue("Bearer", "tok123"));
        var body = JsonDocument.Parse(handler.Body!).RootElement;
        body.GetProperty("to").GetString().Should().Be("+959790011002");
        body.GetProperty("message").GetString().Should().Be("ZayPOS code: 482913");
        body.GetProperty("from").GetString().Should().Be("ZayPOS");
        body.GetProperty("test").ValueKind.Should().Be(JsonValueKind.False); // a JSON boolean (v3 spec), not 0
        log.Lines.Should().NotContain(l => l.Contains("482913") || l.Contains("+959790011002"));
    }

    [Fact]
    public async Task SmsPoh_key_and_secret_become_the_v3_bearer_value_and_never_reach_the_log()
    {
        // SMSPoh's own v3 example: "SMSPohV3APIKey:SMSPohV3APISecret" → Bearer U01TUG9oVjNBUElLZXk6U01TUG9oVjNBUElTZWNyZXQ=
        var o = new SmsPohOptions { ApiKey = "SMSPohV3APIKey", ApiSecret = "SMSPohV3APISecret" };
        o.HasCredentials.Should().BeTrue();
        o.BearerToken().Should().Be("U01TUG9oVjNBUElLZXk6U01TUG9oVjNBUElTZWNyZXQ=");
        new SmsPohOptions { ApiKey = "k" }.HasCredentials.Should().BeFalse();
        new SmsPohOptions { Token = "t", ApiKey = "ignored", ApiSecret = "ignored" }.BearerToken().Should().Be("t");

        var handler = new RecordingHandler(HttpStatusCode.Unauthorized,
            """{"message":"Invalid credential SMSPohV3APIKey / SMSPohV3APISecret / U01TUG9oVjNBUElLZXk6U01TUG9oVjNBUElTZWNyZXQ="}""");
        var log = new ListLogger();
        var sender = new SmsPohSmsSender(Options.Create(new SmsOptions { SmsPoh = o }), new HttpClient(handler), log);
        await ((Func<Task>)(() => sender.SendAsync("+959790011002", "ZayPOS code: 482913", CancellationToken.None)))
            .Should().ThrowAsync<ApiException>();

        handler.Request!.Headers.Authorization.Should().Be(new AuthenticationHeaderValue("Bearer", "U01TUG9oVjNBUElLZXk6U01TUG9oVjNBUElTZWNyZXQ="));
        log.Lines.Should().ContainSingle().Which.Should().Contain("HTTP 401").And.Contain("Invalid credential")
            .And.NotContainAny("SMSPohV3APIKey", "SMSPohV3APISecret", "U01TUG9oVjNBUElLZXk6U01TUG9oVjNBUElTZWNyZXQ=");
    }

    [Fact]
    public async Task Production_starts_with_smspoh_key_and_secret_instead_of_a_token()
    {
        var (_, app) = await MigratedDatabase();
        var settings = ProductionSettings(app);
        settings["Sms:SmsPoh:Token"] = "";
        settings["Sms:SmsPoh:ApiKey"] = "key";
        settings["Sms:SmsPoh:ApiSecret"] = "secret";
        await using var api = new ApiFactory(app, remoteIp: IPAddress.Loopback, settings: settings, environment: "Production");

        (await api.CreateClient().GetAsync("/health")).StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact]
    public async Task SmsPoh_test_mode_sends_json_true_and_says_so_in_the_log()
    {
        var handler = new RecordingHandler(HttpStatusCode.OK, """{"status":true,"data":{"test":true,"to":"+959790011002"}}""");
        var log = new ListLogger();
        var sender = new SmsPohSmsSender(Options.Create(new SmsOptions
        {
            Provider = "SmsPoh", SmsPoh = new SmsPohOptions { Token = "tok123", Test = true },
        }), new HttpClient(handler), log);

        await sender.SendAsync("+959790011002", "ZayPOS code: 482913", CancellationToken.None);

        JsonDocument.Parse(handler.Body!).RootElement.GetProperty("test").ValueKind.Should().Be(JsonValueKind.True);
        JsonDocument.Parse(handler.Body!).RootElement.TryGetProperty("from", out _).Should().BeFalse(); // default sender
        log.Lines.Should().ContainSingle(l => l.Contains("TEST mode") && l.Contains("HTTP 200"));
        log.Lines.Should().NotContain(l => l.Contains("482913") || l.Contains("790011002") || l.Contains("tok123"));
    }

    [Fact]
    public async Task SmsPoh_refusal_logs_status_and_reply_but_no_token_phone_or_code()
    {
        var handler = new RecordingHandler(HttpStatusCode.Forbidden,
            """{"status":false,"message":"IP address 45.32.114.207 is not whitelisted","token":"tok123","to":"+959790011002","text":"ZayPOS code: 482913"}""");
        var log = new ListLogger();
        var sender = new SmsPohSmsSender(Options.Create(new SmsOptions { SmsPoh = new SmsPohOptions { Token = "tok123" } }),
            new HttpClient(handler), log);

        var send = () => sender.SendAsync("+959790011002", "ZayPOS code: 482913", CancellationToken.None);

        await send.Should().ThrowAsync<ApiException>();
        var line = log.Lines.Should().ContainSingle().Which;
        line.Should().Contain("HTTP 403").And.Contain("is not whitelisted").And.Contain("[token]");
        line.Should().NotContainAny("tok123", "482913", "790011002");
    }

    [Theory]
    [InlineData(HttpStatusCode.Unauthorized)]
    [InlineData(HttpStatusCode.InternalServerError)]
    public async Task SmsPoh_failure_is_a_503_sms_unavailable(HttpStatusCode status)
    {
        var sender = new SmsPohSmsSender(Options.Create(new SmsOptions { SmsPoh = new SmsPohOptions { Token = "t" } }),
            new HttpClient(new RecordingHandler(status)), new ListLogger());

        var send = () => sender.SendAsync("+959790011002", "ZayPOS code: 1", CancellationToken.None);

        var e = (await send.Should().ThrowAsync<ApiException>()).Which;
        (e.Status, e.Code).Should().Be((503, "sms_unavailable"));
    }

    // ------------------------------------------------------------ helpers

    private static async Task<int> Scalar(SqlConnection conn, string sqlText) =>
        Convert.ToInt32(await new SqlCommand(sqlText, conn).ExecuteScalarAsync());

    private sealed class NoTenant : ICurrentTenant
    {
        public Guid? TenantId => null;
    }

    private sealed class RecordingHandler(HttpStatusCode status, string reply = "{}") : HttpMessageHandler
    {
        public HttpRequestMessage? Request { get; private set; }
        public string? Body { get; private set; }

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            Request = request;
            Body = request.Content is null ? null : await request.Content.ReadAsStringAsync(ct);
            return new HttpResponseMessage(status) { Content = new StringContent(reply) };
        }
    }

    private sealed class ListLogger : Microsoft.Extensions.Logging.ILogger<SmsPohSmsSender>
    {
        public List<string> Lines { get; } = [];
        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;
        public bool IsEnabled(Microsoft.Extensions.Logging.LogLevel level) => true;
        public void Log<TState>(Microsoft.Extensions.Logging.LogLevel level, Microsoft.Extensions.Logging.EventId id, TState state,
            Exception? exception, Func<TState, Exception?, string> formatter) => Lines.Add(formatter(state, exception));
    }
}
