// Assets/Scripts/Engine/IFDice.cs
// Unity C# port of res://addons/nox_if_engine/if_dice.gd (faithful, 1:1).
//
// Seedable dice-expression roller — the deterministic randomness source for the
// whole computed engine. Parses the standard tabletop expression grammar
// `NdM`, `NdM+K`, `NdM-K` (e.g. `2d6`, `1d20`, `1d6+6`, `2d6+12`) and returns
// the individual die faces PLUS the summed total, because the resolution layer
// needs the faces to judge criticals (double-1s under FF, a natural-20 under
// d20 — see IFResolver) and the total to compare.
//
// Every roll advances one owned IfRng, so a fixed seed replays a scenario
// deterministically. This mirrors the GDScript contract (`set_seed`), lifted
// here to be system-agnostic: the roller knows nothing about SKILL, DC or
// bands — only faces. It uses the shared IfRng instead of Godot's
// RandomNumberGenerator.
using System.Collections.Generic;
using Newtonsoft.Json.Linq;

namespace NoxIfEngine
{
    public sealed class IFDice
    {
        private readonly IfRng _rng;

        // Cache of parsed expressions so repeated rolls of the same string don't re-parse.
        private readonly Dictionary<string, JObject> _parseCache = new Dictionary<string, JObject>();

        // GDScript _init(rng_seed := 0): a non-zero seed is fixed (deterministic),
        // seed 0 randomizes (Godot's _rng.randomize()) for a non-reproducible run.
        public IFDice(long seed = 0)
        {
            _rng = new IfRng();
            if (seed != 0)
            {
                _rng.SetSeed(seed);
            }
            else
            {
                // Emulate RandomNumberGenerator.randomize(): a non-deterministic seed.
                long entropy = unchecked(System.DateTime.UtcNow.Ticks ^ ((long)System.Guid.NewGuid().GetHashCode() << 32));
                _rng.SetSeed(entropy);
            }
        }

        /// <summary>Deterministic rolls for tests/replays. Mirrors GDScript set_seed.</summary>
        public void SetSeed(long seed) => _rng.SetSeed(seed);

        /// <summary>
        /// The current RNG state — lets a Runner snapshot/restore mid-scenario
        /// (save/load) so a resumed session keeps rolling the same sequence.
        /// </summary>
        public ulong GetState() => _rng.GetState();

        public void SetState(ulong s) => _rng.SetState(s);

        /// <summary>
        /// Parse `NdM(+/-K)` into `{count, sides, modifier, expr}`. Logs via
        /// LogError on a malformed expression and returns a safe 1d1 so a single
        /// bad datum can't crash a whole play — but the error is loud, never silent.
        /// </summary>
        public JObject Parse(string expr)
        {
            string key = (expr ?? "").Trim();
            if (_parseCache.TryGetValue(key, out JObject cached))
                return cached;
            JObject parsed = ParseInternal(key);
            _parseCache[key] = parsed;
            return parsed;
        }

        /// <summary>
        /// Pure, side-effect-free validation of a dice expression for the ruleset
        /// validator/importer — mirrors ParseInternal's grammar but logs NOTHING and
        /// never returns a "safe default"; it reports precisely what is wrong. Accepts
        /// `NdM`, `NdM+K`, `NdM-K` and a bare integer constant `K` (a gen like "0").
        /// Returns { ok: bool, error: String }.
        /// </summary>
        public static JObject ValidateExpr(string expr)
        {
            string s = (expr ?? "").Trim().ToLowerInvariant().Replace(" ", "");
            if (s == "")
                return new JObject { ["ok"] = false, ["error"] = "empty dice expression" };
            string modifierStr = "";
            string body = s;
            int plus = s.IndexOf('+');
            int minus = s.IndexOf('-');
            int signAt = -1;
            if (plus >= 0)
                signAt = plus;
            if (minus >= 0 && (signAt < 0 || minus < signAt))
                signAt = minus;
            if (signAt == 0)
                return new JObject { ["ok"] = false, ["error"] = $"expression '{expr}' starts with a sign" };
            if (signAt > 0)
            {
                body = s.Substring(0, signAt);
                modifierStr = s.Substring(signAt);
                if (!IsValidInt(modifierStr))
                    return new JObject { ["ok"] = false, ["error"] = $"bad modifier '{modifierStr}' in '{expr}'" };
            }
            if (!body.Contains("d"))
            {
                if (IsValidInt(body))
                    return new JObject { ["ok"] = true, ["error"] = "" };
                return new JObject { ["ok"] = false, ["error"] = $"malformed expression '{expr}'" };
            }
            string[] halves = body.Split('d');
            if (halves.Length != 2)
                return new JObject { ["ok"] = false, ["error"] = $"malformed dice body '{body}'" };
            if (halves[0] != "" && !IsValidInt(halves[0]))
                return new JObject { ["ok"] = false, ["error"] = $"bad dice count in '{expr}'" };
            if (!IsValidInt(halves[1]))
                return new JObject { ["ok"] = false, ["error"] = $"bad dice sides in '{expr}'" };
            int count = halves[0] == "" ? 1 : ToInt(halves[0]);
            int sides = ToInt(halves[1]);
            if (count < 1)
                return new JObject { ["ok"] = false, ["error"] = $"non-positive dice count in '{expr}'" };
            if (sides < 1)
                return new JObject { ["ok"] = false, ["error"] = $"non-positive dice sides in '{expr}'" };
            return new JObject { ["ok"] = true, ["error"] = "" };
        }

