// Assets/Scripts/Engine/IFScenario.cs
// Unity C# port of res://addons/nox_if_engine/if_scenario.gd (faithful, 1:1).
//
// The shared narrative-graph data model — the ONE model both authoring views
// (ink text via the Writers Room, and the visual passage/choice graph) compile
// to and from. It is pure content: passages, choices, conditions, effects. It
// names a ruleset but contains no resolution logic itself.
//
// Shape (module.json / scenario):
//   {
//     id, name, meta:{...},
//     ruleset: "ff-2d6",              # which system resolves this scenario
//     start:   "<passage id>",
//     sheet:   {attributes:{...}, resources:{...}} | null,   # fixed sheet, or
//                                     # null => generate from the ruleset
//     init:    { vars:{...}, items:{name:count}, flags:{...} },
//     passages: [ <passage> ]
//   }
//
// Check nodes come in TWO shapes (see IFPortableCheck): NATIVE (names a ruleset
// rule id + native attributes/bands) and PORTABLE (names a canonical semantic +
// canonical attribute/difficulty/bands, runs under every system). Validation
// mirrors both.
using System.Collections.Generic;
using System.IO;
using Newtonsoft.Json.Linq;

namespace NoxIfEngine
{
    public sealed class IFScenario
    {
        public string Id = "";
        public string Name = "";
        public JObject Meta = new JObject();
        public string RulesetId = "";
        public string Start = "";
        public JToken SheetOverride = null;      // Dictionary or null
        public JObject InitVars = new JObject();
        public JObject InitItems = new JObject();
        public JObject InitFlags = new JObject();

        /// <summary>id -> passage dict.</summary>
        public Dictionary<string, JObject> Passages = new Dictionary<string, JObject>();

        private JObject _raw = new JObject();

        public IFScenario(JObject data = null)
        {
            if (data != null && data.Count > 0)
                LoadFrom(data);
        }

        public static IFScenario FromFile(string path)
        {
            string text;
            try
            {
                text = File.ReadAllText(path);
            }
            catch
            {
                text = "";
            }
            if (string.IsNullOrEmpty(text))
            {
                LogError($"IFScenario: could not read '{path}'");
                return new IFScenario();
            }
            JToken parsed;
            try
            {
                parsed = JToken.Parse(text);
            }
            catch
            {
                parsed = null;
            }
            if (!(parsed is JObject obj))
            {
                LogError($"IFScenario: '{path}' is not a JSON object");
                return new IFScenario();
            }
            return new IFScenario(obj);
        }

        public void LoadFrom(JObject data)
        {
            _raw = data;
            Id = Str(data["id"]);
            JToken nameTok = data["name"];
            Name = (nameTok != null && nameTok.Type != JTokenType.Null) ? Str(nameTok) : Id;
            Meta = data["meta"] as JObject ?? new JObject();
            RulesetId = Str(data["ruleset"]);
            Start = Str(data["start"]);
            JToken sheetTok = data["sheet"];
            SheetOverride = (sheetTok == null || sheetTok.Type == JTokenType.Null) ? null : sheetTok;
            JObject init = data["init"] as JObject ?? new JObject();
            InitVars = init["vars"] as JObject ?? new JObject();
            InitItems = init["items"] as JObject ?? new JObject();
            InitFlags = init["flags"] as JObject ?? new JObject();

            Passages.Clear();
            JArray passageList = data["passages"] as JArray;
            if (passageList != null)
            {
                foreach (JToken pt in passageList)
                {
                    JObject p = pt as JObject;
                    string pid = p != null ? Str(p["id"]) : "";
                    if (pid == "")
                    {
                        LogWarning($"IFScenario '{Id}': passage with no id");
                        continue;
                    }
                    Passages[pid] = p;
                }
            }
        }

        public bool HasPassage(string passageId)
        {
            return Passages.ContainsKey(passageId);
        }

