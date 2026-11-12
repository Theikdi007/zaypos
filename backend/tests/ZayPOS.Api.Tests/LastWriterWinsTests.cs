using FluentAssertions;
using ZayPOS.Application.Sync;
using static ZayPOS.Application.Sync.LastWriterWins;

namespace ZayPOS.Api.Tests;

public class LastWriterWinsTests
{
    private static readonly DateTime T = new(2026, 11, 11, 9, 0, 0, DateTimeKind.Utc);
    private static readonly DateTime Later = T.AddMinutes(1);
    private static readonly DateTime Earlier = T.AddMinutes(-1);

    [Fact] public void New_row_is_inserted() => Decide(null, null, T, null, false).Should().Be(LwwAction.Insert);
    [Fact] public void Newer_edit_wins() => Decide(T, null, Later, null, false).Should().Be(LwwAction.Update);
    [Fact] public void Older_edit_loses() => Decide(T, null, Earlier, null, false).Should().Be(LwwAction.Ignore);
    [Fact] public void Same_time_keeps_server() => Decide(T, null, T, null, false).Should().Be(LwwAction.Ignore);
    [Fact] public void Newer_delete_wins() => Decide(T, null, Later, Later, false).Should().Be(LwwAction.Update);
    [Fact] public void Older_delete_still_deletes() => Decide(T, null, Earlier, Earlier, false).Should().Be(LwwAction.DeleteOnly);
    [Fact] public void Edit_of_deleted_row_is_ignored() => Decide(T, T, Later, null, false).Should().Be(LwwAction.Ignore);
    [Fact] public void Newer_restore_undeletes() => Decide(T, T, Later, null, true).Should().Be(LwwAction.Update);
    [Fact] public void Older_restore_is_ignored() => Decide(T, T, Earlier, null, true).Should().Be(LwwAction.Ignore);

    [Theory]
    [InlineData(null, "0000000000000000")]
    [InlineData("0", "0000000000000000")]
    [InlineData("A3F21", "00000000000A3F21")]
    [InlineData("0x00000000000A3F21", "00000000000A3F21")]
    public void Cursor_round_trips(string? input, string expected) =>
        SyncCursor.Format(SyncCursor.Parse(input)).Should().Be(expected);

    [Fact]
    public void Cursor_compares_like_rowversion() =>
        SyncCursor.Compare(SyncCursor.Parse("00000000000000FF"), SyncCursor.Parse("0000000000000100")).Should().BeNegative();
}
