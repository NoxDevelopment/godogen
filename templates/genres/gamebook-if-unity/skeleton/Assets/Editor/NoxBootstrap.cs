// Assets/Editor/NoxBootstrap.cs
// Code-built play scene, NoxDev style. Unity .unity files are hostile to hand-
// authoring (YAML with fileID cross-references), so the skeleton ships NO scene:
// this editor script builds the gamebook reader UI — title, body, a choices
// column, and a live sheet HUD — from code and saves it to Assets/Scenes/Main.unity
// on first import. Runs once automatically (never overwrites an existing Main.unity),
// on demand via NoxDev > Rebuild Demo Scene, or headless via
//   Unity.exe -batchmode -quit -nographics -projectPath <p> \
//       -executeMethod NoxDev.Editor.NoxBootstrap.BuildDemoScene
using System.IO;
using NoxDev.GamebookIf;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.SceneManagement;
using UnityEngine.UI;

namespace NoxDev.Editor
{
    public static class NoxBootstrap
    {
        const string ScenePath = "Assets/Scenes/Main.unity";

        static readonly Color Bg = new Color(0.07f, 0.075f, 0.09f);
        static readonly Color Ink = new Color(0.9f, 0.92f, 0.95f);
        static readonly Color Muted = new Color(0.6f, 0.64f, 0.7f);
        static readonly Color Accent = new Color(0.909804f, 0.768627f, 0.419608f);

        [InitializeOnLoadMethod]
        static void AutoBootstrap()
        {
            EditorApplication.delayCall += () =>
            {
                if (File.Exists(ScenePath) || EditorApplication.isPlayingOrWillChangePlaymode)
                    return;
                BuildDemoScene();
            };
        }

        [MenuItem("NoxDev/Rebuild Demo Scene")]
        public static void BuildDemoScene()
        {
            var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            var font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");

            // --- managers ---
            var gm = new GameObject("GameManager");
            gm.AddComponent<GameManager>();

            // --- canvas ---
            var canvasGo = new GameObject("Canvas", typeof(Canvas), typeof(CanvasScaler), typeof(GraphicRaycaster));
            var canvas = canvasGo.GetComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            var scaler = canvasGo.GetComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1280, 720);

            // background
            var bg = NewUi("Background", canvasGo.transform, out RectTransform bgRt);
            Stretch(bgRt);
            var bgImg = bg.AddComponent<Image>();
            bgImg.color = Bg;

            // a centered reading column
            var panel = NewUi("Panel", canvasGo.transform, out RectTransform panelRt);
            panelRt.anchorMin = new Vector2(0.5f, 0.5f);
            panelRt.anchorMax = new Vector2(0.5f, 0.5f);
            panelRt.pivot = new Vector2(0.5f, 0.5f);
            panelRt.sizeDelta = new Vector2(820, 620);
            var vlg = panel.AddComponent<VerticalLayoutGroup>();
            vlg.spacing = 14;
            vlg.padding = new RectOffset(24, 24, 24, 24);
            vlg.childControlWidth = true; vlg.childControlHeight = false;
            vlg.childForceExpandWidth = true; vlg.childForceExpandHeight = false;

            var title = NewText("Title", panel.transform, font, 30, Accent, TextAnchor.MiddleLeft);
            SetMinHeight(title.gameObject, 40);
            var body = NewText("Body", panel.transform, font, 19, Ink, TextAnchor.UpperLeft);
            body.horizontalOverflow = HorizontalWrapMode.Wrap;
            body.verticalOverflow = VerticalWrapMode.Overflow;
            SetMinHeight(body.gameObject, 220);

            var choicesGo = NewUi("Choices", panel.transform, out RectTransform _);
            var cvlg = choicesGo.AddComponent<VerticalLayoutGroup>();
            cvlg.spacing = 8;
            cvlg.childControlWidth = true; cvlg.childControlHeight = true;
            cvlg.childForceExpandWidth = true; cvlg.childForceExpandHeight = false;

            var sheet = NewText("SheetHud", panel.transform, font, 15, Muted, TextAnchor.MiddleLeft);
            SetMinHeight(sheet.gameObject, 28);

            // --- the driver, wired to the UI ---
            var playGo = new GameObject("GamebookPlay");
            var play = playGo.AddComponent<GamebookPlay>();
            play.titleText = title;
            play.bodyText = body;
            play.sheetText = sheet;
            play.choicesContainer = choicesGo.GetComponent<RectTransform>();
            play.uiFont = font;

            // --- event system for button clicks ---
            var es = new GameObject("EventSystem", typeof(EventSystem), typeof(StandaloneInputModule));

            Directory.CreateDirectory(Path.GetDirectoryName(ScenePath));
            EditorSceneManager.SaveScene(scene, ScenePath);
            Debug.Log($"[NoxBootstrap] built {ScenePath}");
        }

        // --- tiny uGUI helpers ---

        static GameObject NewUi(string name, Transform parent, out RectTransform rt)
        {
            var go = new GameObject(name, typeof(RectTransform));
            go.transform.SetParent(parent, false);
            rt = go.GetComponent<RectTransform>();
            return go;
        }

        static Text NewText(string name, Transform parent, Font font, int size, Color color, TextAnchor anchor)
        {
            var go = new GameObject(name, typeof(RectTransform), typeof(Text));
            go.transform.SetParent(parent, false);
            var t = go.GetComponent<Text>();
            t.font = font; t.fontSize = size; t.color = color; t.alignment = anchor;
            t.supportRichText = true;
            return t;
        }

        static void Stretch(RectTransform rt)
        {
            rt.anchorMin = Vector2.zero; rt.anchorMax = Vector2.one;
            rt.offsetMin = Vector2.zero; rt.offsetMax = Vector2.zero;
        }

        static void SetMinHeight(GameObject go, float h)
        {
            var le = go.AddComponent<LayoutElement>();
            le.minHeight = h;
        }
    }
}
