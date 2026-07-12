// Assets/Scripts/PlayerController.cs
// Top-down action controller — C# port of the Godot template's player.gd:
// 8-directional movement (accelerate/friction), mouse aim (the AimPivot barrel
// tracks the cursor), hitscan raycast shot with a visible LineRenderer tracer
// and fire-rate cooldown, dash (burst + cooldown, i-frames while dashing),
// health with a post-hit grace window and respawn at the spawn point.
//
// Uses the Input System package (com.unity.inputsystem) via direct device
// polling — no .inputactions asset, so the skeleton stays fully text-authored.

using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.InputSystem;

namespace NoxDev.TopDownAction
{
    [RequireComponent(typeof(Rigidbody2D))]
    public sealed class PlayerController : MonoBehaviour, IDamageable, ISaveable
    {
        public event Action<int, int> HealthChanged;
        public event Action<Vector2, Vector2, GameObject> ShotFired;
        public event Action Died;

        [Header("Movement")]
        public float moveSpeed = 6.0f;
        public float acceleration = 50.0f;
        public float friction = 42.0f;

        [Header("Health")]
        public int maxHealth = 5;
        [Tooltip("Seconds of invulnerability after taking a hit.")]
        public float hurtGrace = 0.5f;

        [Header("Hitscan shot")]
        [Tooltip("Hitscan range of one shot, in world units.")]
        public float shotRange = 18.0f;
        public int shotDamage = 1;
        public float shotCooldown = 0.18f;

        [Header("Dash")]
        public float dashSpeed = 17.0f;
        public float dashDuration = 0.15f;
        public float dashCooldown = 0.6f;

        public int Health { get; private set; }

        static readonly Color BodyColor = new Color(0.909804f, 0.768627f, 0.419608f);
        static readonly Color HurtColor = new Color(1.0f, 0.35f, 0.35f);

        Rigidbody2D _body;
        Transform _aimPivot;
        Transform _muzzle;
        LineRenderer _tracer;
        SpriteRenderer _bodyVisual;
        Camera _camera;

        Vector2 _spawnPosition;
        Vector2 _moveAxis;
        bool _dashQueued;
        bool _firePressed;
        float _shotCdLeft;
        float _dashCdLeft;
        float _dashLeft;
        Vector2 _dashDir;
        float _graceLeft;
        float _tracerLeft;
        float _flashLeft;

        public bool IsDashing => _dashLeft > 0.0f;

        void Awake()
        {
            _body = GetComponent<Rigidbody2D>();
            _body.gravityScale = 0.0f;
            _body.freezeRotation = true;

            // Node lookups mirror the Godot scene's $AimPivot/$Muzzle/$Tracer/$Body.
            _aimPivot = transform.Find("AimPivot");
            _muzzle = transform.Find("AimPivot/Muzzle");
            var tracerNode = transform.Find("Tracer");
            _tracer = tracerNode != null ? tracerNode.GetComponent<LineRenderer>() : null;
            var bodyNode = transform.Find("Body");
            _bodyVisual = bodyNode != null ? bodyNode.GetComponent<SpriteRenderer>() : null;

            _camera = Camera.main;
            _spawnPosition = _body.position;
            Health = maxHealth;

            if (_tracer != null)
                _tracer.enabled = false;
        }

        void Start()
        {
            HealthChanged?.Invoke(Health, maxHealth);
        }

        void Update()
        {
            var keyboard = Keyboard.current;
            var mouse = Mouse.current;

            // 8-directional movement axis (WASD + arrows), normalized in FixedUpdate.
            _moveAxis = Vector2.zero;
            if (keyboard != null)
            {
                if (keyboard.aKey.isPressed || keyboard.leftArrowKey.isPressed) _moveAxis.x -= 1f;
                if (keyboard.dKey.isPressed || keyboard.rightArrowKey.isPressed) _moveAxis.x += 1f;
                if (keyboard.sKey.isPressed || keyboard.downArrowKey.isPressed) _moveAxis.y -= 1f;
                if (keyboard.wKey.isPressed || keyboard.upArrowKey.isPressed) _moveAxis.y += 1f;
                if (keyboard.spaceKey.wasPressedThisFrame) _dashQueued = true;
            }
            var gamepad = Gamepad.current;
            if (gamepad != null)
            {
                var stick = gamepad.leftStick.ReadValue();
                if (stick.sqrMagnitude > 0.04f) _moveAxis = stick;
                if (gamepad.buttonEast.wasPressedThisFrame) _dashQueued = true;
            }

            _firePressed = (mouse != null && mouse.leftButton.isPressed)
                || (gamepad != null && gamepad.rightTrigger.ReadValue() > 0.5f);

            // Mouse aim: the pivot (barrel + muzzle) tracks the cursor.
            if (_aimPivot != null && mouse != null && _camera != null)
            {
                Vector3 cursor = _camera.ScreenToWorldPoint(mouse.position.ReadValue());
                Vector2 toCursor = (Vector2)cursor - _body.position;
                if (toCursor.sqrMagnitude > 0.0001f)
                {
                    float angle = Mathf.Atan2(toCursor.y, toCursor.x) * Mathf.Rad2Deg;
                    _aimPivot.rotation = Quaternion.Euler(0f, 0f, angle);
                }
            }

            UpdateTracer(Time.deltaTime);
            UpdateFlash(Time.deltaTime);
        }

