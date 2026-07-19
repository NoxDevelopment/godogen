// Assets/Scripts/Engine/IFRunner.cs
// Unity C# port of res://addons/nox_if_engine/if_runner.gd
//
// Plays a scenario deterministically over the computed engine — NO LLM, NO
// networking (P0). Wires the four pure pieces together:
//   IFRuleset (system data) + IFScenario (content data) + IFDice (seeded RNG)
//   -> drives an IFState through the narrative graph, resolving checks via
//   IFResolver and routing by outcome bands.
//
// Given a fixed seed this replays byte-for-byte (on this engine's own terms),
// which is what makes it headless-testable and, later, the authoritative state a
// multiplayer host would sync.
//
// Play loop (host/caller side):
//   var r = new IFRunner(); r.Load(ruleset, scenario, seed); r.Start();
//   while (!r.IsEnded()) {
//       var choices = r.AvailableChoices();      // conditions already filtered
//       r.Choose((string)choices[i]["id"]);      // apply effects + route
//   }
//
// Passage entry sequence (EnterPassage):
//   1. record the passage on the state (history)
//   2. apply passage.onEnter effects
//   3. if the passage has a `check`, resolve it now and route by outcome band
//      (an auto-resolution node — e.g. a trap or a guardian) — chained entry
//   4. if the passage is an `ending`, mark terminal and stop

using System.Collections.Generic;
using Newtonsoft.Json.Linq;

namespace NoxIfEngine
{
    public sealed class IFRunner
    {
        public const int MaxChain = 64; // guard against a mis-authored routing cycle

        public IFRuleset Ruleset;
        public IFScenario Scenario;
        public IFState State;
        public IFDice Dice;
        public IFResolver Resolver;

        /// <summary>Ordered log of everything that happened (for the probe/UI/replay assertions).
        ///   { type:"enter"|"ending"|"check"|"choice", ... }</summary>
        public List<JObject> Trace = new List<JObject>();

        private long _seed = 0;

        public IFRunner()
        {
        }

        /// <summary>
        /// Load system + content + seed. The sheet is chosen in precedence order:
        ///   1. <paramref name="sheet"/> — an EXPLICIT sheet injected by the caller (P1: a
        ///      campaign injecting a carried character's sheet into the slot). Highest priority.
        ///   2. scenario.SheetOverride — a fixed sheet authored on the scenario.
        ///   3. generated from the ruleset's attribute `gen` expressions (seeded).
        /// When <paramref name="sheet"/> is omitted the P0 behaviour is unchanged.
        /// </summary>
        public void Load(IFRuleset ruleset, IFScenario scenario, long seed, JToken sheet = null)
        {
            Ruleset = ruleset;
            Scenario = scenario;
            _seed = seed;
            Dice = new IFDice();
            Dice.SetSeed(seed);
            Resolver = new IFResolver(Ruleset, Dice);
            State = new IFState(Ruleset);

            // Sheet: explicit injection > scenario override > generated.
            JObject sheetDict;
            if (sheet is JObject explicitSheet)
                sheetDict = NormalizeSheetOverride(explicitSheet);
            else if (Scenario.SheetOverride is JObject overrideSheet)
                sheetDict = NormalizeSheetOverride(overrideSheet);
            else
                sheetDict = Ruleset.GenerateSheet(Dice);
            State.InitSheet(sheetDict);

            // Initial short-term state.
            if (Scenario.InitVars != null)
                foreach (var kv in Scenario.InitVars)
                    State.SetVar(kv.Key, Dbl(kv.Value));
            if (Scenario.InitItems != null)
                foreach (var kv in Scenario.InitItems)
                    State.GrantItem(kv.Key, ToInt(kv.Value));
            if (Scenario.InitFlags != null)
                foreach (var kv in Scenario.InitFlags)
                    State.SetFlag(kv.Key, kv.Value);
        }

        private JObject NormalizeSheetOverride(JObject ov)
        {
            // Accept {attributes:{...}, resources:{...}, resource_max?:{...}} directly, or
            // a flat {SKILL:9, STAMINA:20, ...} which we split into attrs/resources.
            if (ov.ContainsKey("attributes") || ov.ContainsKey("resources"))
            {
                return new JObject
                {
                    ["attributes"] = ov["attributes"] != null ? ov["attributes"].DeepClone() : new JObject(),
                    ["resources"] = ov["resources"] != null ? ov["resources"].DeepClone() : new JObject(),
                    ["resource_max"] = ov["resource_max"] != null ? ov["resource_max"].DeepClone() : new JObject(),
                };
            }
            var attrs = new JObject();
            var res = new JObject();
            foreach (var prop in ov.Properties())
            {
                string key = prop.Name;
                if (Ruleset.HasResource(key))
                    res[key] = Dbl(prop.Value);
                if (Ruleset.HasAttribute(key))
                    attrs[key] = Dbl(prop.Value);
            }
            return new JObject
            {
                ["attributes"] = attrs,
                ["resources"] = res,
                ["resource_max"] = new JObject(),
            };
        }

