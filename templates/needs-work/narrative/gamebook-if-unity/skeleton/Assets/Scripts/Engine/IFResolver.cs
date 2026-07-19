// Assets/Scripts/Engine/IFResolver.cs
// Unity C# port of res://addons/nox_if_engine/if_resolver.gd
//
// THE generic rule engine (spec §2.5). A resolution rule is DATA; this
// interpreter turns any such rule into an outcome. It is what lets ONE engine
// express every resolution family — the `compare` mode + `bands` are the knobs:
//
//   * roll-under  (FF 2d6)  : total <= target  -> success / failure
//   * meet-or-beat (d20+mod): total >= target  -> failure / success (+ crits)
//   * threshold-bands (PbtA): total mapped into numeric [min..max] bands
//
// A resolution rule (lives in a ruleset's `resolutionRules[]`):
//   {
//     id, label,
//     dice: "2d6",                       # overridable per call via args.dice
//     operands: [                        # each contributes a target or a modifier
//        { type, ref?, value?, role, transform? }
//     ],
//     compare: "roll-under"|"meet-or-beat"|"threshold-bands",
//     crit:    { mode, ... }?            # optional critical override
//     bands:   [ { id, when|min|max, label } ],   # labelled OUTCOMES (system-level)
//     postEffects: [ <effect> ]?         # applied to state after every resolution
//                                        #   (e.g. FF LUCK attrition)
//   }
//
// Operand types (the abstraction that unifies the families):
//   attribute     -> state.GetAttr(ref)                  (SKILL)
//   attributeArg  -> state.GetAttr(args[ref])            ($attr picked at call site)
//   resource      -> state.GetResource(ref)
//   var           -> state.GetVar(ref)
//   param         -> Dbl(args[ref] ?? default)           (a DC supplied by the scene)
//   const         -> value
// Operand role:  "target" (compared against) | "modifier" (added to the total).
// Operand transform: "none" | "abilityMod" (floor((v-10)/2)) | "negate".
//
// Bands are SYSTEM-level labelled outcomes ("success"/"failure"/"partial"...).
// What each outcome DOES in a given story (route + effects) is CONTENT and lives
// on the scenario's check node — see IFRunner.cs. This keeps rulesets pure and
// reusable across every scenario.

using System;
using System.Collections.Generic;
using Newtonsoft.Json.Linq;

namespace NoxIfEngine
{
    public sealed class IFResolver
    {
        private readonly IFRuleset _ruleset;
        private readonly IFDice _dice;

        public IFResolver(IFRuleset rs, IFDice d)
        {
            _ruleset = rs;
            _dice = d;
        }

