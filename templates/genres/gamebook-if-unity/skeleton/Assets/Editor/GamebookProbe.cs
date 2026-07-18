// Assets/Editor/GamebookProbe.cs
// Headless determinism/behaviour probe for the Unity C# port of the nox_if_engine
// (P0 core parity with the Godot if-engine). Plays the sample scenario
// `thornwood-crypt` under the `ff-2d6` ruleset end-to-end and asserts the same
// invariants the Godot boot_probe does: passage render, effect application, an
// item-gated choice (both open AND closed), dice-check resolution, a victory
// ending, save/restore round-trip, and determinism (same seed -> byte-identical
// run). Prints ONE `DEBUG: ... fails=N ... => OK` line and exits 0 (or 1 on any
// failure), so CI/scaffold can gate on it:
//   Unity.exe -batchmode -quit -nographics -projectPath <p> \
//       -executeMethod NoxDev.Editor.GamebookProbe.Run -logFile <log>
using System.Collections.Generic;
using System.Text;
using NoxIfEngine;
using UnityEditor;
using UnityEngine;

namespace NoxDev.Editor
{
    public static class GamebookProbe
    {
        static int _fails;
        static readonly StringBuilder _line = new StringBuilder();

        static void Check(string name, bool cond)
        {
            if (!cond) _fails++;
            _line.Append(' ').Append(name).Append('=').Append(cond ? "ok" : "FAIL");
        }

        static IFRunner FreshRun(IFRuleset rs, IFScenario sc, long seed)
        {
            var r = new IFRunner();
            r.Load(rs, sc, seed);
            r.Start();
            return r;
        }

        // Greedily play to an ending by taking the first AVAILABLE choice at every
        // passage (check passages auto-chain inside the runner). Guarded against a
        // mis-authored cycle. Returns the visited-passage sequence.
        static List<string> PlayGreedy(IFRunner r)
        {
            var visited = new List<string> { (string)r.CurrentPassage()["id"] };
            int guard = 0;
            while (!r.IsEnded() && guard++ < 128)
            {
                var choices = r.AvailableChoices();
                if (choices == null || choices.Count == 0) break;
                string pick = null;
                foreach (var c in choices)
                {
                    var cid = (string)c["id"];
                    if (r.IsChoiceAvailable(cid)) { pick = cid; break; }
                }
                if (pick == null) break;
                r.Choose(pick);
                visited.Add((string)r.CurrentPassage()["id"]);
            }
            return visited;
        }

        static uint Fnv1a(string s)
        {
            uint h = 2166136261u;
            foreach (char ch in s) { h ^= ch; h *= 16777619u; }
            return h;
        }

        // A canonical, RNG-tolerant fingerprint of a completed run: the ending id +
        // final gold + the ordered roll totals from the log. Same seed => same string.
        static string RunSig(IFRunner r)
        {
            var sb = new StringBuilder();
            sb.Append(r.Ending() != null ? (string)r.Ending()["id"] : "none");
            sb.Append('|').Append(r.State.GetVar("gold"));
            sb.Append('|');
            foreach (var roll in r.State.RollLog)
            {
                var tot = roll["total"];
                sb.Append(tot != null ? tot.ToString() : "?").Append(',');
            }
            return sb.ToString();
        }

