// Assets/Scripts/Engine/IFState.cs
// Unity C# port of nox_if_engine/if_state.gd (faithful, no simplification).
//
// Short-term runtime state — the deterministic, save-able heart of a play
// session. It EXTENDS three NoxDev conventions into one object:
//
//   * ff-gamebook SessionState: passage flow + history + roll_log, and the
//     "persistent" SaveData()/LoadData() contract.
//   * ff-gamebook Sheet: the adventure sheet — here it is system-defined
//     (attributes + resources come from the IFRuleset).
//   * VN runtime-variables/inventory: numeric `Vars`, `Flags`, and INVENTORY AS
//     VARIABLES under the `item.` prefix — `give a key` = `item.key += 1`,
//     `needs a key` = `item.key >= 1`. Same op/cmp vocabulary
//     (set/add · >=,<=,==,!=,>,<) so the ink authoring path and the node-graph
//     authoring path compile to exactly this model.
//
// This object holds NO randomness and NO rules; it is pure data + typed
// accessors. The Runner drives it, the Resolver reads/writes it, conditions and
// effects are interpreted against it (see EvalCondition / ApplyEffect).

using System;
using System.Collections.Generic;
using Newtonsoft.Json.Linq;

namespace NoxIfEngine
{
    public sealed class IFState
    {
        public const string ItemPrefix = "item.";

        /// <summary>The ruleset defines attribute/resource bounds; kept for clamping.</summary>
        public IFRuleset Ruleset;

        // Sheet: system attributes (SKILL/LUCK/STAMINA...) and depletable resources.
        public Dictionary<string, double> Attributes = new Dictionary<string, double>();
        public Dictionary<string, double> Resources = new Dictionary<string, double>();
        public Dictionary<string, double> ResourceMax = new Dictionary<string, double>();

        // VN-style short-term state.
        public Dictionary<string, double> Vars = new Dictionary<string, double>();   // numeric vars, incl. item.* inventory
        public Dictionary<string, JToken> Flags = new Dictionary<string, JToken>();  // named flags (any value)

        // SessionState-style flow.
        public string CurrentPassage = "";
        public List<string> PassageHistory = new List<string>();
        public List<JObject> RollLog = new List<JObject>();
        /// <summary>The most recent resolution result (for `checkResult` conditions and bands).</summary>
        public JObject LastCheck = new JObject();
        /// <summary>Terminal state (set when an ending passage is entered).</summary>
        public bool Ended = false;
        public JObject Ending = new JObject();

        public IFState(IFRuleset rs = null)
        {
            Ruleset = rs;
        }

        // --- Sheet initialization -------------------------------------------

        /// <summary>
        /// Seed the sheet from a GenerateSheet() result or a fixed override object of the
        /// same shape ({attributes, resources, resource_max?}).
        /// </summary>
        public void InitSheet(JObject sheet)
        {
            Attributes = ToDoubleDict(sheet?["attributes"]);
            Resources = ToDoubleDict(sheet?["resources"]);
            ResourceMax = ToDoubleDict(sheet?["resource_max"]);
            // Any trackMax resource with no explicit max mirrors its starting value.
            if (Ruleset != null)
            {
                foreach (string key in new List<string>(Resources.Keys))
                {
                    JObject rd = Ruleset.ResourceDef(key);
                    if (ToBool(rd["trackMax"], false) && !ResourceMax.ContainsKey(key))
                        ResourceMax[key] = Resources[key];
                }
            }
        }

        // --- Attributes -----------------------------------------------------

        public double GetAttr(string key)
        {
            if (!Attributes.ContainsKey(key))
            {
                UnityEngine.Debug.LogWarning($"IFState: unknown attribute '{key}'");
                return 0.0;
            }
            return Attributes[key];
        }

        public void SetAttr(string key, double value)
        {
            Attributes[key] = ClampAttr(key, value);
        }

