using System.Net;
using System.Text.Json;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using ZayPOS.Api.Tests;
using ZayPOS.Application.Sync;
using ZayPOS.Domain.Common;
using ZayPOS.Domain.Sync;
using static ZayPOS.QA.Tests.QaApi;

namespace ZayPOS.QA.Tests;

/// <summary>
/// QA round 11 — 1420ee8, server half. Owner: "the server closes it automatically once no other product in the shop has
/// that barcode. Mark it resolved with a reason ('ပြင်ပြီးသွားပါပြီ'), keep it in history, and show the resolved state on
/// every phone." Implementation: after any unit with product rows, open duplicateBarcode issues whose barcode (Data.barcode,
/// else parsed from the English detail) is on at most one live product get ResolvedAt / UpdatedAt and Data.resolution "fixed".
/// The developer's Api SyncTests cover: three products (one cleared → still open), a delete, an old issue without Data.
/// These cover what they do not: the barcode CHANGED to a new code, a later re-duplicate (a NEW issue; the old one stays
/// resolved), the owner resolving first, a stale phone resolving an issue the server already closed, another shop with the
/// same barcode, and one unit that fixes one duplicate while creating another.
/// </summary>
[Collection(QaSqlCollection.Name)]
public class QaRound11Tests(SqlServerFixture sql)
{
    private static object ProductUnit(Guid id, string name, string? barcode, DateTime? at = null, DateTime? deletedAt = null)
    {
        var t = at ?? Now();
        return Unit("upsertProduct", new
        {
            products = new[]
            {
                new { id, name, category = "General", unit = "ဗူး", barcode, cost = 450L, price = 600L, lowAlertMilli = 0L,
                      tint = 0, initial = "Q", createdAt = t, updatedAt = t, deletedAt },
            },
        });
    }

    private async Task<List<SyncIssue>> Issues(QaShop shop)
    {
        await using var db = sql.CreateContext(shop.TenantId);
        return await db.SyncIssues.Where(i => i.Kind == SyncIssueKind.DuplicateBarcode).OrderBy(i => i.CreatedAt).ToListAsync();
    }

    private static string? Resolution(SyncIssue i)
    {
        if (i.Data is null) return null;
        using var d = JsonDocument.Parse(i.Data);
        return d.RootElement.TryGetProperty("resolution", out var r) ? r.GetString() : null;
    }

    private static string? DataBarcode(SyncIssue i)
    {
        if (i.Data is null) return null;
        using var d = JsonDocument.Parse(i.Data);
        return d.RootElement.TryGetProperty("barcode", out var r) ? r.GetString() : null;
    }

    private async Task<(QaShop Shop, Guid A, Guid B)> Duplicate(string barcode)
    {
        var shop = await NewShop(sql.Api);
        Guid a = Guid.CreateVersion7(), b = Guid.CreateVersion7();
        (await PushOne(shop, ProductUnit(a, "QA R11 Coke A", barcode))).Outcome.Should().Be(UnitOutcome.Applied);
        (await PushOne(shop, ProductUnit(b, "QA R11 Coke B", barcode))).Outcome.Should().Be(UnitOutcome.Applied);
        (await Issues(shop)).Should().ContainSingle().Which.ResolvedAt.Should().BeNull("setup: one open duplicateBarcode");
        return (shop, a, b);
    }

    // TC-SYNC-NEW-25 (a): the barcode CHANGED (not cleared) on B → closed "fixed", other Data kept, UpdatedAt = ResolvedAt
    // (so every phone pulls it), pulled with resolvedAt + resolution.
    [Fact]
    public async Task TC_SYNC_NEW_25_a_barcode_changed_to_a_new_code_closes_the_issue_fixed_and_phones_pull_it()
    {
        var (shop, _, b) = await Duplicate("8850999311001");
        var cursor = (await PullAllPages(shop)).Last().GetProperty("cursor").GetString()!;
        (await PushOne(shop, ProductUnit(b, "QA R11 Coke B", "8850999311002", Now().AddSeconds(1)))).Outcome.Should().Be(UnitOutcome.Applied);
        var i = (await Issues(shop)).Single();
        i.ResolvedAt.Should().NotBeNull();
        i.UpdatedAt.Should().Be(i.ResolvedAt!.Value);
        (Resolution(i), DataBarcode(i)).Should().Be(("fixed", "8850999311001"));
        var pulled = (await PullAllPages(shop, cursor))
            .SelectMany(p => p.GetProperty("changes").TryGetProperty("syncIssues", out var a) ? a.EnumerateArray() : Enumerable.Empty<JsonElement>())
            .Single(r => r.GetProperty("id").GetGuid() == i.Id);
        pulled.GetProperty("resolvedAt").ValueKind.Should().Be(JsonValueKind.String);
        pulled.GetProperty("data").GetString().Should().Contain("\"resolution\":\"fixed\"");
    }

