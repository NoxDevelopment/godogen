// Assets/Scripts/Engine/IFRuleset.cs
// Unity C# port of nox_if_engine/if_ruleset.gd (faithful, no simplification).
//
// A ruleset is DATA, not code (spec §2.5). This class is the typed reader over
// one ruleset dict — it never hardcodes a system. Swapping the dict reskins ALL
// resolution: attributes, resources, the character-sheet template, the dice
// defaults and the resolution rules the interpreter walks.
//
// Shape (`ruleset.json`):
//   {
//     id, name,
//     meta:            { family, license, degreesOfSuccess:[...] , advancement? },
//     dice:            { default: "2d6" },
//     attributes:      [ { key, label, gen:"1d6+6", min, max } ],
//     resources:       [ { key, label, default, min, max?, from? , trackMax? } ],
//     sheetTemplate:   { attributes:[keys], resources:[keys], inventory:bool },
//     resolutionRules: [ <resolution rule>, ... ]     # see IFResolver
//   }
//
// `attributes` are the stats a check reads (SKILL/LUCK/STAMINA). `resources` are
// depletable pools (STAMINA hit-points, provisions, PbtA tokens). A resource may
// mirror an attribute's roll as its starting max via `from` (FF STAMINA is both a
// checkable attribute AND the hp pool).

using System.Collections.Generic;
using System.IO;
using Newtonsoft.Json.Linq;

namespace NoxIfEngine
{
    public sealed class IFRuleset
    {
        public string Id = "";
        public string Name = "";
        public JObject Meta = new JObject();
        public string DiceDefault = "1d6";

        /// <summary>key -> attribute def object.</summary>
        public Dictionary<string, JObject> Attributes = new Dictionary<string, JObject>();
        /// <summary>Ordered attribute keys (sheet display order).</summary>
        public List<string> AttributeOrder = new List<string>();

        /// <summary>key -> resource def object.</summary>
        public Dictionary<string, JObject> Resources = new Dictionary<string, JObject>();
        public List<string> ResourceOrder = new List<string>();

        public JObject SheetTemplate = new JObject();

        /// <summary>id -> resolution rule object.</summary>
        public Dictionary<string, JObject> Rules = new Dictionary<string, JObject>();

        // The PORTABILITY block (spec §2.5, P2) — how this system maps the engine's
        // canonical, ruleset-agnostic check vocabulary (a SEMANTIC + a canonical
        // attribute + a canonical difficulty + canonical outcome bands) onto its OWN
        // resolution rules. This is what lets ONE scenario run under every system.
        //   portability: {
        //     attributeMap: { <canonicalAttr>: "<nativeAttrKey>", ... },
        //     outcomeMap:   { <nativeBandId>: "<canonicalBand>", ... },
        //     semantics: {
        //       "<semanticId>": {
        //         rule: "<resolutionRuleId>",
        //         attrArg: "<argName the rule reads the mapped native attribute from>",
        //         difficulty: {
        //           mode: "dc"|"targetDelta"|"rollModifier",
        //           arg?: "<argName>",
        //           ladder: { <canonicalDifficulty>: <number>, ... }
        //         },
        //         args?: { <extra static args merged into the call> }
        //       }, ...
        //     }
        //   }
        // Empty for a system that opts out of portability (native checks still run).
        public JObject Portability = new JObject();

        private JObject _raw = new JObject();

        public IFRuleset(JObject data = null)
        {
            if (data != null && data.Count > 0)
                LoadFrom(data);
        }

        /// <summary>Load a resource path (ff-2d6.json) into a ruleset.</summary>
        public static IFRuleset FromFile(string path)
        {
            string text;
            try
            {
                text = File.ReadAllText(path);
            }
            catch
            {
                UnityEngine.Debug.LogError($"IFRuleset: could not read '{path}'");
                return new IFRuleset();
            }
            if (string.IsNullOrEmpty(text))
            {
                UnityEngine.Debug.LogError($"IFRuleset: could not read '{path}'");
                return new IFRuleset();
            }
            JToken parsed;
            try
            {
                parsed = JToken.Parse(text);
            }
            catch
            {
                UnityEngine.Debug.LogError($"IFRuleset: '{path}' is not a JSON object");
                return new IFRuleset();
            }
            if (!(parsed is JObject obj))
            {
                UnityEngine.Debug.LogError($"IFRuleset: '{path}' is not a JSON object");
                return new IFRuleset();
            }
            return new IFRuleset(obj);
        }

        public void LoadFrom(JObject data)
        {
            _raw = data;
            Id = StrOf(data["id"], "");
            Name = StrOf(data["name"], Id);
            Meta = data["meta"] as JObject ?? new JObject();
            JObject diceObj = data["dice"] as JObject;
            DiceDefault = StrOf(diceObj?["default"], "1d6");

            Attributes.Clear();
            AttributeOrder.Clear();
            foreach (JToken item in AsArray(data["attributes"]))
            {
                JObject a = item as JObject;
                if (a == null)
                    continue;
                string key = StrOf(a["key"], "");
                if (key == "")
                    continue;
                Attributes[key] = a;
                AttributeOrder.Add(key);
            }

            Resources.Clear();
            ResourceOrder.Clear();
            foreach (JToken item in AsArray(data["resources"]))
            {
                JObject r = item as JObject;
                if (r == null)
                    continue;
                string key = StrOf(r["key"], "");
                if (key == "")
                    continue;
                Resources[key] = r;
                ResourceOrder.Add(key);
            }

            if (data["sheetTemplate"] is JObject st)
            {
                SheetTemplate = st;
            }
            else
            {
                SheetTemplate = new JObject
                {
                    ["attributes"] = new JArray(AttributeOrder),
                    ["resources"] = new JArray(ResourceOrder),
                    ["inventory"] = true,
                };
            }

            Rules.Clear();
            foreach (JToken item in AsArray(data["resolutionRules"]))
            {
                JObject rule = item as JObject;
                if (rule == null)
                    continue;
                string rid = StrOf(rule["id"], "");
                if (rid == "")
                    continue;
                Rules[rid] = rule;
            }

            Portability = data["portability"] as JObject ?? new JObject();
        }