        public JObject Passage(string passageId)
        {
            if (!Passages.ContainsKey(passageId))
            {
                LogError($"IFScenario '{Id}': no passage '{passageId}'");
                return new JObject();
            }
            return Passages[passageId];
        }

        /// <summary>
        /// Structural validation — every referenced passage exists, start is set,
        /// the ruleset is named. Returns a list of human-readable problems
        /// (empty == valid).
        /// </summary>
        public List<string> Validate(IFRuleset ruleset = null)
        {
            var problems = new List<string>();
            if (Start == "")
                problems.Add("no start passage");
            else if (!HasPassage(Start))
                problems.Add($"start passage '{Start}' missing");
            if (RulesetId == "")
                problems.Add("no ruleset id");

            foreach (KeyValuePair<string, JObject> kv in Passages)
            {
                string pid = kv.Key;
                JObject p = kv.Value;
                // Choice routes.
                JArray choices = p["choices"] as JArray;
                if (choices != null)
                {
                    foreach (JToken chTok in choices)
                    {
                        JObject ch = chTok as JObject;
                        string gotoId = ch != null ? Str(ch["goto"]) : "";
                        if (gotoId != "" && !HasPassage(gotoId))
                            problems.Add($"passage '{pid}' choice -> missing '{gotoId}'");
                        ValidateCheck(ch != null ? ch["check"] : null, pid, ruleset, problems);
                    }
                }
                // Passage-level check.
                ValidateCheck(p["check"], pid, ruleset, problems);
            }
            return problems;
        }

        private void ValidateCheck(JToken check, string pid, IFRuleset ruleset, List<string> problems)
        {
            if (check == null || check.Type == JTokenType.Null)
                return;
            if (IFPortableCheck.IsPortable(check))
            {
                // PORTABLE (P2): validated against the canonical vocabularies + (if a
                // ruleset is supplied) the ruleset's ability to express the semantic.
                foreach (string p in IFPortableCheck.Validate((JObject)check, pid, ruleset))
                    problems.Add(p);
            }
            else
            {
                // NATIVE (P0/P1): the check names a ruleset rule id directly.
                JObject checkObj = check as JObject;
                string ruleId = checkObj != null ? Str(checkObj["rule"]) : "";
                JObject outcomesObj = checkObj != null ? checkObj["outcomes"] as JObject : null;
                bool outcomesEmpty = outcomesObj == null || outcomesObj.Count == 0;
                if (ruleId == "" && !outcomesEmpty)
                    problems.Add($"passage '{pid}' check has neither 'rule' nor 'semantic'");
                if (ruleset != null && ruleId != "" && (ruleset.Rule(ruleId)?.Count ?? 0) == 0)
                    problems.Add($"passage '{pid}' check -> unknown rule '{ruleId}'");
            }
            // Outcome routes exist — shared by both shapes.
            JObject outcomes = (check as JObject)?["outcomes"] as JObject;
            if (outcomes != null)
            {
                foreach (JProperty prop in outcomes.Properties())
                {
                    string band = prop.Name;
                    JObject oc = prop.Value as JObject;
                    string gotoId = oc != null ? Str(oc["goto"]) : "";
                    if (gotoId != "" && !HasPassage(gotoId))
                        problems.Add($"passage '{pid}' outcome '{band}' -> missing '{gotoId}'");
                }
            }
        }

        public JObject Raw()
        {
            return _raw;
        }

        // --- Godot semantics helpers -------------------------------------------

        /// <summary>Mirrors Godot str() over a JSON token: "" for null/absent.</summary>
        private static string Str(JToken t)
        {
            if (t == null || t.Type == JTokenType.Null)
                return "";
            return t.Type == JTokenType.String ? (string)t : t.ToString();
        }

        private static void LogError(string msg) => UnityEngine.Debug.LogError(msg);

        private static void LogWarning(string msg) => UnityEngine.Debug.LogWarning(msg);
    }
}
