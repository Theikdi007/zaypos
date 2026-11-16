# Vendored: Google myanmar-tools (Zawgyi detector + Zawgyi→Unicode converter)

- Source: https://github.com/google/myanmar-tools, `clients/c#`, commit `13b4af6aaac63849fa122374f93bc77a42674027` (2024-03-26).
- License: Apache License 2.0 (`LICENSE.txt`). Copyright 2017 Google LLC; C# client copyright 2021 Sei Thu Htun.
- Why vendored: no maintained NuGet package. Google does not publish the C# client; `MyanmarTools.NET` is a
  single-author port with no license expression.
- Taken: `zawgyiUnicodeModel.dat` (byte-identical to the Java/Dart/C# clients, SHA-1 `4211ebf2…ec66`), the Markov model
  reader, the rule engine and the Z2U rules. Not taken: U2Z and Zawgyi normalisation (unused).
- Changes: namespace, `internal`, nullable, immutability; the model is loaded as an embedded resource instead of
  `./resources/…`. The rules and the scoring are unchanged (the ported upstream tests pass: `ZawgyiTests`).
- ZayPOS's own rule (when to convert) is in `MyanmarText.cs` and mirrors the app.
