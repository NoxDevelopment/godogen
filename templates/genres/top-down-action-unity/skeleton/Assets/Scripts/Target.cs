// Assets/Scripts/Target.cs
// Shootable practice dummy — C# port of the Godot template's target.gd. Takes
// hitscan damage from the player, flashes on hit, and destroys itself when
// depleted, incrementing GameManager's "targets_destroyed" flag. The arena
// counts survivors by Main.TargetsAlive (the analogue of the "targets" group).

using System;
using UnityEngine;

namespace NoxDev.TopDownAction
{
    public sealed class Target : MonoBehaviour, IDamageable
    {
        public event Action<Target> Destroyed;

        public int maxHealth = 3;

        public int Health { get; private set; }

        SpriteRenderer _visual;
        Color _baseColor;
        float _flashLeft;

        void Awake()
        {
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
                var manager = GameManager.Instance;
                manager.SetFlag(
                    "targets_destroyed", manager.GetIntFlag("targets_destroyed") + 1);
                Destroyed?.Invoke(this);
                Destroy(gameObject);
            }
        }
    }
}
