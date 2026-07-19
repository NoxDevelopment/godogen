// Assets/Scripts/Spawner.cs
// Firing point — the Unity port of the Godot template's BuHSpawnPoint node. It
// owns the *timing* of a pattern (cooldown between volleys and the iteration
// count); BulletSystem owns the pooling and emission. Splitting it this way
// mirrors the addon: a SpawnPoint drives cadence, the Spawning autoload does
// the bullet work.
//
// Fires the first volley on its first physics tick (BulletUpHell cooldown_shoot
// = 0.0, auto_start_on_cam = false so it also runs headless), then one volley
// every pattern.cooldownSpawn seconds until the pattern's iteration budget runs
// out (-1 = forever).

using UnityEngine;

namespace NoxDev.BulletHell
{
    public sealed class Spawner : MonoBehaviour
    {
        [Tooltip("Pattern id to fire (BuHSpawnPoint auto_pattern_id).")]
        public string patternId = "ring";

        [Tooltip("Whether this spawner is currently firing (SpawnPoint active).")]
        public bool active = true;

        float _cooldownLeft;      // starts at 0 -> first volley fires immediately
        int _volleysLeft = -1;    // resolved from the pattern on first fire
        bool _initialized;

        /// <summary>True once the spawner is live and pointed at a real pattern —
        /// read by the arena boot probe to prove the loop is wired.</summary>
        public bool IsFiring =>
            active && !string.IsNullOrEmpty(patternId)
            && BulletSystem.Instance.GetPattern(patternId) != null;

        void FixedUpdate()
        {
            if (!active)
                return;

            SpawnPattern pattern = BulletSystem.Instance.GetPattern(patternId);
            if (pattern == null)
                return;

            if (!_initialized)
            {
                _volleysLeft = pattern.iterations; // -1 stays infinite
                _initialized = true;
            }

            if (_volleysLeft == 0)
            {
                active = false;
                return;
            }

            _cooldownLeft -= Time.fixedDeltaTime;
            if (_cooldownLeft > 0f)
                return;

            _cooldownLeft += Mathf.Max(pattern.cooldownSpawn, 0.0001f);
            BulletSystem.Instance.EmitVolley(patternId, transform.position);

            if (_volleysLeft > 0)
                _volleysLeft--;
        }
    }
}
