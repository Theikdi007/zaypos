// Copyright 2017 Google LLC; C# client copyright 2021 Sei Thu Htun.
// Licensed under the Apache License, Version 2.0 (see LICENSE.txt in this folder).
// Vendored from https://github.com/google/myanmar-tools (clients/c#), commit 13b4af6aaac63849fa122374f93bc77a42674027
// (Markov/BinaryMarkov.cs, Markov/ZawgyiUnicodeMarkovModel.cs, Utils/BigEndianBinaryReader.cs).
// ZayPOS changes: one file, namespace, nullable, internal, BinaryPrimitives for big-endian reads. The model format
// and the prediction are unchanged.

using System.Buffers.Binary;

namespace ZayPOS.Application.Text.Zawgyi;

/// <summary>Reads the big-endian model file (zawgyiUnicodeModel.dat).</summary>
internal sealed class BigEndianReader(Stream stream) : IDisposable
{
    private readonly BinaryReader _r = new(stream);

    public short ReadInt16() => BinaryPrimitives.ReadInt16BigEndian(_r.ReadBytes(2));
    public int ReadInt32() => BinaryPrimitives.ReadInt32BigEndian(_r.ReadBytes(4));
    public long ReadInt64() => BinaryPrimitives.ReadInt64BigEndian(_r.ReadBytes(8));
    public float ReadSingle() => BinaryPrimitives.ReadSingleBigEndian(_r.ReadBytes(4));

    public void Dispose() => _r.Dispose();
}

/// <summary>
/// Behaves as two Markov chains A and B; exposes the difference of their log probabilities.
/// </summary>
internal sealed class BinaryMarkov
{
    /// <summary>"BMARKOV " in ASCII.</summary>
    private const long BinaryTag = 0x424D41524B4F5620L;
    private const int BinaryVersion = 0;

    private readonly float[,] _logProbabilityDifferences;

    public BinaryMarkov(BigEndianReader reader)
    {
        var tag = reader.ReadInt64();
        if (tag != BinaryTag)
            throw new IOException($"Unexpected magic number; expected 0x{BinaryTag:X} but got 0x{tag:X}");
        var version = reader.ReadInt32();
        if (version != BinaryVersion)
            throw new IOException($"Unexpected serial version number; expected 0x{BinaryVersion:X} but got 0x{version:X}");

        var size = reader.ReadInt16();
        var diffs = new float[size, size];
        for (short i1 = 0; i1 < size; i1++)
        {
            var entries = reader.ReadInt16();
            var fallback = entries == 0 ? 0.0f : reader.ReadSingle();
            short next = -1;
            for (short i2 = 0; i2 < size; i2++)
            {
                if (entries > 0 && next < i2)
                {
                    next = reader.ReadInt16();
                    entries--;
                }
                diffs[i1, i2] = next == i2 ? reader.ReadSingle() : fallback;
            }
        }
        _logProbabilityDifferences = diffs;
    }

    public float GetLogProbabilityDifference(int i1, int i2) => _logProbabilityDifferences[i1, i2];
}

/// <summary>
/// Two Markov chains, Unicode and Zawgyi; the string is scored against both. Every code point outside the
/// Myanmar blocks (and U+2000–U+200B) is the NULL state. Immutable after construction (thread-safe).
/// </summary>
internal sealed class ZawgyiUnicodeMarkovModel
{
    /// <summary>"UZMODEL " in ASCII.</summary>
    private const long BinaryTag = 0x555A4D4F44454C20L;

    private const int StdCp0 = 0x1000, StdCp1 = 0x103F;   // Myanmar before the digits
    private const int AftCp0 = 0x104A, AftCp1 = 0x109F;   // Myanmar after the digits
    private const int ExaCp0 = 0xAA60, ExaCp1 = 0xAA7F;   // Myanmar Extended-A
    private const int ExbCp0 = 0xA9E0, ExbCp1 = 0xA9FF;   // Myanmar Extended-B
    private const int SpcCp0 = 0x2000, SpcCp1 = 0x200B;   // Unicode spaces

    private const int StdOffset = 1;
    private const int AftOffset = StdOffset + StdCp1 - StdCp0 + 1;
    private const int ExaOffset = AftOffset + AftCp1 - AftCp0 + 1;
    private const int ExbOffset = ExaOffset + ExaCp1 - ExaCp0 + 1;
    private const int SpcOffset = ExbOffset + ExbCp1 - ExbCp0 + 1;

    /// <summary>SSV ("state set version"): 0 = Myanmar, Extended A/B and space-like; 1 = without space-like.</summary>
    private const int SsvStdExaExbSpc = 0;
    private const int SsvCount = 2;

    private readonly BinaryMarkov _classifier;
    private readonly int _ssv;

    public ZawgyiUnicodeMarkovModel(Stream stream)
    {
        using var reader = new BigEndianReader(stream);
        var tag = reader.ReadInt64();
        if (tag != BinaryTag)
            throw new IOException($"Unexpected magic number; expected 0x{BinaryTag:X} but got 0x{tag:X}");
        var version = reader.ReadInt32();
        _ssv = version switch
        {
            1 => SsvStdExaExbSpc, // version 1 has no SSV field
            2 => reader.ReadInt32(),
            _ => throw new IOException($"Unexpected serial version number; expected 1 or 2 but got {version}"),
        };
        if (_ssv is < 0 or >= SsvCount)
            throw new IOException($"Unexpected value in ssv position; expected 0 or 1 but got {_ssv}");
        _classifier = new BinaryMarkov(reader);
    }

    private static int GetIndexForCodePoint(int cp, int ssv)
    {
        if (cp is >= StdCp0 and <= StdCp1) return cp - StdCp0 + StdOffset;
        if (cp is >= AftCp0 and <= AftCp1) return cp - AftCp0 + AftOffset;
        if (cp is >= ExaCp0 and <= ExaCp1) return cp - ExaCp0 + ExaOffset;
        if (cp is >= ExbCp0 and <= ExbCp1) return cp - ExbCp0 + ExbOffset;
        if (ssv == SsvStdExaExbSpc && cp is >= SpcCp0 and <= SpcCp1) return cp - SpcCp0 + SpcOffset;
        return 0;
    }

    /// <summary>
    /// Probability (0..1) that the string is Zawgyi given that it is Unicode or Zawgyi;
    /// <see cref="double.NegativeInfinity"/> if it has no Myanmar code points.
    /// </summary>
    public double Predict(string input)
    {
        var prevState = 0;
        var totalDelta = 0.0;
        var seenTransition = false;
        for (var offset = 0; offset <= input.Length; offset++)
        {
            var currState = offset == input.Length ? 0 : GetIndexForCodePoint(input[offset], _ssv);
            // Ignore 0-to-0 transitions
            if (prevState != 0 || currState != 0)
            {
                totalDelta += _classifier.GetLogProbabilityDifference(prevState, currState);
                seenTransition = true;
            }
            prevState = currState;
        }
        // No signal (no Myanmar code points): -Infinity, read by callers as strong Unicode.
        return seenTransition ? 1.0 / (1.0 + Math.Exp(totalDelta)) : double.NegativeInfinity;
    }
}
