// Assets/Scripts/GameManager.cs
// NoxDev ABI singleton for the Unity gamebook. Mirrors the Godot templates'
// game_manager autoload contract: a persistent singleton holding world flags +
// JSON save/load (the ISaveable save_data() analogue). The gamebook's own run
// state lives in the IFRunner (engine); this manager owns cross-run/world data
// and the save file, exactly like the other NoxDev templates.
using System.Collections.Generic;
using System.IO;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using UnityEngine;

namespace NoxDev.GamebookIf
{
    /// <summary>Anything that contributes to / restores from the JSON save blob.</summary>
    public interface ISaveable
    {
        string SaveKey { get; }
        JObject SaveData();
        void LoadData(JObject data);
    }

    public sealed class GameManager : MonoBehaviour
    {
        public static GameManager Instance { get; private set; }

        readonly Dictionary<string, JToken> _worldFlags = new Dictionary<string, JToken>();
        readonly List<ISaveable> _saveables = new List<ISaveable>();

        string SavePath => Path.Combine(Application.persistentDataPath, "gamebook_save.json");

        void Awake()
        {
            if (Instance != null && Instance != this) { Destroy(gameObject); return; }
            Instance = this;
            DontDestroyOnLoad(gameObject);
        }

        public void Register(ISaveable s)
        {
            if (!_saveables.Contains(s)) _saveables.Add(s);
        }

        public void SetFlag(string key, JToken value) => _worldFlags[key] = value;
        public JToken GetFlag(string key, JToken fallback = null) =>
            _worldFlags.TryGetValue(key, out var v) ? v : fallback;

        /// <summary>Assemble the full save blob (world flags + every registered saveable).</summary>
        public JObject SaveData()
        {
            var flags = new JObject();
            foreach (var kv in _worldFlags) flags[kv.Key] = kv.Value;
            var parts = new JObject();
            foreach (var s in _saveables) parts[s.SaveKey] = s.SaveData();
            return new JObject { ["version"] = 1, ["worldFlags"] = flags, ["parts"] = parts };
        }

        public void LoadData(JObject data)
        {
            if (data == null) return;
            _worldFlags.Clear();
            if (data["worldFlags"] is JObject wf)
                foreach (var p in wf) _worldFlags[p.Key] = p.Value;
            if (data["parts"] is JObject parts)
                foreach (var s in _saveables)
                    if (parts[s.SaveKey] is JObject pd) s.LoadData(pd);
        }

        public void SaveToDisk() =>
            File.WriteAllText(SavePath, SaveData().ToString(Formatting.Indented));

        public bool LoadFromDisk()
        {
            if (!File.Exists(SavePath)) return false;
            LoadData(JObject.Parse(File.ReadAllText(SavePath)));
            return true;
        }
    }
}