        void FixedUpdate()
        {
            float delta = Time.fixedDeltaTime;
            _shotCdLeft = Mathf.Max(_shotCdLeft - delta, 0.0f);
            _dashCdLeft = Mathf.Max(_dashCdLeft - delta, 0.0f);
            _graceLeft = Mathf.Max(_graceLeft - delta, 0.0f);

            Vector2 axis = _moveAxis.sqrMagnitude > 1.0f ? _moveAxis.normalized : _moveAxis;

            // Dash: burst along the movement direction (aim direction when standing still).
            if (_dashQueued && _dashCdLeft <= 0.0f)
            {
                _dashDir = axis != Vector2.zero
                    ? axis.normalized
                    : (_aimPivot != null ? (Vector2)_aimPivot.right : Vector2.right);
                _dashLeft = dashDuration;
                _dashCdLeft = dashCooldown;
            }
            _dashQueued = false;

            if (_dashLeft > 0.0f)
            {
                _dashLeft -= delta;
                _body.linearVelocity = _dashDir * dashSpeed;
            }
            else if (axis != Vector2.zero)
            {
                _body.linearVelocity = Vector2.MoveTowards(
                    _body.linearVelocity, axis * moveSpeed, acceleration * delta);
            }
            else
            {
                _body.linearVelocity = Vector2.MoveTowards(
                    _body.linearVelocity, Vector2.zero, friction * delta);
            }

            if (_firePressed && _shotCdLeft <= 0.0f)
                Shoot();
        }

        public void TakeHit(int damage, GameObject from)
        {
            if (_graceLeft > 0.0f || IsDashing)
                return;
            _graceLeft = hurtGrace;
            Health = Mathf.Max(Health - damage, 0);
            HealthChanged?.Invoke(Health, maxHealth);
            Flash(HurtColor);
            if (Health <= 0)
                Die();
        }

        // ISaveable — mirrors player.gd's save_data()/load_data() contract.
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
                ["health"] = Health,
            };
        }

        public void LoadData(Dictionary<string, object> data)
        {
            if (data == null)
                return;
            if (data.TryGetValue("health", out var rawHealth))
                Health = Mathf.Clamp(Convert.ToInt32(rawHealth), 0, maxHealth);
            HealthChanged?.Invoke(Health, maxHealth);
            if (data.TryGetValue("position", out var rawPos)
                && rawPos is Dictionary<string, object> pos
                && pos.TryGetValue("x", out var x) && pos.TryGetValue("y", out var y))
            {
                var restored = new Vector2(
                    Convert.ToSingle(x), Convert.ToSingle(y));
                _body.position = restored;
                transform.position = restored;
            }
        }

        void Shoot()
        {
            _shotCdLeft = shotCooldown;
            Vector2 from = _muzzle != null ? (Vector2)_muzzle.position : _body.position;
            Vector2 dir = _aimPivot != null ? (Vector2)_aimPivot.right : Vector2.right;
            Vector2 to = from + dir * shotRange;

            // Hitscan against everything except ourselves (walls stop the ray;
            // the first IDamageable hit takes the damage).
            GameObject hitObject = null;
            var hits = Physics2D.RaycastAll(from, dir, shotRange);
            foreach (var hit in hits)
            {
                if (hit.collider == null || hit.collider.transform.IsChildOf(transform))
                    continue;
                to = hit.point;
                hitObject = hit.collider.gameObject;
                var damageable = hit.collider.GetComponentInParent<IDamageable>();
                if (damageable != null && !ReferenceEquals(damageable, this))
                    damageable.TakeHit(shotDamage, gameObject);
                break;
            }

            if (_tracer != null)
            {
                _tracer.positionCount = 2;
                _tracer.SetPosition(0, from);
                _tracer.SetPosition(1, to);
                _tracer.enabled = true;
                _tracerLeft = 0.06f;
            }
            ShotFired?.Invoke(from, to, hitObject);
        }

        void UpdateTracer(float delta)
        {
            if (_tracer == null || !_tracer.enabled)
                return;
            _tracerLeft -= delta;
            if (_tracerLeft <= 0.0f)
                _tracer.enabled = false;
        }

        void Flash(Color color)
        {
            if (_bodyVisual == null)
                return;
            _bodyVisual.color = color;
            _flashLeft = 0.25f;
        }

        void UpdateFlash(float delta)
        {
            if (_bodyVisual == null || _flashLeft <= 0.0f)
                return;
            _flashLeft = Mathf.Max(_flashLeft - delta, 0.0f);
            _bodyVisual.color = Color.Lerp(
                _bodyVisual.color, BodyColor, 1.0f - _flashLeft / 0.25f);
            if (_flashLeft <= 0.0f)
                _bodyVisual.color = BodyColor;
        }

        void Die()
        {
            Died?.Invoke();
            // Respawn at the arena spawn point with full health.
            _body.position = _spawnPosition;
            transform.position = _spawnPosition;
            _body.linearVelocity = Vector2.zero;
            Health = maxHealth;
            _graceLeft = hurtGrace;
            HealthChanged?.Invoke(Health, maxHealth);
        }
    }
}