        /// <summary>
        /// Resolve <paramref name="rule"/> against <paramref name="state"/>, with optional
        /// <paramref name="args"/> from the scenario's check node (e.g. {attr:"SKILL"} or
        /// {dc:14}). Records the result into state.RollLog and applies the rule's postEffects.
        /// Returns the full result dict:
        ///   { rule, label, dice, faces, sum, modifier, target_delta, roll_modifier,
        ///     total, target, compare, success (bool|null), crit ("" | "success" | "fail"),
        ///     band, band_label }
        /// Two reserved args are the portability difficulty seam (see IFPortableCheck):
        ///   _targetDelta  (float, default 0) — added to the compared-against target.
        ///   _rollModifier (float, default 0) — added to the total before banding.
        /// Absent in native P0/P1 checks, so those resolve unchanged.
        /// </summary>
        public JObject Resolve(JObject rule, IFState state, JObject args = null)
        {
            JToken diceTok = GetOr(args, "dice", GetOr(rule, "dice", (JToken)_ruleset.DiceDefault));
            string expr = Str(diceTok);
            JObject roll = _dice.Roll(expr);

            double? target = null;
            double modifier = 0.0;
            if (rule["operands"] is JArray operands)
            {
                foreach (var opTok in operands)
                {
                    var op = (JObject)opTok;
                    double v = OperandValue(op, state, args);
                    string role = Str(GetOr(op, "role", (JToken)"target"));
                    if (role == "modifier")
                        modifier += v;
                    else
                        target = v;
                }
            }

            // Portability difficulty seams (P2). Both default to 0, so a native P0/P1 check
            // (no `_targetDelta`/`_rollModifier` args) resolves byte-for-byte as before.
            // IFPortableCheck compiles a canonical difficulty into exactly ONE of these:
            //   * _targetDelta   -> shifts the compared-against target (FF roll-under: a
            //                       harder test lowers the effective attribute to roll under).
            //   * _rollModifier  -> shifts the total (PbtA-style forward/ongoing: a harder
            //                       move subtracts from 2d6+stat before the bands are read).
            // A d20-style system needs neither — its difficulty IS the DC (a `param` target).
            double targetDelta = Dbl(GetOr(args, "_targetDelta", (JToken)0.0));
            double rollModifier = Dbl(GetOr(args, "_rollModifier", (JToken)0.0));
            if (target != null)
                target = target.Value + targetDelta;

            double total = Dbl(roll["total"]) + modifier + rollModifier;
            string compare = Str(GetOr(rule, "compare", (JToken)"meet-or-beat"));

            // Critical override (evaluated on the raw faces, before/over the arithmetic).
            string crit = EvalCrit(rule["crit"] as JObject, roll);

            bool? success = null;
            switch (compare)
            {
                case "roll-under":
                    success = target != null && total <= target.Value;
                    break;
                case "meet-or-beat":
                    success = target != null && total >= target.Value;
                    break;
                case "threshold-bands":
                    success = null; // bands carry the outcome, not a binary
                    break;
                default:
                    UnityEngine.Debug.LogError($"IFResolver: unknown compare mode '{compare}'");
                    success = false;
                    break;
            }

            // Criticals force the binary outcome (a nat-20 hits, double-6 fumbles).
            if (crit == "success")
                success = true;
            else if (crit == "fail")
                success = false;

            JObject band = PickBand(rule["bands"] as JArray, success, crit, total);

            var result = new JObject
            {
                ["rule"] = Str(GetOr(rule, "id", (JToken)"")),
                ["label"] = Str(GetOr(rule, "label", GetOr(rule, "id", (JToken)""))),
                ["dice"] = expr,
                ["faces"] = roll["faces"] != null ? roll["faces"].DeepClone() : new JArray(),
                ["sum"] = roll["sum"] != null ? roll["sum"].DeepClone() : (JToken)0,
                ["modifier"] = modifier,
                ["target_delta"] = targetDelta,
                ["roll_modifier"] = rollModifier,
                ["total"] = total,
                ["target"] = target.HasValue ? (JToken)new JValue(target.Value) : JValue.CreateNull(),
                ["compare"] = compare,
                ["success"] = success.HasValue ? (JToken)new JValue(success.Value) : JValue.CreateNull(),
                ["crit"] = crit,
                ["band"] = Str(GetOr(band, "id", (JToken)"")),
                ["band_label"] = Str(GetOr(band, "label", GetOr(band, "id", (JToken)""))),
            };

            state.RecordRoll(result);
            // Rule-level side effects (any outcome) — FF "testing your luck erodes it".
            state.ApplyEffects(rule["postEffects"]);
            return result;
        }

        private double OperandValue(JObject op, IFState state, JObject args)
        {
            double v = 0.0;
            string type = Str(GetOr(op, "type", (JToken)"const"));
            switch (type)
            {
                case "attribute":
                    v = state.GetAttr(Str(GetOr(op, "ref", (JToken)"")));
                    break;
                case "attributeArg":
                    v = state.GetAttr(Str(GetOr(args, Str(GetOr(op, "ref", (JToken)"")), (JToken)"")));
                    break;
                case "resource":
                    v = state.GetResource(Str(GetOr(op, "ref", (JToken)"")));
                    break;
                case "var":
                    v = state.GetVar(Str(GetOr(op, "ref", (JToken)"")));
                    break;
                case "param":
                    v = Dbl(GetOr(args, Str(GetOr(op, "ref", (JToken)"")), GetOr(op, "default", (JToken)0)));
                    break;
                case "const":
                    v = Dbl(GetOr(op, "value", (JToken)0));
                    break;
                default:
                    UnityEngine.Debug.LogWarning($"IFResolver: unknown operand type '{type}'");
                    break;
            }
            return Transform(Str(GetOr(op, "transform", (JToken)"none")), v);
        }

        private double Transform(string kind, double v)
        {
            switch (kind)
            {
                case "none":
                    return v;
                case "abilityMod":
                    // D&D-style ability modifier: floor((score - 10) / 2).
                    return Math.Floor((v - 10.0) / 2.0);
                case "negate":
                    return -v;
                default:
                    UnityEngine.Debug.LogWarning($"IFResolver: unknown transform '{kind}'");
                    return v;
            }
        }