        private JObject ParseInternal(string expr)
        {
            string s = (expr ?? "").Trim().ToLowerInvariant().Replace(" ", "");
            if (s == "")
            {
                LogError("IFDice: empty dice expression");
                return new JObject { ["count"] = 1, ["sides"] = 1, ["modifier"] = 0, ["expr"] = expr };
            }
            // Split off a trailing +K / -K modifier.
            int modifier = 0;
            string body = s;
            int plus = s.IndexOf('+');
            int minus = s.IndexOf('-');
            int signAt = -1;
            if (plus >= 0)
                signAt = plus;
            if (minus >= 0 && (signAt < 0 || minus < signAt))
                signAt = minus;
            if (signAt >= 0)
            {
                body = s.Substring(0, signAt);
                string modStr = s.Substring(signAt);
                if (!IsValidInt(modStr))
                    LogError($"IFDice: bad modifier in '{expr}'");
                modifier = ToInt(modStr);
            }
            // body is now "NdM" or a bare constant "K".
            if (!body.Contains("d"))
            {
                if (IsValidInt(body))
                    return new JObject { ["count"] = 0, ["sides"] = 0, ["modifier"] = ToInt(body) + modifier, ["expr"] = expr };
                LogError($"IFDice: malformed expression '{expr}'");
                return new JObject { ["count"] = 1, ["sides"] = 1, ["modifier"] = modifier, ["expr"] = expr };
            }
            string[] halves = body.Split('d');
            if (halves.Length != 2)
            {
                LogError($"IFDice: malformed dice body '{body}'");
                return new JObject { ["count"] = 1, ["sides"] = 1, ["modifier"] = modifier, ["expr"] = expr };
            }
            int count = halves[0] == "" ? 1 : ToInt(halves[0]);
            int sides = ToInt(halves[1]);
            if (count < 1 || sides < 1)
            {
                LogError($"IFDice: non-positive dice in '{expr}'");
                count = System.Math.Max(count, 1);
                sides = System.Math.Max(sides, 1);
            }
            return new JObject { ["count"] = count, ["sides"] = sides, ["modifier"] = modifier, ["expr"] = expr };
        }

        /// <summary>
        /// Roll an expression. Returns:
        ///   { expr, count, sides, modifier, faces:[int...], sum:int, total:int }
        /// where `sum` is the raw dice sum and `total` = sum + modifier. `faces` is
        /// the ordered list of individual die results (criticals inspect it).
        /// </summary>
        public JObject Roll(string expr)
        {
            JObject p = Parse(expr);
            int count = (int)p["count"];
            int sides = (int)p["sides"];
            int modifier = (int)p["modifier"];
            var faces = new JArray();
            int sum = 0;
            for (int i = 0; i < count; i++)
            {
                int face = _rng.RangeInclusive(1, sides);
                faces.Add(face);
                sum += face;
            }
            int total = sum + modifier;
            return new JObject
            {
                ["expr"] = expr,
                ["count"] = count,
                ["sides"] = sides,
                ["modifier"] = modifier,
                ["faces"] = faces,
                ["sum"] = sum,
                ["total"] = total,
            };
        }

        // --- Godot String semantics helpers ------------------------------------

        /// <summary>Mirrors Godot String.is_valid_int(): optional leading +/- then digits.</summary>
        private static bool IsValidInt(string s)
        {
            if (string.IsNullOrEmpty(s))
                return false;
            int i = 0;
            if (s[0] == '+' || s[0] == '-')
                i = 1;
            if (i >= s.Length)
                return false;
            for (; i < s.Length; i++)
            {
                if (s[i] < '0' || s[i] > '9')
                    return false;
            }
            return true;
        }

        /// <summary>
        /// Mirrors Godot String.to_int(): parse an optional leading sign then
        /// consecutive digits, stopping at the first non-digit; 0 when no digits.
        /// </summary>
        private static int ToInt(string s)
        {
            if (string.IsNullOrEmpty(s))
                return 0;
            int i = 0;
            int sign = 1;
            if (s[0] == '+' || s[0] == '-')
            {
                if (s[0] == '-')
                    sign = -1;
                i = 1;
            }
            long value = 0;
            bool any = false;
            for (; i < s.Length; i++)
            {
                char c = s[i];
                if (c < '0' || c > '9')
                    break;
                any = true;
                value = value * 10 + (c - '0');
            }
            if (!any)
                return 0;
            return (int)(sign * value);
        }

        private static void LogError(string msg) => UnityEngine.Debug.LogError(msg);
    }
}
