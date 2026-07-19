// Assets/Scripts/BulletSystem.cs
// First-party bullet engine — the Unity port of the Godot template's
// BulletUpHell "Spawning" autoload. BulletUpHell is a third-party Godot addon;
// the Unity lane is pure first-party (only pinned official UPM packages), so
// the pooled-bullet mechanic is reimplemented here from scratch.
//
// Faithful to the addon's architecture: bullets are NOT nodes. They are pooled
// GameObjects processed centrally by this single manager (position integration,
// lifetime, out-of-box death, and collision against the registered "Player"
// special target) — the analogue of BulletUpHell keeping every bullet as a
// shape inside one shared Area2D and stepping them from the autoload.
//
// ABI mapping (BulletUpHell -> BulletSystem):
//   Spawning autoload                    -> BulletSystem.Instance singleton
//   Spawning.poolBullets.size()          -> BulletSystem.ActiveBulletCount
//   Spawning.bullet_collided_body signal -> BulletSystem.BulletHitBody event
//   Spawning.edit_special_target("Player", ship) -> RegisterTarget("Player", ...)
//   BulletProps sub-resource (id "standard")     -> BulletProps (below)
//   PatternCircle resource (id "ring")           -> SpawnPattern (below)
//   SpawnPoint.spawn(pattern_id)                 -> EmitVolley(patternId, origin)

using System;
using System.Collections.Generic;
using UnityEngine;

namespace NoxDev.BulletHell
{
    /// <summary>
    /// Definition of a bullet type (the Unity port of BulletUpHell's BulletProps
    /// sub-resource, id "standard"). Registered by id so new bullet types are a
    /// duplicate-and-tweak, exactly like the Godot "how to extend" recipe.
    /// </summary>
    [Serializable]
    public sealed class BulletProps
    {
        [Tooltip("Registration id (BulletUpHell BulletProps id).")]
        public string id = "standard";

        [Tooltip("Damage dealt to the player on contact.")]
        public int damage = 1;

        [Tooltip("Constant speed in world units per second.")]
        public float speed = 2.4f;

        [Tooltip("Collision radius of the bullet, in world units.")]
        public float radius = 0.12f;

        [Tooltip("Lifetime before self-despawn, in seconds (death_after_time).")]
        public float lifeTime = 10f;

        [Tooltip("Bullet dies when its center leaves this world-space box "
                 + "(death_outside_box). Wider than the arena so bullets clear "
                 + "the walls before dying.")]
        public Rect deathBox = new Rect(-11f, -7f, 22f, 14f);

        [Tooltip("Visual scale of the pooled sprite for this bullet type.")]
        public float visualScale = 0.24f;

        [Tooltip("Sprite tint for this bullet type.")]
        public Color color = new Color(1f, 0.83f, 0.42f, 1f);
    }

    /// <summary>
    /// A radial volley definition (the Unity port of BulletUpHell's PatternCircle
    /// resource, id "ring"): a ring of <see cref="count"/> bullets fired outward
    /// from the spawn origin.
    /// </summary>
    [Serializable]
    public sealed class SpawnPattern
    {
        [Tooltip("Registration id (BulletUpHell SpawnPattern id).")]
        public string id = "ring";

        [Tooltip("Which BulletProps id this pattern fires.")]
        public string bulletId = "standard";

        [Tooltip("Bullets per volley (PatternCircle nbr).")]
        public int count = 12;

        [Tooltip("Radius of the spawn ring the bullets emanate from, in world "
                 + "units (PatternCircle radius).")]
        public float spawnRadius = 0.4f;

        [Tooltip("Total arc swept by the ring, in radians (angle_total). "
                 + "2*PI = a full 360-degree ring.")]
        public float angleTotal = Mathf.PI * 2f;

        [Tooltip("Angular offset of the whole ring, in radians (angle_decal).")]
        public float angleOffset = 0f;

        [Tooltip("Seconds between volleys (PatternCircle cooldown_spawn).")]
        public float cooldownSpawn = 0.8f;

        [Tooltip("Volleys to fire before stopping; -1 = infinite (iterations).")]
        public int iterations = -1;
    }

    /// <summary>
    /// The pooled bullet engine. One per scene (auto-creating singleton). Owns
    /// the bullet pool, the id-keyed bullet/pattern registries, and the central
    /// per-FixedUpdate step that moves every live bullet and resolves hits.
    /// </summary>
    public sealed class BulletSystem : MonoBehaviour
    {
        static BulletSystem _instance;

