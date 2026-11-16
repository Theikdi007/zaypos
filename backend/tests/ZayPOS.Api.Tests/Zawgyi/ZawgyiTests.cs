using System.Globalization;
using FluentAssertions;
using ZayPOS.Application.Text.Zawgyi;

namespace ZayPOS.Api.Tests.Zawgyi;

/// <summary>
/// BUG-52: the vendored Google myanmar-tools detector and converter, ported from the upstream tests, plus ZayPOS's
/// rule for when to convert (<see cref="MyanmarText.NormalizeToUnicode"/>), run against real Zawgyi and Unicode text.
/// Corpora: UDHR in Burmese (unicode.org) and a Myanmar government text, from upstream clients/c#/Resources.
/// </summary>
public class ZawgyiTests
{
    private static string[] Lines(string file) =>
        File.ReadAllLines(Path.Combine(AppContext.BaseDirectory, "Zawgyi", file));

    // ------------------------------------------------------------ upstream: detector

    [Fact]
    public void Detector_returns_minus_infinity_without_Myanmar_code_points()
    {
        MyanmarText.ZawgyiProbability("hello world").Should().Be(double.NegativeInfinity);
        MyanmarText.ZawgyiProbability("၉၆.၀ kHz").Should().Be(double.NegativeInfinity, "digits are ignored");
        MyanmarText.ZawgyiProbability("၂၄၀၉ ဒဂုန်").Should().Be(MyanmarText.ZawgyiProbability("ဒဂုန်"));
    }

    [Fact]
    public void Detector_separates_strong_Unicode_and_strong_Zawgyi()
    {
        MyanmarText.ZawgyiProbability("အပြည်ပြည်ဆိုင်ရာ လူ့အခွင့်အရေး ကြေညာစာတမ်း").Should().BeLessThan(0.001);
        MyanmarText.ZawgyiProbability("အျပည္ျပည္ဆိုင္ရာ လူ႔အခြင့္အေရး ေၾကညာစာတမ္း").Should().BeGreaterThan(0.999);
        MyanmarText.ZawgyiProbability("<span>blah blah ဒဂုန်ဦးစန်းငွေ </span> blah blah blah blah").Should().BeLessThan(0.01);
        MyanmarText.ZawgyiProbability("blah blah blah blah blah သို႔သြားပါ။ blah blah blah").Should().BeGreaterThan(0.99);
    }

    [Theory]
    [InlineData("အသံကို အစားထိုးလိုပါသလား။", 0.995)] // identical in U/Z
    [InlineData("နမူနာ", 0.26)]                       // identical in U/Z
    [InlineData(" \u1025\u102E\u1038", 0.35)]               // " ဦး" with U+1025 U+102E, as upstream; identical in U/Z
    [InlineData("အစားထိုး အထူးအက္ခရာ", 0.995)]        // Unicode with a high Zawgyi score
    [InlineData("ယခု မိုးရွာနေပါသလား။", 0.995)]       // Unicode with a high Zawgyi score
    [InlineData("အခြား", 0.74)]                        // Unicode
    [InlineData("ကာမစာအုပ္မ်ား(ေစာက္ပတ္စာအုပ္မ်ား)", 1.0)] // Zawgyi
    [InlineData("ညႇပ္စရာမလို", 0.82)]                 // Zawgyi
    public void Detector_difficult_strings_score_like_upstream(string input, double expected) =>
        MyanmarText.ZawgyiProbability(input).Should().BeApproximately(expected, 0.005);

    [Fact]
    public void Detector_reproduces_upstream_compatibility_tsv()
    {
        var lines = Lines("compatibility.tsv");
        lines.Should().NotBeEmpty();
        foreach (var line in lines)
        {
            var tab = line.IndexOf('\t');
            var expected = line[..tab];
            var input = line[(tab + 1)..];
            var actual = MyanmarText.ZawgyiProbability(input);
            if (expected == "-Infinity") actual.Should().Be(double.NegativeInfinity, input);
            else actual.Should().BeApproximately(double.Parse(expected, CultureInfo.InvariantCulture), 1e-6, input);
        }
    }

    // ------------------------------------------------------------ upstream: converter

    [Fact]
    public void Converter_leaves_non_Myanmar_text_alone()
    {
        MyanmarText.ZawgyiToUnicode("hello world").Should().Be("hello world");
        MyanmarText.ZawgyiToUnicode("ထ္").Should().Be("ထ်");
    }

    public static IEnumerable<object[]> Z2UCases => UpstreamZ2UCases.TestCases;

    [Theory]
    [MemberData(nameof(Z2UCases))]
    public void Converter_matches_upstream_Z2U_cases(string zawgyi, string unicode) =>
        MyanmarText.ZawgyiToUnicode(zawgyi).Should().Be(unicode);

    [Fact]
    public void Converter_matches_the_mmgov_golden_file_line_by_line()
    {
        var src = Lines("mmgov_zawgyi_src.txt");
        var golden = Lines("mmgov_unicode_out.txt");
        src.Length.Should().Be(golden.Length);
        for (var i = 0; i < src.Length; i++)
            MyanmarText.ZawgyiToUnicode(src[i]).Should().Be(golden[i], $"line {i + 1}");
    }

