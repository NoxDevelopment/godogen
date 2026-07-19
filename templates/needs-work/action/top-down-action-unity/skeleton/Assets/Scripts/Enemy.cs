// Assets/Scripts/Enemy.cs
// Chaser enemy — C# port of the Godot template's enemy.gd. Steers directly at
// the player (re-querying the chase target on a short timer) and deals contact
// damage with a cooldown when it reaches them. Shootable (IDamageable).
//
// Engine note: the Godot template paths with NavigationAgent2D over a
// NavigationRegion2D. Unity has no first-party 2D navmesh (NavMesh is 3D;
// NavMeshPlus is third-party), so the skeleton uses direct seek steering —
// correct for an open arena. For walled interiors, swap ChaseDirection() for
// A* over a Tilemap or vendor a 2D navigation package.

using System;
using UnityEngine;

namespace NoxDev.TopDownAction
{
    [RequireComponent(typeof(Rigidbody2D))]
    public sealed class Enemy : MonoBehaviour, IDamageable
    {
        public event Action<Enemy> Destroyed;

        public float moveSpeed = 3.4f;
        public int maxHealth = 5;
        public int contactDamage = 1;
        public float contactRange = 0.75f;
        public float contactCooldown = 0.8f;
        [Tooltip("How often the chase target is re-queried, in seconds.")]
        public float repathInterval = 0.25f;

        public int Health { get; private set; }

        Rigidbody2D _body;
        SpriteRenderer _visual;
        Color _baseColor;
        PlayerController _player;
        Vector2 _chaseTarget;
        bool _hasTarget;
        float _repathLeft;
        float _contactCdLeft;
        float _flashLeft;

        /// <summary>
        /// True once the enemy holds a live chase target (used by the arena's
        /// boot probe to prove the chase loop is running).
        /// </summary>
        public bool IsChasing => _hasTarget;

        void Awake()
        {
            _body = GetComponent<Rigidbody2D>();
            _body.gravityScale = 0.0f;
            _body.freezeRotation = true;

            var visualNode = transform.Find("Visual");
            _visual = visualNode != null ? visualNode.GetComponent<SpriteRenderer>() : null;
            _baseColor = _visual != null ? _visual.color : Color.white;

            Health = maxHealth;
        }

        void Update()
        {
            if (_visual != null && _flashLeft > 0.0f)
            {
                _flashLeft = Mathf.Max(_flashLeft - Time.deltaTime, 0.0f);
                _visual.color = Color.Lerp(Color.white, _baseColor, 1.0f - _flashLeft / 0.15f);
                if (_flashLeft <= 0.0f)
                    _visual.color = _baseColor;
            }
        }

        void FixedUpdate()
        {
            float delta = Time.fixedDeltaTime;
            _contactCdLeft = Mathf.Max(_contactCdLeft - delta, 0.0f);

            if (_player == null)
            {
                _player = FindFirstObjectByType<PlayerController>();
                if (_player == null)
                {
                    _hasTarget = false;
                    _body.linearVelocity = Vector2.MoveTowards(
                        _body.linearVelocity, Vector2.zero, moveSpeed * 8.0f * delta);
                    return;
                }
            }

            _repathLeft -= delta;
            if (_repathLeft <= 0.0f)
            {
                _repathLeft = repathInterval;
                _chaseTarget = _player.transform.position;
                _hasTarget = true;
            }

            Vector2 toTarget = _chaseTarget - _body.position;
            if (toTarget.magnitude <= 0.05f)
            {
                _body.linearVelocity = Vector2.MoveTowards(
                    _body.linearVelocity, Vector2.zero, moveSpeed * 8.0f * delta);
            }
            else
            {
                _body.linearVelocity = toTarget.normalized * moveSpeed;
            }

            Vector2 toPlayer = (Vector2)_player.transform.position - _body.position;
            if (_contactCdLeft <= 0.0f && toPlayer.magnitude <= contactRange)
            {
                _contactCdLeft = contactCooldown;
                _player.TakeHit(contactDamage, gameObject);
            }
        }

        public void TakeHit(int damage, GameObject from)
        {
            Health = Mathf.Max(Health - damage, 0);
            if (_visual != null)
            {
                _visual.color = Color.white;
                _flashLeft = 0.15f;
            }
            if (Health <= 0)
            {
                Destroyed?.Invoke(this);
                Destroy(gameObject);
            }
        }
    }
}
