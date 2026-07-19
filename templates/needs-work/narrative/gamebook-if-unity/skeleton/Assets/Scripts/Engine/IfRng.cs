// Assets/Scripts/Engine/IfRng.cs
// Deterministic, seedable PRNG for the Nox Loom IF engine (Unity C# port of the
// nox_if_engine). Replaces Godot's RandomNumberGenerator with a self-contained
// xorshift64* so the C# engine is reproducible on its own terms: same seed +
// same call sequence => same run (the determinism the probes assert). Not
// byte-identical to the GDScript engine — cross-engine parity is not required;
// each engine is internally deterministic.
namespace NoxIfEngine
{
    public sealed class IfRng
    {
        private ulong _state;

        public IfRng(long seed = 0) => SetSeed(seed);

        public void SetSeed(long seed)
        {
            // Splitmix-style seeding so seed 0 (and small seeds) still spread well.
            _state = unchecked((ulong)seed * 2685821657736338717UL + 1442695040888963407UL);
            if (_state == 0UL) _state = 0x9E3779B97F4A7C15UL;
        }

        /// <summary>The full internal state, for save/snapshot.</summary>
        public ulong GetState() => _state;

        /// <summary>Restore a previously captured state (0 is coerced to a safe seed).</summary>
        public void SetState(ulong s) => _state = s == 0UL ? 0x9E3779B97F4A7C15UL : s;

        private ulong NextU64()
        {
            unchecked
            {
                _state ^= _state >> 12;
                _state ^= _state << 25;
                _state ^= _state >> 27;
                return _state * 0x2545F4914F6CDD1DUL;
            }
        }

        /// <summary>Inclusive integer in [a, b] (order-tolerant), matching GDScript randi_range.</summary>
        public int RangeInclusive(int a, int b)
        {
            if (b < a) { (a, b) = (b, a); }
            ulong span = (ulong)(b - a + 1);
            return a + (int)(NextU64() % span);
        }
    }
}