        public void AddAttr(string key, double delta)
        {
            SetAttr(key, GetAttr(key) + delta);
        }

        private double ClampAttr(string key, double value)
        {
            if (Ruleset != null && Ruleset.HasAttribute(key))
            {
                JObject b = Ruleset.AttributeBounds(key);
                value = Math.Max(value, ToDouble(b["min"], double.NegativeInfinity));
                value = Math.Min(value, ToDouble(b["max"], double.PositiveInfinity));
            }
            return value;
        }

        // --- Resources ------------------------------------------------------

        public double GetResource(string key)
        {
            return Resources.TryGetValue(key, out double v) ? v : 0.0;
        }

        public void SetResource(string key, double value)
        {
            Resources[key] = ClampResource(key, value);
        }

        public void AddResource(string key, double delta)
        {
            SetResource(key, GetResource(key) + delta);
        }

        private double ClampResource(string key, double value)
        {
            double lo = 0.0;
            double hi = double.PositiveInfinity;
            if (Ruleset != null)
            {
                JObject rd = Ruleset.ResourceDef(key);
                if (rd["min"] != null)
                    lo = ToDouble(rd["min"], lo);
                if (rd["max"] != null)
                    hi = ToDouble(rd["max"], hi);
            }
            if (ResourceMax.TryGetValue(key, out double rmax))
                hi = Math.Min(hi, rmax);
            return Clampf(value, lo, hi);
        }

        // --- Variables (VN convention) --------------------------------------

        public double GetVar(string key)
        {
            return Vars.TryGetValue(key, out double v) ? v : 0.0;
        }

        public void SetVar(string key, double value)
        {
            Vars[key] = value;
        }

        public void AddVar(string key, double delta)
        {
            Vars[key] = GetVar(key) + delta;
        }

        // --- Inventory = vars under item.* (VN convention) ------------------

        public int GetItem(string key)
        {
            return (int)GetVar(ItemPrefix + key);
        }

        public bool HasItem(string key)
        {
            return GetItem(key) >= 1;
        }

        public void GrantItem(string key, int count = 1)
        {
            AddVar(ItemPrefix + key, count);
        }

        public bool ConsumeItem(string key, int count = 1)
        {
            int have = GetItem(key);
            if (have < count)
                return false;
            SetVar(ItemPrefix + key, have - count);
            return true;
        }

        /// <summary>Inventory as a {name: count} map (item.* vars with count &gt; 0) for the UI/save.</summary>
        public JObject Inventory()
        {
            JObject inv = new JObject();
            foreach (KeyValuePair<string, double> kv in Vars)
            {
                string key = kv.Key;
                if (key.StartsWith(ItemPrefix, StringComparison.Ordinal))
                {
                    int count = (int)kv.Value;
                    if (count > 0)
                        inv[key.Substring(ItemPrefix.Length)] = count;
                }
            }
            return inv;
        }

        // --- Flags ----------------------------------------------------------

        public JToken GetFlag(string key, JToken def = null)
        {
            if (def == null)
                def = new JValue(false);
            return Flags.TryGetValue(key, out JToken v) ? v : def;
        }

        public void SetFlag(string key, JToken value = null)
        {
            Flags[key] = value ?? (JToken)new JValue(true);
        }

        public void ClearFlag(string key)
        {
            Flags.Remove(key);
        }

        // --- Passage flow (SessionState role) -------------------------------

        public void EnterPassage(string passageId)
        {
            CurrentPassage = passageId;
            PassageHistory.Add(passageId);
        }

        public void RecordRoll(JObject result)
        {
            LastCheck = result;
            RollLog.Add(result);
        }

        public void MarkEnding(JObject endingDef)
        {
            Ended = true;
            Ending = endingDef;
        }

        // --- Condition interpreter ------------------------------------------
        // Shared vocabulary with the VN var-conditions + item.* + flags + attrs.
        // A condition list is ANDed; `any`/`all` nest for OR/grouping. A bare
        // condition object is treated as a single-element (ANDed) list.