        public static BulletSystem Instance
        {
            get
            {
                if (_instance == null)
                {
                    _instance = FindFirstObjectByType<BulletSystem>();
                    if (_instance == null)
                    {
                        var go = new GameObject("BulletSystem");
                        _instance = go.AddComponent<BulletSystem>();
                    }
                }
                return _instance;
            }
        }

        [Tooltip("Sprite used for every pooled bullet. Assigned by NoxBootstrap "
                 + "at scene-build time; a runtime disc is generated if unset.")]
        public Sprite bulletSprite;

        [Tooltip("Bullets to pre-warm into the pool (SpawnPoint pool_amount). "
                 + "The pool grows past this if a volley needs more.")]
        public int prewarm = 64;

        /// <summary>
        /// Fired when a bullet strikes a registered body (the Unity port of
        /// BulletUpHell's bullet_collided_body). The player ship subscribes and
        /// applies damage; the bullet is despawned by the system on contact,
        /// mirroring the addon auto-despawning bullets that touch a "Player" body.
        /// </summary>
        public event Action<GameObject, BulletProps> BulletHitBody;

        /// <summary>Live bullet count — the port of Spawning.poolBullets.size().</summary>
        public int ActiveBulletCount => _active.Count;

        readonly Dictionary<string, BulletProps> _bulletDefs =
            new Dictionary<string, BulletProps>();
        readonly Dictionary<string, SpawnPattern> _patterns =
            new Dictionary<string, SpawnPattern>();

        readonly List<Bullet> _active = new List<Bullet>();
        readonly Stack<Bullet> _idle = new Stack<Bullet>();

        Transform _poolRoot;

        // The registered special target ("Player") — the port of
        // Spawning.edit_special_target. Bullets test against this transform.
        Transform _target;
        GameObject _targetBody;
        float _targetRadius;

        void Awake()
        {
            if (_instance != null && _instance != this)
            {
                Destroy(gameObject);
                return;
            }
            _instance = this;

            _poolRoot = new GameObject("BulletPool").transform;
            _poolRoot.SetParent(transform, false);

            if (bulletSprite == null)
                bulletSprite = GenerateDiscSprite();

            for (int i = 0; i < Mathf.Max(prewarm, 0); i++)
                _idle.Push(CreatePooledBullet());
        }

        void OnDestroy()
        {
            if (_instance == this)
                _instance = null;
        }

        // -------------------------------------------------------------------
        // id-keyed registration (BulletUpHell BulletProps / SpawnPattern nodes)
        // -------------------------------------------------------------------

        /// <summary>Register a bullet type by id (BuHBulletProperties node).</summary>
        public void RegisterBullet(BulletProps props)
        {
            if (props == null || string.IsNullOrEmpty(props.id))
                return;
            _bulletDefs[props.id] = props;
        }

        /// <summary>Register a spawn pattern by id (BuHPattern node).</summary>
        public void RegisterPattern(SpawnPattern pattern)
        {
            if (pattern == null || string.IsNullOrEmpty(pattern.id))
                return;
            _patterns[pattern.id] = pattern;
        }

        public SpawnPattern GetPattern(string id) =>
            _patterns.TryGetValue(id, out var p) ? p : null;

        public BulletProps GetBullet(string id) =>
            _bulletDefs.TryGetValue(id, out var b) ? b : null;

        // -------------------------------------------------------------------
        // special target (BulletUpHell edit_special_target)
        // -------------------------------------------------------------------

        /// <summary>
        /// Register the object bullets home to / collide with. Only the "Player"
        /// name is honored today (single special target), which is all the
        /// skeleton loop needs; the name argument keeps the signature parallel
        /// to Spawning.edit_special_target for when more targets are added.
        /// </summary>
        public void RegisterTarget(string targetName, Transform target, float radius)
        {
            if (targetName != "Player")
                return;
            _target = target;
            _targetBody = target != null ? target.gameObject : null;
            _targetRadius = radius;
        }

        public void UnregisterTarget(Transform target)
        {
            if (_target == target)
            {
                _target = null;
                _targetBody = null;
            }
        }

        // -------------------------------------------------------------------
        // emission (BulletUpHell SpawnPoint.spawn / pattern iteration)
        // -------------------------------------------------------------------

