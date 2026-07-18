// Assets/Scripts/GamebookPlay.cs
// Runtime driver for the Unity gamebook play scene. Owns an IFRunner (the C# port
// of the nox_if_engine), renders the current passage (title + body + a live sheet
// HUD), and builds a choice button per available choice — clicking one calls
// Choose() and re-renders. Check passages auto-chain inside the engine, so the
// player only ever sees passages-with-choices or an ending. Wholly computed:
// there is no AI here (the AI-DM layer is a documented, optional add — parity with
// the Godot template's ai_dm seam is a follow-on).
using System.Collections.Generic;
using NoxIfEngine;
using UnityEngine;
using UnityEngine.UI;

namespace NoxDev.GamebookIf
{
    public sealed class GamebookPlay : MonoBehaviour, ISaveable
    {
        [Header("Scenario")]
        public string rulesetId = "ff-2d6";
        public string scenarioId = "thornwood-crypt";
        public long seed = 12345;

        [Header("Wired by NoxBootstrap")]
        public Text titleText;
        public Text bodyText;
        public Text sheetText;
        public RectTransform choicesContainer;
        public Font uiFont;

        IFRuleset _ruleset;
        IFScenario _scenario;
        IFRunner _runner;

        public string SaveKey => "gamebook";

        void Start()
        {
            if (uiFont == null) uiFont = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
            GameManager.Instance?.Register(this);
            NewGame();
        }

        public void NewGame()
        {
            _ruleset = IFRuleset.FromFile(IfDataPaths.Ruleset(rulesetId));
            _scenario = IFScenario.FromFile(IfDataPaths.Scenario(scenarioId));
            _runner = new IFRunner();
            _runner.Load(_ruleset, _scenario, seed);
            _runner.Start();
            Render();
        }

        void Render()
        {
            if (_runner == null) return;
            ClearChoices();

            if (_runner.IsEnded())
            {
                var end = _runner.Ending();
                if (titleText != null) titleText.text = end != null ? (string)end["label"] : "The End";
                if (bodyText != null) bodyText.text = CurrentText();
                MakeButton("Play again", NewGame);
            }
            else
            {
                var p = _runner.CurrentPassage();
                if (titleText != null) titleText.text = p != null ? (string)p["title"] : "";
                if (bodyText != null) bodyText.text = p != null ? (string)p["text"] : "";
                foreach (var c in _runner.AvailableChoices())
                {
                    var id = (string)c["id"];
                    if (!_runner.IsChoiceAvailable(id)) continue;
                    var label = (string)c["text"];
                    MakeButton(label, () => { _runner.Choose(id); Render(); });
                }
            }
            RenderSheet();
        }

        string CurrentText()
        {
            var p = _runner.CurrentPassage();
            return p != null ? (string)p["text"] : "";
        }

        void RenderSheet()
        {
            if (sheetText == null || _runner == null) return;
            var s = _runner.State;
            sheetText.text =
                $"SKILL {s.GetAttr("SKILL"):0}   STAMINA {s.GetAttr("STAMINA"):0}   LUCK {s.GetAttr("LUCK"):0}   GOLD {s.GetVar("gold"):0}";
        }

        void ClearChoices()
        {
            if (choicesContainer == null) return;
            for (int i = choicesContainer.childCount - 1; i >= 0; i--)
                Destroy(choicesContainer.GetChild(i).gameObject);
        }

        void MakeButton(string label, UnityEngine.Events.UnityAction onClick)
        {
            if (choicesContainer == null) return;
            var go = new GameObject("Choice", typeof(RectTransform), typeof(Image), typeof(Button));
            go.transform.SetParent(choicesContainer, false);
            var img = go.GetComponent<Image>();
            img.color = new Color(0.16f, 0.18f, 0.22f);
            var le = go.AddComponent<LayoutElement>();
            le.minHeight = 44;

            var txtGo = new GameObject("Label", typeof(RectTransform), typeof(Text));
            txtGo.transform.SetParent(go.transform, false);
            var txt = txtGo.GetComponent<Text>();
            txt.font = uiFont;
            txt.text = label;
            txt.color = new Color(0.9f, 0.92f, 0.95f);
            txt.alignment = TextAnchor.MiddleCenter;
            txt.fontSize = 18;
            var trt = txtGo.GetComponent<RectTransform>();
            trt.anchorMin = Vector2.zero; trt.anchorMax = Vector2.one;
            trt.offsetMin = new Vector2(12, 4); trt.offsetMax = new Vector2(-12, -4);

            go.GetComponent<Button>().onClick.AddListener(onClick);
        }

        // ISaveable — persist the engine snapshot so a run resumes exactly.
        public Newtonsoft.Json.Linq.JObject SaveData() =>
            _runner != null ? _runner.Snapshot() : new Newtonsoft.Json.Linq.JObject();

        public void LoadData(Newtonsoft.Json.Linq.JObject data)
        {
            if (data == null || !data.HasValues) return;
            _ruleset ??= IFRuleset.FromFile(IfDataPaths.Ruleset(rulesetId));
            _scenario ??= IFScenario.FromFile(IfDataPaths.Scenario(scenarioId));
            _runner = new IFRunner();
            _runner.Restore(_ruleset, _scenario, data);
            Render();
        }
    }
}
