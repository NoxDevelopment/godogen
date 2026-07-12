// Assets/Editor/NoxBootstrap.cs
// Code-built demo scene, NoxDev style. Unity scenes are hostile to hand-
// authored text (YAML with fileID cross-references), so the skeleton ships NO
// .unity file: this editor script builds the arena — walls, player rig, chaser
// enemy, three practice targets, HUD, camera — entirely from code and saves it
// to Assets/Scenes/Main.unity on first import. Same discipline as the Godot
// lane's code-built geometry: every object is constructed by reviewable code.
//
// Runs automatically once after the first import (guarded: it never overwrites
// an existing Main.unity). Re-run on demand via the menu item
// NoxDev > Rebuild Demo Scene, or headless via
//   Unity.exe -batchmode -quit -projectPath <p> \
//       -executeMethod NoxDev.Editor.NoxBootstrap.BuildDemoScene

using System.IO;
using NoxDev.TopDownAction;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.UI;

namespace NoxDev.Editor
{
    public static class NoxBootstrap
    {
        const string ScenePath = "Assets/Scenes/Main.unity";
        const string SpritePath = "Assets/Sprites/white_square.png";

        static readonly Color PlayerColor = new Color(0.909804f, 0.768627f, 0.419608f);
        static readonly Color EnemyColor = new Color(0.847f, 0.325f, 0.310f);
        static readonly Color TargetColor = new Color(0.357f, 0.718f, 0.659f);
        static readonly Color WallColor = new Color(0.25f, 0.27f, 0.31f);
        static readonly Color FloorColor = new Color(0.118f, 0.125f, 0.145f);
        static readonly Color BackgroundColor = new Color(0.07f, 0.075f, 0.09f);

        // Arena interior half-extents in world units (camera shows 19.2 x 10.8).
        const float ArenaHalfWidth = 9.0f;
        const float ArenaHalfHeight = 5.0f;
        const float WallThickness = 0.5f;

        [InitializeOnLoadMethod]
        static void AutoBootstrap()
        {
            // Defer until the editor is idle; never rebuild an existing scene.
            EditorApplication.delayCall += () =>
            {
                if (File.Exists(ScenePath) || EditorApplication.isPlayingOrWillChangePlaymode)
                    return;
                BuildDemoScene();
            };
        }

        [MenuItem("NoxDev/Rebuild Demo Scene")]
        public static void RebuildDemoScene()
        {
            if (File.Exists(ScenePath))
                AssetDatabase.DeleteAsset(ScenePath);
            BuildDemoScene();
        }

        /// <summary>
        /// Build the demo arena scene from code and save it to Assets/Scenes/.
        /// Idempotent: does nothing if the scene already exists.
        /// </summary>
        public static void BuildDemoScene()
        {
            if (File.Exists(ScenePath))
            {
                Debug.Log($"NoxBootstrap: {ScenePath} already exists — nothing to do");
                return;
            }

            Sprite square = EnsureSquareSprite();
            Scene scene = EditorSceneManager.NewScene(
                NewSceneSetup.EmptyScene, NewSceneMode.Single);

            BuildCamera();
            BuildArena(square);
            GameObject player = BuildPlayer(square);
            BuildEnemy(square, new Vector2(6.5f, 3.2f));
            BuildTarget(square, new Vector2(-6.0f, 3.0f));
            BuildTarget(square, new Vector2(6.0f, -3.2f));
            BuildTarget(square, new Vector2(-5.5f, -2.8f));
            BuildHud();

            var managerGo = new GameObject("GameManager");
            managerGo.AddComponent<GameManager>();

            var mainGo = new GameObject("Main");
            mainGo.AddComponent<Main>();

            Directory.CreateDirectory(Path.GetDirectoryName(ScenePath));
            if (!EditorSceneManager.SaveScene(scene, ScenePath))
            {
                Debug.LogError($"NoxBootstrap: failed to save {ScenePath}");
                return;
            }
            EditorBuildSettings.scenes = new[]
            {
                new EditorBuildSettingsScene(ScenePath, true),
            };
            AssetDatabase.SaveAssets();
            Debug.Log($"NoxBootstrap: demo scene built at {ScenePath} "
                      + $"(player={player != null})");
        }