        /// <summary>
        /// Fire one volley of the named pattern from <paramref name="origin"/>.
        /// Returns the number of bullets emitted (0 if the pattern or its bullet
        /// id is unregistered).
        /// </summary>
        public int EmitVolley(string patternId, Vector2 origin)
        {
            if (!_patterns.TryGetValue(patternId, out var pattern))
                return 0;
            if (!_bulletDefs.TryGetValue(pattern.bulletId, out var props))
                return 0;

            int emitted = 0;
            int count = Mathf.Max(pattern.count, 0);
            for (int i = 0; i < count; i++)
            {
                // Evenly distribute bullets across angle_total. Matching the
                // addon's PatternCircle, a full 2*PI ring wraps seamlessly, so
                // divide by count (not count-1) to avoid a doubled bullet at
                // the seam; a partial fan divides by (count-1) to hit both ends.
                float t = FullCircle(pattern.angleTotal)
                    ? (float)i / count
                    : (count > 1 ? (float)i / (count - 1) : 0f);
                float angle = pattern.angleOffset + pattern.angleTotal * t;
                var dir = new Vector2(Mathf.Cos(angle), Mathf.Sin(angle));
                Vector2 spawnPos = origin + dir * pattern.spawnRadius;
                SpawnBullet(props, spawnPos, dir * props.speed);
                emitted++;
            }
            return emitted;
        }

        static bool FullCircle(float angleTotal) =>
            Mathf.Abs(Mathf.Abs(angleTotal) - Mathf.PI * 2f) < 0.001f;

        /// <summary>
        /// Spawn a single bullet with an explicit velocity (also the hook a
        /// custom pattern or a homing routine would call directly).
        /// </summary>
        public Bullet SpawnBullet(BulletProps props, Vector2 position, Vector2 velocity)
        {
            Bullet bullet = _idle.Count > 0 ? _idle.Pop() : CreatePooledBullet();
            bullet.Activate(props, position, velocity);
            _active.Add(bullet);
            return bullet;
        }

        // -------------------------------------------------------------------
        // central step (BulletUpHell processes all bullets from the autoload)
        // -------------------------------------------------------------------

        void FixedUpdate()
        {
            float delta = Time.fixedDeltaTime;

            // Iterate backwards so despawns (swap-remove) don't skip bullets.
            for (int i = _active.Count - 1; i >= 0; i--)
            {
                Bullet bullet = _active[i];
                bullet.Step(delta);

                bool dead = bullet.Age >= bullet.Props.lifeTime
                    || !bullet.Props.deathBox.Contains(bullet.Position);

                if (!dead && _target != null)
                {
                    float reach = bullet.Props.radius + _targetRadius;
                    if (((Vector2)_target.position - bullet.Position).sqrMagnitude
                        <= reach * reach)
                    {
                        // Contact: raise the collision event (player applies the
                        // damage on its side, gated by its own grace window) and
                        // despawn the bullet — the addon's touch-a-Player-body
                        // auto-despawn.
                        BulletHitBody?.Invoke(_targetBody, bullet.Props);
                        dead = true;
                    }
                }

                if (dead)
                {
                    Recycle(bullet);
                    _active.RemoveAt(i);
                }
            }
        }

        void Recycle(Bullet bullet)
        {
            bullet.Deactivate();
            _idle.Push(bullet);
        }

        Bullet CreatePooledBullet()
        {
            var go = new GameObject("Bullet");
            go.transform.SetParent(_poolRoot, false);
            var renderer = go.AddComponent<SpriteRenderer>();
            renderer.sprite = bulletSprite;
            renderer.sortingOrder = 4;
            var bullet = go.AddComponent<Bullet>();
            bullet.Bind(renderer);
            go.SetActive(false);
            return bullet;
        }

        /// <summary>
        /// Build a soft white disc sprite at runtime so bullets are visible even
        /// if the editor-assigned sprite reference is missing. Mirrors the
        /// texture NoxBootstrap bakes, but usable outside the editor.
        /// </summary>
        static Sprite GenerateDiscSprite()
        {
            const int size = 32;
            var texture = new Texture2D(size, size, TextureFormat.RGBA32, false)
            {
                filterMode = FilterMode.Bilinear,
                wrapMode = TextureWrapMode.Clamp,
            };
            float center = (size - 1) * 0.5f;
            float outer = center;
            var pixels = new Color32[size * size];
            for (int y = 0; y < size; y++)
            {
                for (int x = 0; x < size; x++)
                {
                    float dist = Mathf.Sqrt((x - center) * (x - center)
                        + (y - center) * (y - center));
                    // Soft edge over the outer 2px for a rounded bullet look.
                    float alpha = Mathf.Clamp01((outer - dist) / 2f);
                    pixels[y * size + x] = new Color(1f, 1f, 1f, alpha);
                }
            }
            texture.SetPixels32(pixels);
            texture.Apply();
            return Sprite.Create(texture, new Rect(0, 0, size, size),
                new Vector2(0.5f, 0.5f), size);
        }
    }
}
