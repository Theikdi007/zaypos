// Copyright 2017 Google LLC; C# client copyright 2021 Sei Thu Htun.
// Licensed under the Apache License, Version 2.0 (see LICENSE.txt in this folder).
// Vendored from https://github.com/google/myanmar-tools (clients/c#), commit 13b4af6aaac63849fa122374f93bc77a42674027
// (Rule.cs, Phase.cs, Transliterate/Transliterate.cs). ZayPOS changes: one file, namespace, nullable, internal,
// immutable after construction (thread-safe). The matching algorithm is unchanged.

using System.Text;
using System.Text.RegularExpressions;

namespace ZayPOS.Application.Text.Zawgyi;

/// <summary>A rule of a transliteration phase. The pattern is anchored at the current position.</summary>
internal sealed class Rule(string patternString, string substitution)
{
    public string Substitution { get; } = substitution;
    public bool MatchOnStart { get; private set; }
    public int RevisitPosition { get; private set; } = -1;
    public Regex Pattern { get; } = new($"^{patternString}");

    public Rule SetMatchOnStart()
    {
        MatchOnStart = true;
        return this;
    }

    public Rule SetRevisitPosition(int newPos)
    {
        RevisitPosition = newPos;
        return this;
    }
}

/// <summary>A transliteration phase: an ordered list of rules.</summary>
internal sealed class Phase
{
    private readonly List<Rule> _rules = [];

    public void AddRule(Rule rule) => _rules.Add(rule);

    public string RunPhase(string inString)
    {
        var outString = new StringBuilder();
        var midString = inString;
        var startOfString = true;

        while (!string.IsNullOrEmpty(midString))
        {
            // Move through the string, matching / applying rules.
            var foundRule = false;
            foreach (var rule in _rules)
            {
                if (rule.MatchOnStart && !startOfString) continue;
                var match = rule.Pattern.Match(midString);
                if (!match.Success) continue;
                foundRule = true;
                var substitution = match.Result(rule.Substitution);
                if (rule.RevisitPosition < 0)
                {
                    // Reset the new position to the end of the substitution.
                    outString.Append(substitution);
                    midString = midString[match.Length..];
                }
                else
                {
                    midString = string.Concat(substitution, midString[match.Length..]);
                }
            }
            if (!foundRule)
            {
                // Move forward by 1.
                outString.Append(midString[0]);
                midString = midString[1..];
            }
            startOfString = false;
        }
        return outString.ToString();
    }
}

/// <summary>Runs the phases in order, like the ICU4J transliterator.</summary>
internal abstract class Transliterate(string name)
{
    private readonly List<Phase> _phases = [];

    public string Name { get; } = name;

    protected Phase AddPhase()
    {
        var phase = new Phase();
        _phases.Add(phase);
        return phase;
    }

    public string Convert(string inString)
    {
        var s = inString;
        foreach (var phase in _phases) s = phase.RunPhase(s);
        return s;
    }
}