        public bool ConditionsMet(JToken conds)
        {
            if (conds == null || conds.Type == JTokenType.Null)
                return true;
            if (conds is JArray arr)
            {
                foreach (JToken c in arr)
                {
                    if (!EvalCondition(c as JObject))
                        return false;
                }
                return true;
            }
            if (conds is JObject obj)
                return EvalCondition(obj);
            return true;
        }

        public bool EvalCondition(JObject cond)
        {
            if (cond == null)
                cond = new JObject();
            string kind = StrOf(cond["kind"], "var");
            switch (kind)
            {
                case "always":
                    return true;
                case "any":
                    foreach (JToken c in AsArray(cond["of"]))
                    {
                        if (EvalCondition(c as JObject))
                            return true;
                    }
                    return false;
                case "all":
                    foreach (JToken c in AsArray(cond["of"]))
                    {
                        if (!EvalCondition(c as JObject))
                            return false;
                    }
                    return true;
                case "not":
                    return !EvalCondition(cond["of"] as JObject ?? new JObject());
                case "var":
                    return Cmp(GetVar(StrOf(cond["key"], "")), cond);
                case "attr":
                    return Cmp(GetAttr(StrOf(cond["key"], "")), cond);
                case "resource":
                    return Cmp(GetResource(StrOf(cond["key"], "")), cond);
                case "item":
                {
                    // Default: presence (item.key >= 1).
                    double have = GetItem(StrOf(cond["key"], ""));
                    if (cond["cmp"] == null && cond["value"] == null)
                        return have >= 1.0;
                    return Cmp(have, cond, 1.0);
                }
                case "flag":
                {
                    JToken want = cond["value"] ?? new JValue(true);
                    JToken cur = GetFlag(StrOf(cond["key"], ""), new JValue(false));
                    return VariantEquals(cur, want);
                }
                case "checkResult":
                {
                    string band = StrOf(LastCheck["band"], "");
                    JToken target = cond["value"] ?? new JValue("");
                    if (target.Type == JTokenType.Array)
                    {
                        foreach (JToken t in (JArray)target)
                        {
                            if (StrOf(t, "") == band)
                                return true;
                        }
                        return false;
                    }
                    return band == StrOf(target, "");
                }
                default:
                    UnityEngine.Debug.LogWarning($"IFState: unknown condition kind '{kind}'");
                    return false;
            }
        }

        private bool Cmp(double lhs, JObject cond, double defaultValue = 0.0)
        {
            double rhs = ToDouble(cond["value"], defaultValue);
            string cmp = StrOf(cond["cmp"], ">=");
            switch (cmp)
            {
                case ">=": return lhs >= rhs;
                case "<=": return lhs <= rhs;
                case "==": return IsEqualApprox(lhs, rhs);
                case "!=": return !IsEqualApprox(lhs, rhs);
                case ">": return lhs > rhs;
                case "<": return lhs < rhs;
                default:
                    UnityEngine.Debug.LogWarning($"IFState: unknown cmp '{StrOf(cond["cmp"], "")}'");
                    return false;
            }
        }

        // --- Effect interpreter ---------------------------------------------
        // Shared with the narrative graph's choice effects AND resolution postEffects.
        // Returns a route (passage id) if the effect is a `goto`, else "".

        public string ApplyEffects(JToken effects)
        {
            string route = "";
            if (effects == null || effects.Type == JTokenType.Null)
                return route;
            if (effects is JArray arr)
            {
                foreach (JToken e in arr)
                {
                    string r = ApplyEffect(e as JObject);
                    if (r != "")
                        route = r;
                }
            }
            else if (effects is JObject obj)
            {
                string r = ApplyEffect(obj);
                if (r != "")
                    route = r;
            }
            return route;
        }