        /// <summary>Begin play at the scenario's start passage.</summary>
        public void Start()
        {
            Trace.Clear();
            EnterPassage(Scenario.Start, 0);
        }

        public bool IsEnded()
        {
            return State.Ended;
        }

        public JObject Ending()
        {
            return State.Ending;
        }

        public JObject CurrentPassage()
        {
            return Scenario.Passage(State.CurrentPassage);
        }

        /// <summary>
        /// Choices whose conditions currently hold — what the player (or AI-player-assist
        /// later) may pick. Each is the raw choice dict; use ["id"] to choose.
        /// </summary>
        public List<JObject> AvailableChoices()
        {
            var outList = new List<JObject>();
            if (State.Ended)
                return outList;
            var p = CurrentPassage();
            if (p["choices"] is JArray choices)
            {
                foreach (var ch in choices)
                {
                    if (State.ConditionsMet(ch["conditions"]))
                        outList.Add((JObject)ch);
                }
            }
            return outList;
        }

        /// <summary>
        /// Is a given choice offered right now (conditions hold)? Used for item-gate
        /// assertions.
        /// </summary>
        public bool IsChoiceAvailable(string choiceId)
        {
            foreach (var ch in AvailableChoices())
            {
                if (Str(ch["id"]) == choiceId)
                    return true;
            }
            return false;
        }

        /// <summary>Take a choice by id: apply its effects, run its optional check, route.</summary>
        public void Choose(string choiceId)
        {
            if (State.Ended)
            {
                UnityEngine.Debug.LogWarning($"IFRunner: Choose('{choiceId}') after ending");
                return;
            }
            var p = CurrentPassage();
            JObject choice = null;
            if (p["choices"] is JArray choices)
            {
                foreach (var ch in choices)
                {
                    if (Str(ch["id"]) == choiceId)
                    {
                        choice = (JObject)ch;
                        break;
                    }
                }
            }
            if (choice == null || choice.Count == 0)
            {
                UnityEngine.Debug.LogError($"IFRunner: no choice '{choiceId}' at passage '{State.CurrentPassage}'");
                return;
            }
            if (!State.ConditionsMet(choice["conditions"]))
            {
                UnityEngine.Debug.LogError($"IFRunner: choice '{choiceId}' not available (conditions unmet)");
                return;
            }

            Trace.Add(new JObject
            {
                ["type"] = "choice",
                ["passage"] = State.CurrentPassage,
                ["choice"] = choiceId,
            });

            string route = State.ApplyEffects(choice["effects"]);

            // An inline check on the choice can override the route.
            if (choice.ContainsKey("check"))
            {
                string checkRoute = RunCheck((JObject)choice["check"]);
                if (checkRoute != "")
                    route = checkRoute;
            }

            if (route == "")
                route = Str(choice["goto"]);
            if (route == "")
            {
                UnityEngine.Debug.LogError($"IFRunner: choice '{choiceId}' produced no route");
                return;
            }
            EnterPassage(route, 0);
        }

        // --- internals ----------------------------------------------------------

        private void EnterPassage(string passageId, int depth)
        {
            if (depth > MaxChain)
            {
                UnityEngine.Debug.LogError($"IFRunner: routing depth exceeded at '{passageId}' (cycle?)");
                return;
            }
            if (!Scenario.HasPassage(passageId))
            {
                UnityEngine.Debug.LogError($"IFRunner: route to missing passage '{passageId}'");
                return;
            }

            State.EnterPassage(passageId);
            var p = Scenario.Passage(passageId);
            Trace.Add(new JObject { ["type"] = "enter", ["passage"] = passageId });

            // 1) onEnter effects (a passage effect may itself route via a goto effect).
            string route = State.ApplyEffects(p["onEnter"]);

            // 2) ending short-circuits.
            if (p.ContainsKey("ending"))
            {
                State.MarkEnding((JObject)p["ending"]);
                Trace.Add(new JObject
                {
                    ["type"] = "ending",
                    ["passage"] = passageId,
                    ["ending"] = p["ending"].DeepClone(),
                });
                return;
            }

            // 3) an onEnter goto effect routes immediately.
            if (route != "")
            {
                EnterPassage(route, depth + 1);
                return;
            }

            // 4) a passage-level check auto-resolves and routes by outcome band.
            if (p.ContainsKey("check"))
            {
                string checkRoute = RunCheck((JObject)p["check"]);
                if (checkRoute != "")
                    EnterPassage(checkRoute, depth + 1);
                return;
            }
            // else: an interactive passage — wait for Choose().
        }

