// Assets/Scripts/Engine/IFPortableCheck.cs
// The ruleset-portability layer (spec §2.5, P2) — the abstraction that lets ONE
// scenario run under EVERY system. Counterpart to IFResolver: the resolver runs a
// system's OWN rule; this compiler lets a scenario name a check in a system-
// AGNOSTIC interlingua and have each ruleset express it in its own resolution math.
// Faithful C# port of if_portable_check.gd (every branch, error string, and the
// fallback ladder preserved).
using System.Collections.Generic;
using Newtonsoft.Json.Linq;

namespace NoxIfEngine
{
    public static class IFPortableCheck
    {
        // --- The interlingua: three fixed canonical vocabularies ---
        public static readonly string[] CanonicalAttributes =
            { "prowess", "agility", "might", "wits", "presence", "resolve" };

        public static readonly string[] CanonicalDifficulties =
            { "trivial", "easy", "standard", "hard", "formidable", "heroic" };

        public static readonly string[] CanonicalBands =
            { "critSuccess", "success", "partial", "failure", "critFailure" };

        // Routing fallback ladder — when a resolved canonical band isn't explicitly
        // authored in the scenario's outcomes, try these in order, then _default.
        static readonly Dictionary<string, string[]> BandFallback = new Dictionary<string, string[]>
        {
            ["critSuccess"] = new[] { "critSuccess", "success" },
            ["success"] = new[] { "success" },
            ["partial"] = new[] { "partial", "success" },
            ["failure"] = new[] { "failure" },
            ["critFailure"] = new[] { "critFailure", "failure" },
        };

        static string Str(JToken t) => t == null || t.Type == JTokenType.Null ? "" : t.ToString();

        static bool Contains(string[] arr, string v)
        {
            foreach (var s in arr) if (s == v) return true;
            return false;
        }

        /// <summary>Is this check node the portable shape (names a `semantic`)?</summary>
        public static bool IsPortable(JToken check) =>
            check is JObject o && o["semantic"] != null;

        /// <summary>Compile a portable check into a concrete resolver call for `ruleset`.</summary>
        public static JObject Compile(JObject check, IFRuleset ruleset)
        {
            var semantic = Str(check["semantic"]);
            if (semantic == "") return Err("portable check has no 'semantic'");
            if (ruleset == null) return Err($"no ruleset supplied to compile semantic '{semantic}'");
            if (!ruleset.HasSemantic(semantic))
                return Err($"ruleset '{ruleset.Id}' declares no mapping for semantic '{semantic}'");

            var sdef = ruleset.SemanticDef(semantic);
            var ruleId = Str(sdef["rule"]);
            if (ruleId == "" || !ruleset.Rules.ContainsKey(ruleId))
                return Err($"semantic '{semantic}' -> unknown resolution rule '{ruleId}' in ruleset '{ruleset.Id}'");

            var args = new JObject();

            // 1) static args the semantic always supplies.
            if (sdef["args"] is JObject sargs)
                foreach (var p in sargs) args[p.Key] = p.Value;

            // 2) the canonical attribute -> this system's native attribute.
            var canonAttr = Str(check["attribute"]);
            if (canonAttr != "")
            {
                if (!Contains(CanonicalAttributes, canonAttr))
                    return Err($"unknown canonical attribute '{canonAttr}'");
                var native = ruleset.NativeAttributeFor(canonAttr);
                if (native == "")
                    return Err($"ruleset '{ruleset.Id}' does not map canonical attribute '{canonAttr}'");
                if (!ruleset.HasAttribute(native))
                    return Err($"ruleset '{ruleset.Id}' attributeMap '{canonAttr}'->'{native}' names a non-attribute");
                var attrArg = Str(sdef["attrArg"]);
                if (attrArg != "") args[attrArg] = native;
            }

            // 3) the canonical difficulty -> a per-system number, applied by mode.
            var diff = check["difficulty"] != null ? Str(check["difficulty"]) : "standard";
            var ddef = sdef["difficulty"] as JObject;
            if (ddef != null && ddef.HasValues)
            {
                if (!Contains(CanonicalDifficulties, diff))
                    return Err($"unknown canonical difficulty '{diff}'");
                var ladder = ddef["ladder"] as JObject;
                if (ladder == null || ladder[diff] == null)
                    return Err($"semantic '{semantic}' difficulty ladder has no rung '{diff}' in ruleset '{ruleset.Id}'");
                var value = (double)ladder[diff];
                switch (Str(ddef["mode"]))
                {
                    case "dc":
                        args[ddef["arg"] != null ? Str(ddef["arg"]) : "dc"] = value;
                        break;
                    case "targetDelta":
                        args["_targetDelta"] = value;
                        break;
                    case "rollModifier":
                        args["_rollModifier"] = value;
                        break;
                    default:
                        return Err($"semantic '{semantic}' has unknown difficulty mode '{Str(ddef["mode"])}'");
                }
            }

            // 4) explicit per-call passthrough on the check itself.
            if (check["args"] is JObject cargs)
                foreach (var p in cargs) args[p.Key] = p.Value;

            return new JObject { ["ok"] = true, ["error"] = "", ["rule"] = ruleId, ["args"] = args, ["semantic"] = semantic };
        }

        /// <summary>Map a native band id to a canonical band, via the ruleset's outcomeMap.</summary>
        public static string CanonicalBand(string nativeBand, IFRuleset ruleset) =>
            ruleset.CanonicalBandFor(nativeBand);

        /// <summary>Pick the scenario outcome for a resolved canonical band, applying the fallback ladder then _default.</summary>
        public static JObject ResolveOutcome(JObject outcomes, string canonBand)
        {
            var chain = BandFallback.TryGetValue(canonBand, out var c) ? c : new[] { canonBand };
            foreach (var b in chain)
                if (outcomes[b] is JObject ob) return ob;
            if (outcomes["_default"] is JObject def) return def;
            return new JObject();
        }

        /// <summary>Structural validation of a portable check against a ruleset (null ruleset = shape-only).</summary>
        public static List<string> Validate(JObject check, string pid, IFRuleset ruleset)
        {
            var problems = new List<string>();
            var semantic = Str(check["semantic"]);
            if (semantic == "")
            {
                problems.Add($"passage '{pid}' portable check has no 'semantic'");
                return problems;
            }

            var canonAttr = Str(check["attribute"]);
            if (canonAttr != "" && !Contains(CanonicalAttributes, canonAttr))
                problems.Add($"passage '{pid}' check names unknown canonical attribute '{canonAttr}'");
            var diff = check["difficulty"] != null ? Str(check["difficulty"]) : "standard";
            if (!Contains(CanonicalDifficulties, diff))
                problems.Add($"passage '{pid}' check names unknown canonical difficulty '{diff}'");

            if (check["outcomes"] is JObject outs)
                foreach (var p in outs)
                {
                    var b = p.Key;
                    if (b != "_default" && !Contains(CanonicalBands, b))
                        problems.Add($"passage '{pid}' outcome '{b}' is not a canonical band");
                }

            if (ruleset != null)
            {
                var compiled = Compile(check, ruleset);
                if (!(bool)(compiled["ok"] ?? false))
                    problems.Add($"passage '{pid}' check: {Str(compiled["error"])}");
            }
            return problems;
        }

        static JObject Err(string msg) =>
            new JObject { ["ok"] = false, ["error"] = msg, ["rule"] = "", ["args"] = new JObject(), ["semantic"] = "" };
    }
}
