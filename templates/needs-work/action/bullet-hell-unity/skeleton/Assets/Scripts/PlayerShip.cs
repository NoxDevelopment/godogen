// Assets/Scripts/PlayerShip.cs
// Bullet-hell player ship — C# port of the Godot template's player.gd:
// 8-directional movement clamped to the arena, a held-focus slowdown (the shmup
// precision-dodge staple), a deliberately small hurtbox, and lives with a
// post-hit invulnerability window and respawn at the start position.
//
// Collision comes from BulletSystem: the ship registers itself as the "Player"
// special target (the port of Spawning.edit_special_target) and subscribes to
// BulletHitBody (the port of Spawning.bullet_collided_body); the system despawns
// any bullet that reaches the hurtbox and this script applies the damage, gated
// by the grace window — byte-for-concept with player.gd.
//
// Input uses the Input System package via direct device polling (no
// .inputactions asset), matching the Unity lane's text-only-skeleton rule.

using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.InputSystem;

namespace NoxDev.BulletHell
{
    [RequireComponent(typeof(Rigidbody2D))]
    public sealed class PlayerShip : MonoBehaviour, IDamageable, ISaveable
    {
        public event Action<int, int> LivesChanged;
        public event Action Died;

        [Header("Movement")]
        [Tooltip("Normal flight speed, world units per second.")]
        public float moveSpeed = 7.0f;
        [Tooltip("Held-focus flight speed for precision dodging (shmup focus mode).")]
        public float focusSpeed = 3.0f;

        [Header("Lives")]
        public int maxLives = 3;
        [Tooltip("Seconds of invulnerability after losing a life.")]
        public float hurtGrace = 1.5f;

        [Header("Hurtbox")]
        [Tooltip("Radius of the (small!) hurtbox, world units. The system tests "
                 + "bullet contact against this — the classic tiny shmup hitbox.")]
        public float hurtboxRadius = 0.12f;

        [Header("Arena clamp (matches the walled playfield)")]
        public Vector2 clampMin = new Vector2(-8.6f, -4.6f);
        public Vector2 clampMax = new Vector2(8.6f, 4.6f);

        public int Lives { get; private set; }

        Rigidbody2D _body;
        SpriteRenderer _shipVisual;
        Color _baseColor;
        Vector2 _spawnPosition;

        Vector2 _moveAxis;
        bool _focusHeld;
        float _graceLeft;

        void Awake()
        {
            _body = GetComponent<Rigidbody2D>();
            _body.gravityScale = 0f;
            _body.freezeRotation = true;
            _body.bodyType = RigidbodyType2D.Kinematic;
            _body.interpolation = RigidbodyInterpolation2D.Interpolate;

            // Node lookup mirrors the Godot scene's $Visual.
            var visualNode = transform.Find("Visual");
            _shipVisual = visualNode != null
                ? visualNode.GetComponent<SpriteRenderer>()
                : null;
            _baseColor = _shipVisual != null ? _shipVisual.color : Color.white;

            _spawnPosition = _body.position;
            Lives = maxLives;
        }

        void Start()
        {
            BulletSystem.Instance.RegisterTarget("Player", transform, hurtboxRadius);
            BulletSystem.Instance.BulletHitBody += OnBulletHitBody;
            LivesChanged?.Invoke(Lives, maxLives);
        }

        void OnDestroy()
        {
            var system = BulletSystem.Instance;
            if (system != null)
            {
                system.BulletHitBody -= OnBulletHitBody;
                system.UnregisterTarget(transform);
            }
        }

