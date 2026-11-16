namespace ZayPOS.Application.Text.Zawgyi;

/// <summary>
/// Zawgyi → Unicode for text that phones send (BUG-52). The same rule runs in the app
/// (mobile/lib/core/utils/zawgyi/) so both sides store the same string.
/// </summary>
/// <remarks>
/// The Markov detector alone is not enough: it scores some correct Unicode at 0.99+ (for example
/// "ယခု မိုးရွာနေပါသလား။"), and converting correct Unicode would corrupt it. Text is converted only when
/// it ALSO contains a sequence that cannot occur in well-formed Unicode Burmese (<see cref="HasZawgyiMarker"/>).
/// A Zawgyi string with no such marker is stored as typed: missing a conversion is safer than corrupting
/// correct text.
/// </remarks>
public static class MyanmarText
{
    /// <summary>Detector probability at or above which marked text is treated as Zawgyi.</summary>
    public const double Threshold = 0.5;

    private static readonly Lazy<ZawgyiUnicodeMarkovModel> Model = new(LoadModel, LazyThreadSafetyMode.ExecutionAndPublication);
    private static readonly Lazy<TransliterateZ2U> Z2U = new(() => new TransliterateZ2U(), LazyThreadSafetyMode.ExecutionAndPublication);

    /// <summary>
    /// Probability (0..1) that the text is Zawgyi (Google myanmar-tools); -Infinity when it has no Myanmar code points.
    /// </summary>
    public static double ZawgyiProbability(string text) => Model.Value.Predict(text);

    /// <summary>Google myanmar-tools Zawgyi → Unicode conversion, unconditionally.</summary>
    public static string ZawgyiToUnicode(string text) => Z2U.Value.Convert(text);

    /// <summary>
    /// Returns the Unicode form of <paramref name="text"/> if it is Zawgyi, otherwise the same instance.
    /// </summary>
    public static string? NormalizeToUnicode(string? text)
    {
        if (text is null || !HasZawgyiMarker(text)) return text;
        if (ZawgyiProbability(text) < Threshold) return text;
        return ZawgyiToUnicode(text);
    }

    /// <summary>
    /// True if the text contains something impossible in well-formed Unicode Burmese but typical of Zawgyi:
    /// <list type="number">
    /// <item>U+105A or U+1060–U+1097 (Zawgyi stacked consonants, medial forms and ligatures);</item>
    /// <item>a dependent sign U+102B–U+103E at the start or right after a non-Myanmar character
    /// (Zawgyi types ေ / ျ before the consonant);</item>
    /// <item>U+1039 (virama) not followed by a consonant U+1000–U+1021 (Zawgyi uses it as asat);</item>
    /// <item>U+103A (asat) followed by U+102B–U+102E, U+1032 or U+103B–U+103E (Zawgyi U+103A is the medial ya;
    /// U+102F / U+1030 are excluded because Unicode writes ကျွန်ုပ် with asat + ု).</item>
    /// </list>
    /// </summary>
    public static bool HasZawgyiMarker(string text)
    {
        for (var i = 0; i < text.Length; i++)
        {
            var c = text[i];
            if (c < 'က' || c > '႟') continue;
            if (c == 'ၚ' || c is >= 'ၠ' and <= '႗') return true;
            if (c is >= 'ါ' and <= 'ှ' && (i == 0 || text[i - 1] is < 'က' or > '႟')) return true;
            if (c == '္' && (i + 1 == text.Length || text[i + 1] is < 'က' or > 'အ')) return true;
            if (c == '်' && i + 1 < text.Length
                && text[i + 1] is (>= 'ါ' and <= 'ီ') or 'ဲ' or (>= 'ျ' and <= 'ှ')) return true;
        }
        return false;
    }

    private static ZawgyiUnicodeMarkovModel LoadModel()
    {
        const string name = "ZayPOS.Application.Text.Zawgyi.zawgyiUnicodeModel.dat";
        using var s = typeof(MyanmarText).Assembly.GetManifestResourceStream(name)
                      ?? throw new InvalidOperationException($"Embedded resource {name} is missing.");
        return new ZawgyiUnicodeMarkovModel(s);
    }
}
