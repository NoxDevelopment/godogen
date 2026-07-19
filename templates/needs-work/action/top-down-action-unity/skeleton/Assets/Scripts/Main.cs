// Assets/Scripts/Main.cs
// Arena shell — C# port of the Godot template's main.gd: wires the player's
// health event and the targets' Destroyed events into the HUD, and emits the
// boot probe line that proves the core loop (player + shootable targets +
// chasing enemy) is alive.

using System.Collections;
using UnityEngine;
using UnityEngine.UI;

namespace NoxDev.TopDownAction
{
    public sealed class Main : MonoBehaviour
    {
        PlayerController _player;
        Enemy _enemy;
        Text _healthLabel;
        Text _targetsLabel;

        public int TargetsAlive =>
            FindObjectsByType<Target>(FindObjectsSortMode.None).Length;

        void Start()
        {
            _player = FindFirstObjectByType<PlayerController>();
            _enemy = FindFirstObjectByType<Enemy>();
            _healthLabel = FindLabel("HealthLabel");
            _targetsLabel = FindLabel("TargetsLabel");

            if (_player != null)
            {
                _player.HealthChanged += OnPlayerHealthChanged;
                OnPlayerHealthChanged(_player.Health, _player.maxHealth);
            }
            if (_enemy != null)
                _enemy.Destroyed += _ => RefreshTargetsLabelDeferred();
            foreach (var target in FindObjectsByType<Target>(FindObjectsSortMode.None))
                target.Destroyed += OnTargetDestroyed;
            RefreshTargetsLabel();

            StartCoroutine(EmitBootProbe());
        }

        void OnPlayerHealthChanged(int current, int maxHealth)
        {
            if (_healthLabel != null)
                _healthLabel.text = $"HP {current}/{maxHealth}";
        }

        void OnTargetDestroyed(Target target)
        {
            // The target is destroyed after raising the event; recount next frame.
            RefreshTargetsLabelDeferred();
        }

        void RefreshTargetsLabelDeferred()
        {
            StartCoroutine(RefreshNextFrame());
        }

        IEnumerator RefreshNextFrame()
        {
            yield return null;
            RefreshTargetsLabel();
        }

        void RefreshTargetsLabel()
        {
            if (_targetsLabel != null)
                _targetsLabel.text = $"Targets left: {TargetsAlive}";
        }

        IEnumerator EmitBootProbe()
        {
            // Give the enemy time to acquire its first chase target.
            for (int i = 0; i < 8; i++)
                yield return new WaitForFixedUpdate();
            bool playerOk = _player != null && _player.CompareTag("Player");
            bool enemyChasing = _enemy != null && _enemy.IsChasing;
            Debug.Log(
                "DEBUG: top-down-action core loop ready — "
                + $"player={(playerOk ? "true" : "false")} targets={TargetsAlive} "
                + $"enemy_chasing={(enemyChasing ? "true" : "false")}");
        }

        static Text FindLabel(string name)
        {
            foreach (var text in FindObjectsByType<Text>(
                         FindObjectsInactive.Include, FindObjectsSortMode.None))
            {
                if (text.name == name)
                    return text;
            }
            return null;
        }
    }
}