        public string ApplyEffect(JObject eff)
        {
            if (eff == null)
                eff = new JObject();
            string kind = StrOf(eff["kind"], "var");
            string key = StrOf(eff["key"], "");
            string op = StrOf(eff["op"], "add");
            double value = ToDouble(eff["value"], 0.0);
            switch (kind)
            {
                case "var":
                    if (op == "set")
                        SetVar(key, value);
                    else
                        AddVar(key, value);
                    break;
                case "item":
                    // op: grant (add) | consume (subtract, floored at 0)
                    if (op == "consume")
                        ConsumeItem(key, (int)(value != 0.0 ? value : 1.0));
                    else
                        GrantItem(key, (int)(value != 0.0 ? value : 1.0));
                    break;
                case "attr":
                    if (op == "set")
                        SetAttr(key, value);
                    else
                        AddAttr(key, value);
                    break;
                case "resource":
                    if (op == "set")
                        SetResource(key, value);
                    else
                        AddResource(key, value);
                    break;
                case "flag":
                    SetFlag(key, eff["value"] ?? new JValue(true));
                    break;
                case "goto":
                    return StrOf(eff["value"] ?? eff["target"], "");
                default:
                    UnityEngine.Debug.LogWarning($"IFState: unknown effect kind '{kind}'");
                    break;
            }
            return "";
        }

        // --- "persistent" save contract (SessionState/Sheet ABI) ------------

        public JObject SaveData()
        {
            return new JObject
            {
                ["attributes"] = DoubleDictToJObject(Attributes),
                ["resources"] = DoubleDictToJObject(Resources),
                ["resource_max"] = DoubleDictToJObject(ResourceMax),
                ["vars"] = DoubleDictToJObject(Vars),
                ["flags"] = FlagDictToJObject(Flags),
                ["current_passage"] = CurrentPassage,
                ["passage_history"] = new JArray(PassageHistory),
                ["roll_log"] = RollLogToJArray(RollLog),
                ["last_check"] = LastCheck != null ? LastCheck.DeepClone() : new JObject(),
                ["ended"] = Ended,
                ["ending"] = Ending != null ? Ending.DeepClone() : new JObject(),
            };
        }

        public void LoadData(JObject data)
        {
            if (data == null)
                data = new JObject();
            Attributes = ToDoubleDict(data["attributes"]);
            Resources = ToDoubleDict(data["resources"]);
            ResourceMax = ToDoubleDict(data["resource_max"]);
            Vars = ToDoubleDict(data["vars"]);
            Flags = ToFlagDict(data["flags"]);
            CurrentPassage = StrOf(data["current_passage"], "");
            PassageHistory = ToStringList(data["passage_history"]);
            RollLog = ToJObjectList(data["roll_log"]);
            LastCheck = data["last_check"] is JObject lc ? (JObject)lc.DeepClone() : new JObject();
            Ended = ToBool(data["ended"], false);
            Ending = data["ending"] is JObject en ? (JObject)en.DeepClone() : new JObject();
        }

        // --- Conversion / math helpers --------------------------------------

        private static JArray AsArray(JToken t) => t as JArray ?? new JArray();

        private static Dictionary<string, double> ToDoubleDict(JToken t)
        {
            Dictionary<string, double> d = new Dictionary<string, double>();
            if (t is JObject o)
            {
                foreach (JProperty p in o.Properties())
                    d[p.Name] = ToDouble(p.Value, 0.0);
            }
            return d;
        }

        private static Dictionary<string, JToken> ToFlagDict(JToken t)
        {
            Dictionary<string, JToken> d = new Dictionary<string, JToken>();
            if (t is JObject o)
            {
                foreach (JProperty p in o.Properties())
                    d[p.Name] = p.Value.DeepClone();
            }
            return d;
        }

        private static List<string> ToStringList(JToken t)
        {
            List<string> l = new List<string>();
            if (t is JArray a)
            {
                foreach (JToken x in a)
                    l.Add(StrOf(x, ""));
            }
            return l;
        }

