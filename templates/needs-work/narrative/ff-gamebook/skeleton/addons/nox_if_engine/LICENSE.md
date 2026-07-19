# nox_if_engine — License

Copyright (c) NoxDev Studio.

The `nox_if_engine` addon (engine code, probe, and the shipped ruleset/scenario
data) is released for use within NoxDev Studio projects and the games they
generate.

## Ruleset licensing note (important)

The shipped rulesets (`ff-2d6`, `srd-d20`, `pbta`) are **genericised, original
reimplementations** of the *math* of well-known resolution families (2d6
roll-under; d20 + modifier vs a Difficulty Class; 2d6 + stat threshold bands).
They contain **no third-party rules text, adventure text, monster stats, or
trademarks** — only the numeric resolution structure, which is not itself
copyrightable. They are clearly labelled as genericised builtins.

**User-imported systems stay the user's data.** The engine is an interpreter;
importing a system you own (or one that is openly licensed) keeps that content
under its own terms — the engine never bundles or redistributes it. This is the
license-safe posture from the gamebook engine spec §1.
