# Audio Pipeline

All-in-one audio generation: procedural sound effects, scale-aware music, and TTS speech via local providers (Kokoro → Orpheus → EdgeTTS fallback chain). **All free, all local.**

## TL;DR

```bash
python3 .claude/skills/audio-pipeline/tools/audio_gen.py {command} [options]
```

Three commands: `sfx`, `music`, `speech`. All output `.wav` files Godot imports natively.

## Sound Effects (procedural — instant, free)

20+ built-in SFX types generated from oscillators + ADSR envelopes. No model, no GPU, no API call — pure DSP.

```bash
python3 .claude/skills/audio-pipeline/tools/audio_gen.py sfx \
  --type explosion -o assets/audio/explosion.wav
```

**Types**: `explosion`, `laser`, `coin`, `jump`, `hit`, `damage`, `powerup`, `whoosh`, `footstep`, `door`, `pickup`, `click`, `notification`, `error`, `success`, `swoosh`, `chime`, `static`, `engine`, `step_metal`, `step_wood`, `step_grass`.

Each type accepts `--pitch`, `--duration`, `--reverb` to vary instances. Generate **multiple variants per SFX** (different pitch / duration) so the in-game playback isn't repetitive — Godot can pick a random variant on each trigger.

## Music (scale-aware procedural)

Generate ambient or themed loops with chord progression + melody on top.

```bash
python3 .claude/skills/audio-pipeline/tools/audio_gen.py music \
  --mood {ambient|tense|heroic|playful|melancholy|chaotic} \
  --duration 30 --bpm 120 --key C --scale major \
  -o assets/audio/title_theme.wav
```

For a full game, generate at least:
- **Title screen** loop (~30s, distinct mood)
- **Gameplay** loop (~60s, fits the genre's energy)
- **Menu / pause** ambient (~20s, low intensity)
- **Game over** sting (~5s, one-shot)

## Speech / TTS (provider chain)

Provider order (auto-fallback if a service is unreachable):

1. **Orpheus** at `$ORPHEUS_URL` (default `http://localhost:5005`) — emotion-tagged, expressive
2. **Kokoro** at `$KOKORO_URL` (default `http://localhost:8880`) — clean neutral voices
3. **EdgeTTS** — final fallback, requires Microsoft Edge runtime

```bash
python3 .claude/skills/audio-pipeline/tools/audio_gen.py speech \
  --text "Welcome to the dungeon, adventurer." \
  --voice af_bella \
  -o assets/audio/intro.wav
```

### Voices (Kokoro)

`af_bella`, `af_emma`, `af_nicole`, `af_sarah` (female), `am_adam`, `am_michael` (male). Pick one per character and stick with it for consistency.

### Voice mapping per character

When generating dialog for multiple NPCs, build a voice map at the start of the project and reuse it:

```markdown
# Voice cast (in ASSETS.md)
- Player narrator → af_bella
- Shopkeeper Mira → af_emma
- Captain Vex → am_adam
- Old wizard → am_michael (Orpheus, slow tempo)
```

### Emotion (Orpheus only)

```bash
python3 .claude/skills/audio-pipeline/tools/audio_gen.py speech \
  --text "We won't make it out of here alive!" \
  --voice am_adam --emotion fearful \
  --backend orpheus \
  -o assets/audio/vex_panic.wav
```

Emotions: `neutral`, `happy`, `sad`, `fearful`, `angry`, `surprised`, `whisper`, `excited`. Falls back to neutral if unsupported by the active backend.

## When to invoke each

| Need | Tool |
|---|---|
| One-off zap / hit / pickup feedback | `sfx` |
| Repeated environmental noise (engine, ambient) | `sfx` with `--loop` flag (looping enabled by default for `engine`/`static`) |
| Background music | `music` |
| Character voice line | `speech` |
| Title screen narration | `speech` with slower `--rate 0.85` |
| In-game tutorial voiceover | `speech`, then chunk into per-line files |

## Output format

JSON to stdout: `{"ok": true, "path": "assets/audio/x.wav", "backend": "kokoro", "cost_cents": 0}`

## What NOT to do

- ❌ Don't generate a single 90-second SFX file — split into discrete WAVs Godot can play independently
- ❌ Don't TTS the same line twice with different voices "to compare" — pick the voice up front from the cast map
- ❌ Don't use Orpheus emotion tags in Kokoro calls — Kokoro silently ignores them; check `backend` in the JSON output

## Verification

After generating a batch of SFX, listen to a sample (or visualize the waveform) — procedural SFX can clip if `--pitch` is too aggressive. The `--normalize` flag (default on) prevents clipping but can flatten dynamics; pass `--no-normalize` for raw output if you want it punchier.