        public bool HasAttribute(string key) => Attributes.ContainsKey(key);

        public JObject AttributeBounds(string key)
        {
            Attributes.TryGetValue(key, out JObject a);
            JToken min = a?["min"];
            JToken max = a?["max"];
            return new JObject
            {
                ["min"] = min != null ? min.DeepClone() : new JValue(double.NegativeInfinity),
                ["max"] = max != null ? max.DeepClone() : new JValue(double.PositiveInfinity),
            };
        }

        public bool HasResource(string key) => Resources.ContainsKey(key);

        public JObject ResourceDef(string key)
        {
            Resources.TryGetValue(key, out JObject r);
            return r ?? new JObject();
        }

        public JObject Rule(string ruleId)
        {
            if (!Rules.TryGetValue(ruleId, out JObject r))
            {
                UnityEngine.Debug.LogError($"IFRuleset '{Id}': no resolution rule '{ruleId}'");
                return new JObject();
            }
            return r;
        }

        // --- Portability accessors (P2) -------------------------------------

        /// <summary>
        /// Does this system declare a mapping for the given canonical SEMANTIC (e.g.
        /// "skill-test")? If false, a portable check cannot be compiled for this ruleset.
        /// </summary>
        public bool HasSemantic(string semanticId)
        {
            JObject sems = Portability["semantics"] as JObject;
            return sems != null && sems[semanticId] != null;
        }

        /// <summary>
        /// The semantic mapping object ({rule, attrArg, difficulty, args?}). Returns {}
        /// when unmapped.
        /// </summary>
        public JObject SemanticDef(string semanticId)
        {
            JObject sems = Portability["semantics"] as JObject;
            return sems?[semanticId] as JObject ?? new JObject();
        }

        /// <summary>
        /// Map a canonical attribute (prowess/wits/...) to this system's native attribute
        /// key (SKILL / STR / cool / ...). Returns "" when the canonical attr is unmapped.
        /// </summary>
        public string NativeAttributeFor(string canonicalAttr)
        {
            JObject map = Portability["attributeMap"] as JObject;
            return StrOf(map?[canonicalAttr], "");
        }

        /// <summary>
        /// Map a native band id this system produces (success/miss/full/...) to a canonical
        /// outcome band. Falls back to the native id unchanged when unmapped.
        /// </summary>
        public string CanonicalBandFor(string nativeBand)
        {
            JObject map = Portability["outcomeMap"] as JObject;
            return StrOf(map?[nativeBand], nativeBand);
        }

        /// <summary>
        /// Roll a fresh sheet from the attribute `gen` expressions + resource defaults. The
        /// returned object feeds IFState.InitSheet(). A resource with `from: &lt;attr&gt;`
        /// takes that attribute's rolled value as its starting value/max (FF STAMINA).
        /// </summary>
        public JObject GenerateSheet(IFDice dice)
        {
            JObject attrValues = new JObject();
            foreach (string key in AttributeOrder)
            {
                JObject a = Attributes[key];
                string gen = StrOf(a["gen"], "");
                double value;
                if (gen == "")
                    value = ToDouble(a["default"], 0.0);
                else
                    value = ToDouble(dice.Roll(gen)["total"], 0.0);
                value = ClampAttr(a, value);
                attrValues[key] = value;
            }

            JObject resValues = new JObject();
            JObject resMax = new JObject();
            foreach (string key in ResourceOrder)
            {
                JObject r = Resources[key];
                double value;
                JToken fromTok = r["from"];
                string fromKey = fromTok != null ? StrOf(fromTok, "") : "";
                if (fromTok != null && attrValues[fromKey] != null)
                    value = ToDouble(attrValues[fromKey], 0.0);
                else
                    value = ToDouble(r["default"], 0.0);
                resValues[key] = value;
                if (ToBool(r["trackMax"], false))
                    resMax[key] = value;
            }

            return new JObject
            {
                ["attributes"] = attrValues,
                ["resources"] = resValues,
                ["resource_max"] = resMax,
            };
        }

        private static double ClampAttr(JObject a, double value)
        {
            if (a["min"] != null)
                value = System.Math.Max(value, ToDouble(a["min"], double.NegativeInfinity));
            if (a["max"] != null)
                value = System.Math.Min(value, ToDouble(a["max"], double.PositiveInfinity));
            return value;
        }

        public JObject Raw() => _raw;

        // --- Conversion helpers (faithful GDScript str()/float()/bool()) ----

        private static JArray AsArray(JToken t) => t as JArray ?? new JArray();

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
    }
}