    // ------------------------------------------------------------ ZayPOS rule: NormalizeToUnicode

    [Fact]
    public void QA_sample_name_is_converted()
    {
        // TC-DEBT-NEW-14: what a Zawgyi keyboard sends for မောင်မောင်.
        MyanmarText.NormalizeToUnicode("ေမာင္ေမာင္").Should().Be("မောင်မောင်");
        MyanmarText.NormalizeToUnicode("ေမာင္ေမာင္").Should().Be("မောင်မောင်");
    }

    [Theory]
    [InlineData("စကားခ်ီး", "စကားချီး")]                // only marker 4 (asat + vowel) catches it
    [InlineData("ျမန္မာ", "မြန်မာ")]                    // leading medial
    [InlineData("သို႔သြားပါ။", "သို့သွားပါ။")]          // U+1094
    [InlineData("ႏိုင္ငံ", "နိုင်ငံ")]                  // U+108F
    [InlineData("ဦးေက်ာ္ေက်ာ္ ဆိုင္", "ဦးကျော်ကျော် ဆိုင်")]
    public void Real_Zawgyi_strings_are_converted(string zawgyi, string unicode)
    {
        MyanmarText.HasZawgyiMarker(zawgyi).Should().BeTrue();
        MyanmarText.NormalizeToUnicode(zawgyi).Should().Be(unicode);
    }

    [Theory]
    [InlineData("ယခု မိုးရွာနေပါသလား။")]   // detector 0.9997, valid Unicode
    [InlineData("အစားထိုး အထူးအက္ခရာ")]    // detector 0.995, valid Unicode
    [InlineData("ကျွန်ုပ်")]               // asat + ု is valid Unicode (marker 4 excludes U+102F)
    [InlineData("မောင်မောင်")]
    [InlineData("ဒေါ်ခင်မာ")]
    [InlineData("ဆေးဆိုင်")]
    [InlineData("အင်္ဂလိပ်")]              // kinzi: U+1039 followed by a consonant
    [InlineData("09 ၇၇၇ ၁၂၃ ၄၅၆")]
    public void Unicode_text_is_returned_unchanged(string unicode) =>
        MyanmarText.NormalizeToUnicode(unicode).Should().BeSameAs(unicode);

    [Theory]
    [InlineData("")]
    [InlineData("Coca-Cola 330ml")]
    [InlineData("8850999150003")]
    [InlineData("+959790917151")]
    public void Non_Myanmar_text_is_the_same_instance(string s) =>
        MyanmarText.NormalizeToUnicode(s).Should().BeSameAs(s);

    [Fact]
    public void Null_stays_null() => MyanmarText.NormalizeToUnicode(null).Should().BeNull();

    [Fact]
    public void Every_line_of_the_Unicode_corpora_is_unchanged()
    {
        var lines = Lines("udhr_mya_unicode_src.txt").Concat(Lines("mmgov_unicode_out.txt"))
            .Where(l => l.Any(c => c is >= 'က' and <= '႟')).ToList();
        lines.Should().HaveCount(154, "91 UDHR + 63 mmgov lines contain Myanmar text");
        var changed = lines.Where(l => !ReferenceEquals(MyanmarText.NormalizeToUnicode(l), l)).ToList();
        changed.Should().BeEmpty("correct Unicode must never be converted");
    }

    [Fact]
    public void Every_differing_line_of_the_mmgov_Zawgyi_corpus_is_converted_to_the_golden_Unicode()
    {
        var src = Lines("mmgov_zawgyi_src.txt");
        var golden = Lines("mmgov_unicode_out.txt");
        var misses = Enumerable.Range(0, src.Length)
            .Where(i => src[i] != golden[i] && MyanmarText.NormalizeToUnicode(src[i]) != golden[i])
            .Select(i => src[i]).ToList();
        misses.Should().BeEmpty();
    }

    [Fact]
    public void UDHR_Zawgyi_corpus_is_converted_except_one_known_unmarked_line()
    {
        // The UDHR Zawgyi file is upstream's U2Z output of the Unicode file, so it is compared with Z2U of itself
        // (what the converter would produce) rather than with the original Unicode.
        var src = Lines("udhr_mya_zawgyi_out.txt");
        var unicode = Lines("udhr_mya_unicode_src.txt");
        src.Length.Should().Be(unicode.Length);
        var misses = Enumerable.Range(0, src.Length)
            .Where(i => src[i] != unicode[i])
            .Where(i => MyanmarText.NormalizeToUnicode(src[i]) != MyanmarText.ZawgyiToUnicode(src[i]))
            .Select(i => src[i].Trim()).ToList();
        // p ≈ 0.69 and no marker: the line is also well-formed (if wrong) Unicode, so it is kept as typed.
        misses.Should().Equal("အေထြေထြညီလာခံ က");
    }
}