    // TC-SYNC-NEW-25 (b): a later re-duplicate → a NEW open issue; the old one stays resolved with the same ResolvedAt.
    [Fact]
    public async Task TC_SYNC_NEW_25_b_re_duplicated_later_raises_a_new_issue_and_the_old_one_stays_resolved()
    {
        var (shop, _, b) = await Duplicate("8850999311003");
        (await PushOne(shop, ProductUnit(b, "QA R11 Coke B", null, Now().AddSeconds(1)))).Outcome.Should().Be(UnitOutcome.Applied);
        var closed = (await Issues(shop)).Single();
        closed.ResolvedAt.Should().NotBeNull();

        (await PushOne(shop, ProductUnit(b, "QA R11 Coke B", "8850999311003", Now().AddSeconds(2)))).Outcome.Should().Be(UnitOutcome.Applied);
        var all = await Issues(shop);
        all.Should().HaveCount(2);
        var old = all.Single(x => x.Id == closed.Id);
        (old.ResolvedAt, Resolution(old)).Should().Be((closed.ResolvedAt, "fixed"), "the old one keeps its resolution");
        var fresh = all.Single(x => x.Id != closed.Id);
        fresh.ResolvedAt.Should().BeNull("the new duplicate is a new open issue");
        Resolution(fresh).Should().BeNull();
    }

    // TC-SYNC-NEW-25 (c): the owner taps "စစ်ပြီး" first; then the duplicate is fixed → the owner's resolution is kept
    // (no "fixed" added, ResolvedAt unchanged) → the app shows "စစ်ပြီးပြီ".
    [Fact]
    public async Task TC_SYNC_NEW_25_c_owner_resolves_first_then_the_fix_keeps_the_owner_resolution()
    {
        var (shop, _, b) = await Duplicate("8850999311004");
        var id = (await Issues(shop)).Single().Id;
        var res = await shop.Http.PostAsync($"/api/v1/sync/issues/{id}/resolve", null);
        res.StatusCode.Should().Be(HttpStatusCode.OK, await res.Content.ReadAsStringAsync());
        var byOwner = (await Issues(shop)).Single();
        (await PushOne(shop, ProductUnit(b, "QA R11 Coke B", null, Now().AddSeconds(1)))).Outcome.Should().Be(UnitOutcome.Applied);
        var after = (await Issues(shop)).Single();
        (after.ResolvedAt, after.UpdatedAt, Resolution(after)).Should().Be((byOwner.ResolvedAt, byOwner.UpdatedAt, (string?)null));
    }

    // TC-SYNC-NEW-25 (d): phone B has not pulled the server's close yet and the owner taps "စစ်ပြီး" there → 200, the returned
    // row still says "fixed" with the server's ResolvedAt (B then shows "ပြင်ပြီးသွားပါပြီ").
    [Fact]
    public async Task TC_SYNC_NEW_25_d_a_stale_phone_resolving_an_issue_the_server_already_closed_gets_the_fixed_row()
    {
        var (shop, _, b) = await Duplicate("8850999311005");
        (await PushOne(shop, ProductUnit(b, "QA R11 Coke B", null, Now().AddSeconds(1)))).Outcome.Should().Be(UnitOutcome.Applied);
        var closed = (await Issues(shop)).Single();
        var other = await Login(sql.Api, shop);
        var res = await other.Http.PostAsync($"/api/v1/sync/issues/{closed.Id}/resolve", null);
        res.StatusCode.Should().Be(HttpStatusCode.OK, await res.Content.ReadAsStringAsync());
        var row = JsonDocument.Parse(await res.Content.ReadAsStringAsync()).RootElement;
        row.GetProperty("data").GetString().Should().Contain("\"resolution\":\"fixed\"");
        row.GetProperty("resolvedAt").GetDateTime().ToUniversalTime().Should().Be(closed.ResolvedAt!.Value);
    }

    // TC-SYNC-NEW-25 (e): another shop with the same barcode on two products keeps ITS issue open when shop 1 fixes its own.
    [Fact]
    public async Task TC_SYNC_NEW_25_e_another_shop_with_the_same_duplicate_is_not_closed()
    {
        var (shop1, _, b1) = await Duplicate("8850999311006");
        var (shop2, _, _) = await Duplicate("8850999311006");
        (await PushOne(shop1, ProductUnit(b1, "QA R11 Coke B", null, Now().AddSeconds(1)))).Outcome.Should().Be(UnitOutcome.Applied);
        (await Issues(shop1)).Single().ResolvedAt.Should().NotBeNull();
        (await Issues(shop2)).Single().ResolvedAt.Should().BeNull("tenant scope: shop 2 still has two products with the code");
    }

    // TC-SYNC-NEW-25 (f): ONE unit moves B from barcode X (duplicate of A) to Y (C's barcode) → the X issue closes, a new
    // Y issue opens.
    [Fact]
    public async Task TC_SYNC_NEW_25_f_one_unit_fixing_one_duplicate_and_creating_another()
    {
        var (shop, _, b) = await Duplicate("8850999311007");
        var c = Guid.CreateVersion7();
        (await PushOne(shop, ProductUnit(c, "QA R11 Sprite", "8850999311008"))).Outcome.Should().Be(UnitOutcome.Applied);
        (await PushOne(shop, ProductUnit(b, "QA R11 Coke B", "8850999311008", Now().AddSeconds(1)))).Outcome.Should().Be(UnitOutcome.Applied);
        var all = await Issues(shop);
        all.Select(i => (DataBarcode(i), i.ResolvedAt != null, Resolution(i))).Should().BeEquivalentTo(new[]
        {
            ("8850999311007", true, "fixed"),
            ("8850999311008", false, (string?)null),
        });
    }
}
