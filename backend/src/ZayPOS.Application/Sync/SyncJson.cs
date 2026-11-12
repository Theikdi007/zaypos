using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace ZayPOS.Application.Sync;

/// <summary>Strict parsing of a unit's rows: integers must be JSON integers, enums must be names.</summary>
public static class SyncJson
{
    public static readonly JsonSerializerOptions Rows = new(JsonSerializerDefaults.Web)
    {
        NumberHandling = JsonNumberHandling.Strict,
        Converters =
        {
            new JsonStringEnumConverter(JsonNamingPolicy.CamelCase, allowIntegerValues: false),
            new UtcMillisecondsConverter(),
            new LenientDateOnlyConverter(),
        },
    };

    public static UnitRows ParseRows(JsonElement rows)
    {
        if (rows.ValueKind != JsonValueKind.Object)
            throw new SyncRejectException("rows must be a JSON object.");
        try
        {
            return rows.Deserialize<UnitRows>(Rows) ?? new UnitRows();
        }
        catch (JsonException e)
        {
            throw new SyncRejectException($"Malformed rows{(e.Path is null ? "" : " at " + e.Path)}: {Short(e.Message)}");
        }
    }

    /// <summary>datetime2(3) keeps milliseconds; truncate so LWW comparisons round-trip exactly.</summary>
    public static DateTime ToUtcMs(DateTime t)
    {
        var utc = t.Kind switch
        {
            DateTimeKind.Utc => t,
            DateTimeKind.Local => t.ToUniversalTime(),
            _ => DateTime.SpecifyKind(t, DateTimeKind.Utc), // no offset given: the app always sends UTC
        };
        return new DateTime(utc.Ticks - utc.Ticks % TimeSpan.TicksPerMillisecond, DateTimeKind.Utc);
    }

    private static string Short(string s) => s.Length <= 200 ? s : s[..200];

    private sealed class UtcMillisecondsConverter : JsonConverter<DateTime>
    {
        public override DateTime Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) =>
            ToUtcMs(reader.GetDateTime());

        public override void Write(Utf8JsonWriter writer, DateTime value, JsonSerializerOptions options) =>
            writer.WriteStringValue(ToUtcMs(value));
    }

    /// <summary>Accepts "2026-12-31" and Dart's DateTime.toIso8601String() ("2026-12-31T00:00:00.000Z").</summary>
    private sealed class LenientDateOnlyConverter : JsonConverter<DateOnly>
    {
        public override DateOnly Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        {
            var s = reader.GetString() ?? throw new JsonException("date expected");
            if (DateOnly.TryParseExact(s, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var d)) return d;
            if (DateTime.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var dt))
                return DateOnly.FromDateTime(dt.Kind == DateTimeKind.Local ? dt.ToUniversalTime() : dt);
            throw new JsonException($"'{s}' is not a date");
        }

        public override void Write(Utf8JsonWriter writer, DateOnly value, JsonSerializerOptions options) =>
            writer.WriteStringValue(value.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture));
    }
}

/// <summary>README §3.3 last-writer-wins, including the soft-delete rule.</summary>
public static class LastWriterWins
{
    public enum LwwAction
    {
        /// <summary>New row.</summary>
        Insert,
        /// <summary>Take every incoming field (incl. DeletedAt).</summary>
        Update,
        /// <summary>Incoming is older but deletes: set DeletedAt only ("DeletedAt set wins").</summary>
        DeleteOnly,
        Ignore,
    }

    /// <param name="existingUpdatedAt">null = the row does not exist yet.</param>
    public static LwwAction Decide(DateTime? existingUpdatedAt, DateTime? existingDeletedAt,
        DateTime incomingUpdatedAt, DateTime? incomingDeletedAt, bool restore)
    {
        if (existingUpdatedAt is not { } current) return LwwAction.Insert;
        var newer = incomingUpdatedAt > current;

        var existingDeleted = existingDeletedAt is not null;
        var incomingDeleted = incomingDeletedAt is not null;

        if (existingDeleted && !incomingDeleted)
            return restore && newer ? LwwAction.Update : LwwAction.Ignore; // a deleted item stays deleted unless restored
        if (incomingDeleted && !existingDeleted)
            return newer ? LwwAction.Update : LwwAction.DeleteOnly;        // delete wins over later edits
        return newer ? LwwAction.Update : LwwAction.Ignore;
    }
}