        /// <summary>
        /// Critical rules, as data. Returns "" | "success" | "fail".
        ///   { mode: "none" }
        ///   { mode: "natural", low: "fail",    high: "success" }   # d20 nat1/nat20
        ///   { mode: "doubles", lowValue: 1, lowResult: "success",  # FF double-1 always
        ///                      highValue: 6, highResult: "fail" }   #    double-6 always
        /// </summary>
        private string EvalCrit(JObject crit, JObject roll)
        {
            if (crit == null || crit.Count == 0)
                return "";
            var faces = roll["faces"] as JArray;
            string mode = Str(GetOr(crit, "mode", (JToken)"none"));
            switch (mode)
            {
                case "none":
                    return "";
                case "natural":
                    // Single-die naturals (uses the first/only die).
                    if (faces == null || faces.Count == 0)
                        return "";
                    int f = (int)faces[0];
                    if (f == 1 && crit.ContainsKey("low"))
                        return Str(crit["low"]);
                    if (f == (int)roll["sides"] && crit.ContainsKey("high"))
                        return Str(crit["high"]);
                    return "";
                case "doubles":
                    if (faces == null || faces.Count < 2)
                        return "";
                    bool allSame = true;
                    for (int i = 1; i < faces.Count; i++)
                    {
                        if ((int)faces[i] != (int)faces[0])
                        {
                            allSame = false;
                            break;
                        }
                    }
                    if (!allSame)
                        return "";
                    int val = (int)faces[0];
                    if (crit.ContainsKey("lowValue") && val == (int)crit["lowValue"])
                        return Str(GetOr(crit, "lowResult", (JToken)""));
                    if (crit.ContainsKey("highValue") && val == (int)crit["highValue"])
                        return Str(GetOr(crit, "highResult", (JToken)""));
                    return "";
                default:
                    UnityEngine.Debug.LogWarning($"IFResolver: unknown crit mode '{mode}'");
                    return "";
            }
        }

        /// <summary>
        /// Choose the outcome band. Threshold bands (any band with min/max) map the
        /// total into a numeric range; otherwise binary bands match on `when` with crits
        /// preferred over their plain counterparts.
        /// </summary>
        private JObject PickBand(JArray bands, bool? success, string crit, double total)
        {
            if (bands == null || bands.Count == 0)
                return new JObject { ["id"] = "", ["label"] = "" };

            bool isRange = false;
            foreach (var bTok in bands)
            {
                var b = (JObject)bTok;
                if (b.ContainsKey("min") || b.ContainsKey("max"))
                {
                    isRange = true;
                    break;
                }
            }

            if (isRange)
            {
                foreach (var bTok in bands)
                {
                    var b = (JObject)bTok;
                    double lo = b.ContainsKey("min") ? Dbl(b["min"]) : double.NegativeInfinity;
                    double hi = b.ContainsKey("max") ? Dbl(b["max"]) : double.PositiveInfinity;
                    if (total >= lo && total <= hi)
                        return b;
                }
                return (JObject)bands[bands.Count - 1];
            }

            // Binary bands, most-specific outcome first.
            List<string> wants;
            if (crit == "success")
                wants = new List<string> { "critSuccess", "success" };
            else if (crit == "fail")
                wants = new List<string> { "critFail", "fail" };
            else if (success == true)
                wants = new List<string> { "success" };
            else
                wants = new List<string> { "fail" };

            foreach (var w in wants)
            {
                foreach (var bTok in bands)
                {
                    var b = (JObject)bTok;
                    if (Str(GetOr(b, "when", (JToken)"")) == w)
                        return b;
                }
            }
            return (JObject)bands[0];
        }

        // --- helpers ------------------------------------------------------------

        /// <summary>Mirrors GDScript Dictionary.get(key, default): value if present, else default.</summary>
        private static JToken GetOr(JObject o, string key, JToken dflt)
            => (o != null && o.TryGetValue(key, out var v)) ? v : dflt;

        /// <summary>Mirrors GDScript str(): "" for null/JSON-null, else the token's string value.</summary>
        private static string Str(JToken t)
        {
            if (t == null || t.Type == JTokenType.Null)
                return "";
            return t.ToString();
        }

        /// <summary>Mirrors GDScript float(): numeric coercion of any token, 0 for null/unparsable.</summary>
        private static double Dbl(JToken t)
        {
            if (t == null || t.Type == JTokenType.Null)
                return 0.0;
            if (t.Type == JTokenType.Boolean)
                return (bool)t ? 1.0 : 0.0;
            if (t.Type == JTokenType.String)
                return double.TryParse((string)t, out var d) ? d : 0.0;
            try { return (double)t; }
            catch { return 0.0; }
        }
    }
}