        public static void Run()
        {
            _fails = 0;
            _line.Clear();

            var rs = IFRuleset.FromFile(IfDataPaths.Ruleset("ff-2d6"));
            var sc = IFScenario.FromFile(IfDataPaths.Scenario("thornwood-crypt"));
            Check("ruleset_loaded", rs != null && rs.Id == "ff-2d6");
            Check("scenario_loaded", sc != null && sc.Id == "thornwood-crypt");

            var problems = sc.Validate(rs);
            Check("scenario_valid", problems != null && problems.Count == 0);

            // --- a detailed, seeded run through the win path ---
            var r = FreshRun(rs, sc, 12345);
            var start = r.CurrentPassage();
            Check("passage_render",
                start != null && (string)start["id"] == "crypt_gate"
                && !string.IsNullOrEmpty((string)start["title"])
                && !string.IsNullOrEmpty((string)start["text"]));
            Check("sheet_from_template", r.State.GetAttr("SKILL") == 9 && r.State.GetAttr("LUCK") == 11);

            r.Choose("descend");
            Check("effect_var_gold", r.State.GetVar("gold") == 5);
            Check("effect_item_grant", r.State.HasItem("torch"));
            Check("at_antechamber", (string)r.CurrentPassage()["id"] == "antechamber");

            r.Choose("search_sarcophagus");
            Check("item_key_granted", r.State.HasItem("iron_key"));

            // pry_open chains through dart_trap (a LUCK check) and lands at iron_door
            r.Choose("pry_open");
            Check("chained_through_check_to_iron_door", (string)r.CurrentPassage()["id"] == "iron_door");
            Check("dice_check_recorded", r.State.RollLog.Count >= 1); // the luck test ran

            // item gate — BOTH directions, via the state API
            Check("gate_open_with_key", r.IsChoiceAvailable("unlock"));
            r.State.ConsumeItem("iron_key", 1);
            Check("gate_closed_without_key", !r.IsChoiceAvailable("unlock"));
            r.State.GrantItem("iron_key", 1);
            Check("gate_reopens_with_key", r.IsChoiceAvailable("unlock"));

            // unlock consumes the key and chains through the guardian SKILL check to an ending
            r.Choose("unlock");
            Check("effect_item_consume", r.State.GetItem("iron_key") == 0);
            Check("skill_check_ran", r.State.RollLog.Count >= 2);
            Check("run_ended", r.IsEnded());
            var end = r.Ending();
            Check("ending_reached", end != null && !string.IsNullOrEmpty((string)end["id"]));
            Check("ending_is_terminal_kind",
                end != null && ((string)end["kind"] == "victory" || (string)end["kind"] == "retreat"));

            // --- the victory path is reachable (scan seeds; SKILL 9 wins most 2d6 roll-under) ---
            bool victoryFound = false;
            long winningSeed = 0;
            for (long s = 0; s < 200 && !victoryFound; s++)
            {
                var rr = FreshRun(rs, sc, s);
                PlayGreedy(rr);
                if (rr.IsEnded() && (string)rr.Ending()["id"] == "treasure")
                {
                    victoryFound = true;
                    winningSeed = s;
                    Check("victory_gold_total", rr.State.GetVar("gold") == 15); // 5 + 10
                }
            }
            Check("victory_reachable", victoryFound);

            // --- determinism: same seed -> identical run ---
            var d1 = FreshRun(rs, sc, winningSeed); PlayGreedy(d1);
            var d2 = FreshRun(rs, sc, winningSeed); PlayGreedy(d2);
            Check("determinism_same_seed", RunSig(d1) == RunSig(d2));

            // --- save/restore round-trip mid-run -> identical continuation ---
            var a = FreshRun(rs, sc, winningSeed);
            a.Choose("descend");
            a.Choose("search_sarcophagus");
            var snap = a.Snapshot();
            var b = new IFRunner();
            b.Restore(rs, sc, snap);
            Check("restore_position", (string)b.CurrentPassage()["id"] == (string)a.CurrentPassage()["id"]);
            PlayGreedy(a);
            PlayGreedy(b);
            Check("save_load_identical", RunSig(a) == RunSig(b));

            uint sig = Fnv1a(RunSig(d1));

            var msg = "DEBUG: gamebook-if-unity — engine=nox_if_engine(C#) ruleset=ff-2d6 "
                + $"scenario=thornwood-crypt win_seed={winningSeed} sig={sig:x8} rolls={d1.State.RollLog.Count}"
                + _line.ToString() + $" fails={_fails} => {( _fails == 0 ? "OK" : "FAILED")}";
            Debug.Log(msg);
            // Also to stdout so the console (-logFile) shows it plainly.
            System.Console.WriteLine(msg);

            EditorApplication.Exit(_fails == 0 ? 0 : 1);
        }
    }
}
