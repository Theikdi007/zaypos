using FluentAssertions;
using ZayPOS.Application.Auth;

namespace ZayPOS.Api.Tests;

public class AuthRulesTests
{
    [Theory]
    [InlineData(0, "A")]
    [InlineData(1, "B")]
    [InlineData(25, "Z")]
    [InlineData(26, "AA")]
    [InlineData(27, "AB")]
    [InlineData(26 + 26 * 26 - 1, "ZZ")]
    [InlineData(26 + 26 * 26, "AAA")]
    [InlineData(DeviceCodes.MaxIndex - 1, "ZZZ")]
    public void Device_codes_follow_A_to_Z_then_AA(int index, string code) =>
        DeviceCodes.ForIndex(index).Should().Be(code);

    [Fact]
    public void Next_free_code_fills_gaps()
    {
        DeviceCodes.NextFree([]).Should().Be("A");
        DeviceCodes.NextFree(["A", "B"]).Should().Be("C");
        DeviceCodes.NextFree(["A", "C"]).Should().Be("B");
        DeviceCodes.NextFree(Enumerable.Range(0, 26).Select(DeviceCodes.ForIndex)).Should().Be("AA");
    }

    [Theory]
    [InlineData("09 7xx", null)]
    [InlineData("0971234567", "+95971234567")]
    [InlineData("09-797-123-456", "+959797123456")]
    [InlineData("+959797123456", "+959797123456")]
    [InlineData("959797123456", "+959797123456")]
    [InlineData("+66812345678", null)]
    [InlineData("091234", null)]
    [InlineData("", null)]
    public void Phones_normalize_to_E164(string input, string? expected) =>
        PhoneNumbers.Normalize(input).Should().Be(expected);

    [Theory]
    [InlineData("123456", true)]
    [InlineData("12345", false)]
    [InlineData("1234567", false)]
    [InlineData("12a456", false)]
    [InlineData(null, false)]
    public void Pins_are_six_digits(string? pin, bool valid) => Pins.IsValid(pin).Should().Be(valid);
}