        // ---------------------------------------------------------------
        // pieces
        // ---------------------------------------------------------------

        static Sprite EnsureSquareSprite()
        {
            var existing = AssetDatabase.LoadAssetAtPath<Sprite>(SpritePath);
            if (existing != null)
                return existing;

            var texture = new Texture2D(64, 64, TextureFormat.RGBA32, false);
            var pixels = new Color32[64 * 64];
            for (int i = 0; i < pixels.Length; i++)
                pixels[i] = new Color32(255, 255, 255, 255);
            texture.SetPixels32(pixels);
            texture.Apply();

            Directory.CreateDirectory(Path.GetDirectoryName(SpritePath));
            File.WriteAllBytes(SpritePath, texture.EncodeToPNG());
            Object.DestroyImmediate(texture);
            AssetDatabase.ImportAsset(SpritePath);

            var importer = (TextureImporter)AssetImporter.GetAtPath(SpritePath);
            importer.textureType = TextureImporterType.Sprite;
            importer.spritePixelsPerUnit = 64;
            importer.filterMode = FilterMode.Point;
            importer.mipmapEnabled = false;
            importer.SaveAndReimport();

            return AssetDatabase.LoadAssetAtPath<Sprite>(SpritePath);
        }

        static void BuildCamera()
        {
            var go = new GameObject("Main Camera") { tag = "MainCamera" };
            go.transform.position = new Vector3(0f, 0f, -10f);
            var camera = go.AddComponent<Camera>();
            camera.orthographic = true;
            camera.orthographicSize = 5.4f;
            camera.clearFlags = CameraClearFlags.SolidColor;
            camera.backgroundColor = BackgroundColor;
            go.AddComponent<AudioListener>();
        }

        static void BuildArena(Sprite square)
        {
            var arena = new GameObject("Arena");

            var floor = MakeSpriteObject("Floor", square, FloorColor, arena.transform);
            floor.transform.localScale = new Vector3(
                ArenaHalfWidth * 2f + WallThickness * 2f,
                ArenaHalfHeight * 2f + WallThickness * 2f, 1f);
            floor.GetComponent<SpriteRenderer>().sortingOrder = -10;

            MakeWall(arena.transform, square, "WallTop",
                new Vector2(0f, ArenaHalfHeight + WallThickness / 2f),
                new Vector2(ArenaHalfWidth * 2f + WallThickness * 2f, WallThickness));
            MakeWall(arena.transform, square, "WallBottom",
                new Vector2(0f, -ArenaHalfHeight - WallThickness / 2f),
                new Vector2(ArenaHalfWidth * 2f + WallThickness * 2f, WallThickness));
            MakeWall(arena.transform, square, "WallLeft",
                new Vector2(-ArenaHalfWidth - WallThickness / 2f, 0f),
                new Vector2(WallThickness, ArenaHalfHeight * 2f));
            MakeWall(arena.transform, square, "WallRight",
                new Vector2(ArenaHalfWidth + WallThickness / 2f, 0f),
                new Vector2(WallThickness, ArenaHalfHeight * 2f));
        }

        static void MakeWall(Transform parent, Sprite square, string name,
            Vector2 position, Vector2 size)
        {
            var wall = MakeSpriteObject(name, square, WallColor, parent);
            wall.transform.position = position;
            wall.transform.localScale = new Vector3(size.x, size.y, 1f);
            wall.AddComponent<BoxCollider2D>();
        }