        void Update()
        {
            // ---- read input (Input System device polling; no .inputactions) ----
            _moveAxis = Vector2.zero;
            _focusHeld = false;

            var keyboard = Keyboard.current;
            if (keyboard != null)
            {
                if (keyboard.aKey.isPressed || keyboard.leftArrowKey.isPressed) _moveAxis.x -= 1f;
                if (keyboard.dKey.isPressed || keyboard.rightArrowKey.isPressed) _moveAxis.x += 1f;
                if (keyboard.sKey.isPressed || keyboard.downArrowKey.isPressed) _moveAxis.y -= 1f;
                if (keyboard.wKey.isPressed || keyboard.upArrowKey.isPressed) _moveAxis.y += 1f;
                if (keyboard.spaceKey.isPressed || keyboard.leftShiftKey.isPressed)
                    _focusHeld = true;
            }
            var gamepad = Gamepad.current;
            if (gamepad != null)
            {
                var stick = gamepad.leftStick.ReadValue();
                if (stick.sqrMagnitude > 0.04f) _moveAxis = stick;
                var dpad = gamepad.dpad.ReadValue();
                if (dpad.sqrMagnitude > 0.04f) _moveAxis = dpad;
                if (gamepad.buttonSouth.isPressed) _focusHeld = true;
            }

            // ---- post-hit blink (visual only; runs off frame time) ----
            if (_graceLeft > 0f && _shipVisual != null)
            {
                float a = ((int)(_graceLeft * 12f) % 2 == 0) ? 0.4f : 0.9f;
                var c = _shipVisual.color;
                c.a = a;
                _shipVisual.color = c;
            }
        }

        void FixedUpdate()
        {
            float delta = Time.fixedDeltaTime;

            if (_graceLeft > 0f)
            {
                _graceLeft = Mathf.Max(_graceLeft - delta, 0f);
                if (_graceLeft <= 0f && _shipVisual != null)
                {
                    var c = _shipVisual.color;
                    c.a = 1f;
                    _shipVisual.color = c;
                }
            }

            Vector2 axis = _moveAxis.sqrMagnitude > 1f ? _moveAxis.normalized : _moveAxis;
            float speed = _focusHeld ? focusSpeed : moveSpeed;
            Vector2 target = _body.position + axis * speed * delta;
            target.x = Mathf.Clamp(target.x, clampMin.x, clampMax.x);
            target.y = Mathf.Clamp(target.y, clampMin.y, clampMax.y);
            _body.MovePosition(target);
        }

        // -------------------------------------------------------------------
        // damage (take_hit contract) + BulletSystem collision callback
        // -------------------------------------------------------------------

        void OnBulletHitBody(GameObject body, BulletProps props)
        {
            if (body == gameObject)
                TakeHit(props != null ? props.damage : 1, null);
        }

        public void TakeHit(int damage, GameObject from)
        {
            if (_graceLeft > 0f)
                return;
            _graceLeft = hurtGrace;
            Lives = Mathf.Max(Lives - damage, 0);
            LivesChanged?.Invoke(Lives, maxLives);
            if (Lives <= 0)
                Die();
        }

        void Die()
        {
            Died?.Invoke();
            // Classic shmup respawn: back to the start with full lives.
            _body.position = _spawnPosition;
            transform.position = _spawnPosition;
            Lives = maxLives;
            _graceLeft = hurtGrace;
            LivesChanged?.Invoke(Lives, maxLives);
        }

        // -------------------------------------------------------------------
        // ISaveable — mirrors player.gd's save_data()/load_data() contract.
        // {"position": {"x","y"}, "lives": N}
        // -------------------------------------------------------------------

        public string SaveKey => "player";

        public Dictionary<string, object> SaveData()
        {
            return new Dictionary<string, object>
            {
                ["position"] = new Dictionary<string, object>
                {
                    ["x"] = (double)_body.position.x,
                    ["y"] = (double)_body.position.y,
                },
                ["lives"] = Lives,
            };
        }

        public void LoadData(Dictionary<string, object> data)
        {
            if (data == null)
                return;
            if (data.TryGetValue("lives", out var rawLives))
                Lives = Mathf.Clamp(Convert.ToInt32(rawLives), 0, maxLives);
            LivesChanged?.Invoke(Lives, maxLives);
            if (data.TryGetValue("position", out var rawPos)
                && rawPos is Dictionary<string, object> pos
                && pos.TryGetValue("x", out var x) && pos.TryGetValue("y", out var y))
            {
                var restored = new Vector2(Convert.ToSingle(x), Convert.ToSingle(y));
                _body.position = restored;
                transform.position = restored;
            }
        }
    }
}