        private static List<JObject> ToJObjectList(JToken t)
        {
            List<JObject> l = new List<JObject>();
            if (t is JArray a)
            {
                foreach (JToken x in a)
                {
                    if (x is JObject o)
                        l.Add((JObject)o.DeepClone());
                }
            }
            return l;
        }

        private static JObject DoubleDictToJObject(Dictionary<string, double> d)
        {
            JObject o = new JObject();
            foreach (KeyValuePair<string, double> kv in d)
                o[kv.Key] = kv.Value;
            return o;
        }

        private static JObject FlagDictToJObject(Dictionary<string, JToken> d)
        {
            JObject o = new JObject();
            foreach (KeyValuePair<string, JToken> kv in d)
                o[kv.Key] = kv.Value != null ? kv.Value.DeepClone() : JValue.CreateNull();
            return o;
        }

        private static JArray RollLogToJArray(List<JObject> log)
        {
            JArray a = new JArray();
            foreach (JObject entry in log)
                a.Add(entry != null ? entry.DeepClone() : new JObject());
            return a;
        }

        private static string StrOf(JToken t, string fallback = "")
        {
            if (t == null || t.Type == JTokenType.Null)
                return fallback;
            if (t.Type == JTokenType.String)
                return (string)t;
            return t.ToString();
        }

        private static double ToDouble(JToken t, double fallback = 0.0)
        {
            if (t == null)
                return fallback;
            switch (t.Type)
            {
                case JTokenType.Integer:
                case JTokenType.Float:
                    return (double)t;
                case JTokenType.Boolean:
                    return (bool)t ? 1.0 : 0.0;
                case JTokenType.String:
                    return double.TryParse((string)t, out double d) ? d : fallback;
                default:
                    return fallback;
            }
        }

        private static bool ToBool(JToken t, bool fallback = false)
        {
            if (t == null)
                return fallback;
            switch (t.Type)
            {
                case JTokenType.Boolean:
                    return (bool)t;
                case JTokenType.Integer:
                case JTokenType.Float:
                    return (double)t != 0.0;
                case JTokenType.String:
                    return ((string)t).Length != 0;
                case JTokenType.Null:
                    return fallback;
                default:
                    return fallback;
            }
        }

        // Godot Variant `==` semantics for flag comparison: numeric-ish operands
        // (int/float/bool) compare by numeric value (so `true == 1`), everything
        // else falls back to structural equality (string==string, etc.).
        private static bool VariantEquals(JToken a, JToken b)
        {
            if (a == null)
                a = JValue.CreateNull();
            if (b == null)
                b = JValue.CreateNull();
            if (IsNumberish(a) && IsNumberish(b))
                return NumOf(a) == NumOf(b);
            return JToken.DeepEquals(a, b);
        }

        private static bool IsNumberish(JToken t)
        {
            return t.Type == JTokenType.Integer
                || t.Type == JTokenType.Float
                || t.Type == JTokenType.Boolean;
        }

        private static double NumOf(JToken t)
        {
            if (t.Type == JTokenType.Boolean)
                return (bool)t ? 1.0 : 0.0;
            return (double)t;
        }

        // Godot clampf(value, lo, hi): value below lo -> lo, above hi -> hi.
        private static double Clampf(double v, double lo, double hi)
        {
            if (v < lo)
                return lo;
            if (v > hi)
                return hi;
            return v;
        }

        // Godot is_equal_approx: tolerance is CMP_EPSILON (1e-5) scaled by |a|,
        // floored at CMP_EPSILON.
        private static bool IsEqualApprox(double a, double b)
        {
            if (a == b)
                return true;
            double tolerance = 1e-05 * Math.Abs(a);
            if (tolerance < 1e-05)
                tolerance = 1e-05;
            return Math.Abs(a - b) < tolerance;
        }
    }
}