        /// <summary>
        /// Resolve a check node against a ruleset rule, apply the matched outcome's
        /// effects, and return its route ("" if none). Records into Trace + RollLog.
        ///
        /// Dispatches on the check SHAPE (P2):
        ///   * PORTABLE (has `semantic`) — compiled by IFPortableCheck into a concrete
        ///     { rule, args } for THIS ruleset, resolved, and the native band mapped back
        ///     to a CANONICAL band that the scenario's `outcomes` route on (with the
        ///     canonical fallback ladder).
        ///   * NATIVE (has `rule`) — the P0/P1 path, unchanged: the check names a ruleset
        ///     rule id + native args and routes on native band ids.
        /// </summary>
        private string RunCheck(JObject check)
        {
            bool portable = IFPortableCheck.IsPortable(check);

            string ruleId;
            JObject args;
            if (portable)
            {
                var compiled = IFPortableCheck.Compile(check, Ruleset);
                if (!(compiled["ok"] != null && (bool)compiled["ok"]))
                {
                    UnityEngine.Debug.LogError(
                        $"IFRunner: portable check could not compile — {Str(compiled["error"])}");
                    return "";
                }
                ruleId = Str(compiled["rule"]);
                args = compiled["args"] as JObject ?? new JObject();
            }
            else
            {
                ruleId = Str(check["rule"]);
                args = check["args"] as JObject ?? new JObject();
            }

            var rule = Ruleset.Rule(ruleId);
            if (rule == null || rule.Count == 0)
                return "";
            var result = Resolver.Resolve(rule, State, args);
            string nativeBand = Str(result["band"]);

            // Route on the canonical band for portable checks; on the native band for
            // native checks (byte-for-byte the P0/P1 behaviour).
            string band = nativeBand;
            var outcomes = check["outcomes"] as JObject ?? new JObject();
            JObject outcome;
            if (portable)
            {
                band = IFPortableCheck.CanonicalBand(nativeBand, Ruleset);
                outcome = IFPortableCheck.ResolveOutcome(outcomes, band);
            }
            else
            {
                outcome = (outcomes[nativeBand] as JObject)
                          ?? (outcomes["_default"] as JObject)
                          ?? new JObject();
            }

            Trace.Add(new JObject
            {
                ["type"] = "check",
                ["passage"] = State.CurrentPassage,
                ["portable"] = portable,
                ["semantic"] = Str(check["semantic"]),
                ["rule"] = ruleId,
                ["band"] = band,
                ["native_band"] = nativeBand,
                ["total"] = result["total"] != null ? result["total"].DeepClone() : JValue.CreateNull(),
                ["faces"] = result["faces"] != null ? result["faces"].DeepClone() : new JArray(),
                ["target"] = result["target"] != null ? result["target"].DeepClone() : JValue.CreateNull(),
                ["success"] = result["success"] != null ? result["success"].DeepClone() : JValue.CreateNull(),
                ["crit"] = result["crit"] != null ? result["crit"].DeepClone() : (JToken)"",
            });

            string route = State.ApplyEffects(outcome["effects"]);
            string gotoRoute = Str(outcome["goto"]);
            if (gotoRoute != "")
                route = gotoRoute;
            return route;
        }

        /// <summary>
        /// Snapshot for save/replay — the SHORT-TERM store's payload (P1). Captures the
        /// seed, the live RNG position and the full IFState so a session can be resumed
        /// deterministically with Restore().
        /// </summary>
        public JObject Snapshot()
        {
            return new JObject
            {
                ["seed"] = _seed,
                ["dice_state"] = Dice.GetState(),
                ["state"] = State.SaveData(),
            };
        }

        /// <summary>
        /// Rehydrate a runner from a Snapshot() — the inverse of Load()+play. Rebuilds the
        /// dice at its exact mid-stream position (seed + saved RNG state) and reloads the
        /// IFState, so continuing to play produces the identical sequence a non-interrupted
        /// run would have. The caller supplies the same ruleset + scenario the snapshot was
        /// taken against (content is not stored in the save — only mutable state is).
        /// </summary>
        public void Restore(IFRuleset ruleset, IFScenario scenario, JObject snapshot)
        {
            Ruleset = ruleset;
            Scenario = scenario;
            _seed = snapshot["seed"] != null ? (long)snapshot["seed"] : 0L;
            Dice = new IFDice();
            Dice.SetSeed(_seed);
            Dice.SetState(snapshot["dice_state"] != null ? (ulong)snapshot["dice_state"] : 0UL);
            Resolver = new IFResolver(Ruleset, Dice);
            State = new IFState(Ruleset);
            State.LoadData(snapshot["state"] as JObject ?? new JObject());
            Trace.Clear();
        }

        // --- helpers ------------------------------------------------------------

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

        /// <summary>Mirrors GDScript int(): truncate-toward-zero numeric coercion.</summary>
        private static int ToInt(JToken t)
        {
            return (int)Dbl(t);
        }
    }
}
