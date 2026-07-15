// Assets/Editor/NoxBootstrap.cs
// Code-built demo scene, NoxDev style. Unity scenes are hostile to hand-
// authored text (YAML with fileID cross-references), so the skeleton ships NO
// .unity file: this editor script builds the bullet-hell arena — walls, player
// ship, the bullet spawner (standard bullet + ring pattern), the BulletSystem
// engine, HUD, camera — entirely from code and saves it to
// Assets/Scenes/Main.unity on first import. Same discipline as the Godot lane's
// code-built geometry: every object is constructed by reviewable code.
//
// Runs automatically once after the first import (guarded: it never overwrites
// an existing Main.unity). Re-run on demand via the menu item
// NoxDev > Rebuild Demo Scene, or headless via
//   Unity.exe -batchmode -quit -projectPath <p> \
//       -executeMethod NoxDev.Editor.NoxBootstrap.BuildDemoScene

using System.IO;
using NoxDev.BulletHell;
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

        static readonly Color PlayerColor = new Color(0.419608f, 0.796078f, 0.909804f);
        static readonly Color CoreColor = new Color(1f, 1f, 1f, 0.9f);
        static readonly Color SpawnerColor = new Color(0.768627f, 0.290196f, 0.317647f);
        static readonly Color WallColor = new Color(0.227451f, 0.247059f, 0.290196f);
        static readonly Color FloorColor = new Color(0.078431f, 0.086275f, 0.113725f);
        static readonly Color BackgroundColor = new Color(0.05f, 0.055f, 0.07f);

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
            BuildBulletEngine(square);
            BuildSpawner(square, new Vector2(0f, 3.2f));
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
            wall.GetComponent<SpriteRenderer>().sortingOrder = -5;
            wall.AddComponent<BoxCollider2D>();
        }

        static GameObject BuildPlayer(Sprite square)
        {
            var player = new GameObject("Player") { tag = "Player" };
            player.transform.position = new Vector3(0f, -3.6f, 0f);

            // Ship body — a compact cyan blockout.
            var body = MakeSpriteObject("Visual", square, PlayerColor, player.transform);
            body.transform.localScale = new Vector3(0.5f, 0.5f, 1f);
            body.GetComponent<SpriteRenderer>().sortingOrder = 10;

            // The tiny white core marks the (small!) hurtbox — shmup convention.
            var core = MakeSpriteObject("Core", square, CoreColor, player.transform);
            core.transform.localScale = new Vector3(0.14f, 0.14f, 1f);
            core.GetComponent<SpriteRenderer>().sortingOrder = 11;

            var body2d = player.AddComponent<Rigidbody2D>();
            body2d.gravityScale = 0f;
            body2d.freezeRotation = true;
            body2d.bodyType = RigidbodyType2D.Kinematic;
            body2d.interpolation = RigidbodyInterpolation2D.Interpolate;

            var hurtbox = player.AddComponent<CircleCollider2D>();
            hurtbox.radius = 0.12f;
            hurtbox.isTrigger = true;

            player.AddComponent<PlayerShip>();
            return player;
        }

        static void BuildBulletEngine(Sprite square)
        {
            var engine = new GameObject("BulletSystem");
            var system = engine.AddComponent<BulletSystem>();
            system.bulletSprite = square;
            system.prewarm = 64;

            // Bullet type registration node (BulletUpHell BulletProps, id "standard").
            var bulletProps = new GameObject("BulletProps");
            bulletProps.transform.SetParent(engine.transform, false);
            bulletProps.AddComponent<BulletDefinition>();

            // Pattern registration node (BulletUpHell PatternCircle, id "ring").
            var patterns = new GameObject("Patterns");
            patterns.transform.SetParent(engine.transform, false);
            patterns.AddComponent<PatternDefinition>();
        }

        static void BuildSpawner(Sprite square, Vector2 position)
        {
            var spawner = new GameObject("Spawner");
            spawner.transform.position = position;

            // A red diamond blockout (a square rotated 45 degrees).
            var visual = MakeSpriteObject("Visual", square, SpawnerColor, spawner.transform);
            visual.transform.localScale = new Vector3(0.55f, 0.55f, 1f);
            visual.transform.localRotation = Quaternion.Euler(0f, 0f, 45f);
            visual.GetComponent<SpriteRenderer>().sortingOrder = 3;

            // The firing point drives volley cadence (BuHSpawnPoint).
            var spawnPoint = new GameObject("SpawnPoint");
            spawnPoint.transform.SetParent(spawner.transform, false);
            spawnPoint.AddComponent<Spawner>();
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

            MakeLabel(canvasGo.transform, "LivesLabel", "Lives 3/3",
                new Vector2(16f, -16f));
            MakeLabel(canvasGo.transform, "BulletsLabel", "Bullets: 0",
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