        static GameObject BuildPlayer(Sprite square)
        {
            var player = new GameObject("Player") { tag = "Player" };
            player.transform.position = Vector3.zero;

            var body = MakeSpriteObject("Body", square, PlayerColor, player.transform);
            body.transform.localScale = new Vector3(0.7f, 0.7f, 1f);
            body.GetComponent<SpriteRenderer>().sortingOrder = 2;

            var aimPivot = new GameObject("AimPivot");
            aimPivot.transform.SetParent(player.transform, false);

            var barrel = MakeSpriteObject(
                "Barrel", square, new Color(0.8f, 0.8f, 0.85f), aimPivot.transform);
            barrel.transform.localPosition = new Vector3(0.45f, 0f, 0f);
            barrel.transform.localScale = new Vector3(0.7f, 0.14f, 1f);
            barrel.GetComponent<SpriteRenderer>().sortingOrder = 3;

            var muzzle = new GameObject("Muzzle");
            muzzle.transform.SetParent(aimPivot.transform, false);
            muzzle.transform.localPosition = new Vector3(0.85f, 0f, 0f);

            var tracerGo = new GameObject("Tracer");
            tracerGo.transform.SetParent(player.transform, false);
            var tracer = tracerGo.AddComponent<LineRenderer>();
            tracer.useWorldSpace = true;
            tracer.positionCount = 0;
            tracer.startWidth = 0.05f;
            tracer.endWidth = 0.02f;
            tracer.sharedMaterial =
                AssetDatabase.GetBuiltinExtraResource<Material>("Sprites-Default.mat");
            tracer.startColor = new Color(1f, 0.95f, 0.6f);
            tracer.endColor = new Color(1f, 0.95f, 0.6f, 0.2f);
            tracer.sortingOrder = 5;
            tracer.enabled = false;

            var rigidbody = player.AddComponent<Rigidbody2D>();
            rigidbody.gravityScale = 0f;
            rigidbody.freezeRotation = true;
            rigidbody.interpolation = RigidbodyInterpolation2D.Interpolate;
            var collider = player.AddComponent<CircleCollider2D>();
            collider.radius = 0.35f;

            player.AddComponent<PlayerController>();
            return player;
        }

        static void BuildEnemy(Sprite square, Vector2 position)
        {
            var enemy = new GameObject("Enemy");
            enemy.transform.position = position;

            var visual = MakeSpriteObject("Visual", square, EnemyColor, enemy.transform);
            visual.transform.localScale = new Vector3(0.8f, 0.8f, 1f);
            visual.GetComponent<SpriteRenderer>().sortingOrder = 2;

            var rigidbody = enemy.AddComponent<Rigidbody2D>();
            rigidbody.gravityScale = 0f;
            rigidbody.freezeRotation = true;
            rigidbody.interpolation = RigidbodyInterpolation2D.Interpolate;
            var collider = enemy.AddComponent<CircleCollider2D>();
            collider.radius = 0.4f;

            enemy.AddComponent<Enemy>();
        }

        static void BuildTarget(Sprite square, Vector2 position)
        {
            var target = new GameObject("Target");
            target.transform.position = position;

            var visual = MakeSpriteObject("Visual", square, TargetColor, target.transform);
            visual.transform.localScale = new Vector3(0.6f, 0.6f, 1f);
            visual.GetComponent<SpriteRenderer>().sortingOrder = 1;

            target.AddComponent<BoxCollider2D>().size = new Vector2(0.6f, 0.6f);
            target.AddComponent<Target>();
        }

        static void BuildHud()
        {
            var canvasGo = new GameObject("HUD");
            var canvas = canvasGo.AddComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            var scaler = canvasGo.AddComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1152f, 648f);
            canvasGo.AddComponent<GraphicRaycaster>();

            MakeLabel(canvasGo.transform, "HealthLabel", "HP 5/5",
                new Vector2(16f, -16f));
            MakeLabel(canvasGo.transform, "TargetsLabel", "Targets left: 3",
                new Vector2(16f, -48f));
        }

        static void MakeLabel(Transform parent, string name, string content,
            Vector2 offsetFromTopLeft)
        {
            var go = new GameObject(name);
            go.transform.SetParent(parent, false);
            var rect = go.AddComponent<RectTransform>();
            rect.anchorMin = new Vector2(0f, 1f);
            rect.anchorMax = new Vector2(0f, 1f);
            rect.pivot = new Vector2(0f, 1f);
            rect.anchoredPosition = offsetFromTopLeft;
            rect.sizeDelta = new Vector2(360f, 32f);

            var text = go.AddComponent<Text>();
            text.text = content;
            text.font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
            text.fontSize = 24;
            text.color = Color.white;
            text.alignment = TextAnchor.UpperLeft;
        }

        static GameObject MakeSpriteObject(
            string name, Sprite sprite, Color color, Transform parent)
        {
            var go = new GameObject(name);
            if (parent != null)
                go.transform.SetParent(parent, false);
            var renderer = go.AddComponent<SpriteRenderer>();
            renderer.sprite = sprite;
            renderer.color = color;
            return go;
        }
    }
}
