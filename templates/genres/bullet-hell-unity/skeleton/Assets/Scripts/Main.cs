// Assets/Scripts/Main.cs
// Arena shell — C# port of the Godot template's main.gd: wires the player's
// lives event and the live bullet count into the HUD, and emits the boot probe
// line proving the core loop (spawner firing, live bullets in the pool, player
// ship) is running.

using System.Collections;
using UnityEngine;
using UnityEngine.UI;

namespace NoxDev.BulletHell
{
    public sealed class Main : MonoBehaviour
    {
        PlayerShip _player;
        Spawner _spawner;
        Text _livesLabel;
        Text _bulletsLabel;

        void Start()
        {
            _player = FindFirstObjectByType<PlayerShip>();
            _spawner = FindFirstObjectByType<Spawner>();
            _livesLabel = FindLabel("LivesLabel");
            _bulletsLabel = FindLabel("BulletsLabel");

            if (_player != null)
            {
                _player.LivesChanged += OnPlayerLivesChanged;
                OnPlayerLivesChanged(_player.Lives, _player.maxLives);
            }

            StartCoroutine(EmitBootProbe());
        }

        void Update()
        {
            if (_bulletsLabel != null)
                _bulletsLabel.text = $"Bullets: {BulletSystem.Instance.ActiveBulletCount}";
        }

        void OnPlayerLivesChanged(int current, int maxLives)
        {
            if (_livesLabel != null)
                _livesLabel.text = $"Lives {current}/{maxLives}";
        }

        IEnumerator EmitBootProbe()
        {
            // Let the spawner fire its first ring volley (fires on its first
            // physics tick; wait well under the 0.8s volley cadence so exactly
            // one ring — 12 bullets — is live, mirroring the Godot probe).
            for (int i = 0; i < 20; i++)
                yield return new WaitForFixedUpdate();

            bool spawnerOk = _spawner != null && _spawner.IsFiring;
            bool playerOk = _player != null && _player.CompareTag("Player");
            Debug.Log(
                "DEBUG: bullet-hell core loop ready — "
                + $"spawner={(spawnerOk ? "true" : "false")} "
                + $"player={(playerOk ? "true" : "false")} "
                + $"active_bullets={BulletSystem.Instance.ActiveBulletCount}");
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
