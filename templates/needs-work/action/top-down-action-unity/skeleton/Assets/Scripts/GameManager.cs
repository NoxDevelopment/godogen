// Assets/Scripts/GameManager.cs
// Global game state singleton. Carries world flags (targets destroyed, doors
// opened, events fired) and owns JSON save/load. This is the Unity port of the
// NoxDev template ABI's "game_manager" autoload: anything that persists
// implements ISaveable (the analogue of the "persistent" group's
// save_data()/load_data() contract) and GameManager gathers them all into one
// JSON document, flags included.

using System.Collections.Generic;
using System.IO;
using System.Linq;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using UnityEngine;

namespace NoxDev.TopDownAction
{
    /// <summary>
    /// The "persistent" group contract from the NoxDev template ABI, in C#.
    /// Godot: nodes join the "persistent" group and implement
    /// save_data() -> Dictionary / load_data(data). Unity: MonoBehaviours
    /// implement ISaveable; GameManager finds them all at save/load time.
    /// </summary>
    public interface ISaveable
    {
        /// <summary>Stable key for this object's slot in the save document.</summary>
        string SaveKey { get; }

        Dictionary<string, object> SaveData();

        void LoadData(Dictionary<string, object> data);
    }

    /// <summary>
    /// The take_hit(damage, from) damage contract shared by everything
    /// shootable (player, enemies, targets, future destructibles).
    /// </summary>
    public interface IDamageable
    {
        void TakeHit(int damage, GameObject from);
    }

    public sealed class GameManager : MonoBehaviour, ISaveable
    {
        static GameManager _instance;

        /// <summary>
        /// Singleton accessor. Auto-creates the manager if the scene does not
        /// contain one, so scripts can rely on it unconditionally.
        /// </summary>
        public static GameManager Instance
        {
            get
            {
                if (_instance == null)
                {
                    _instance = FindFirstObjectByType<GameManager>();
                    if (_instance == null)
                    {
                        var go = new GameObject("GameManager");
                        _instance = go.AddComponent<GameManager>();
                    }
                }
                return _instance;
            }
        }

        /// <summary>World flags: targets destroyed, doors opened, events fired.</summary>
        readonly Dictionary<string, object> _flags = new Dictionary<string, object>();

        public string SaveKey => "game_manager";

        public string DefaultSavePath =>
            Path.Combine(Application.persistentDataPath, "save.json");

        void Awake()
        {
            if (_instance != null && _instance != this)
            {
                Destroy(gameObject);
                return;
            }
            _instance = this;
            DontDestroyOnLoad(gameObject);
        }

        void OnDestroy()
        {
            if (_instance == this)
                _instance = null;
        }

        // -------------------------------------------------------------------
        // Flags
        // -------------------------------------------------------------------

        public void SetFlag(string flag, object value)
        {
            _flags[flag] = value;
        }

        public void SetFlag(string flag)
        {
            _flags[flag] = true;
        }

        public object GetFlag(string flag, object defaultValue = null)
        {
            return _flags.TryGetValue(flag, out var value) ? value : defaultValue;
        }

        public int GetIntFlag(string flag, int defaultValue = 0)
        {
            if (_flags.TryGetValue(flag, out var value))
            {
                switch (value)
                {
                    case int i: return i;
                    case long l: return (int)l;
                    case double d: return (int)d;
                    case float f: return (int)f;
                    case string s when int.TryParse(s, out var parsed): return parsed;
                }
            }
            return defaultValue;
        }

        public bool GetBoolFlag(string flag, bool defaultValue = false)
        {
            if (_flags.TryGetValue(flag, out var value) && value is bool b)
                return b;
            return defaultValue;
        }

        public void ClearFlag(string flag)
        {
            _flags.Remove(flag);
        }

        // -------------------------------------------------------------------
        // ISaveable (mirrors game_manager.gd: save_data() -> {"flags": {...}})
        // -------------------------------------------------------------------

        public Dictionary<string, object> SaveData()
        {
            return new Dictionary<string, object>
            {
                ["flags"] = new Dictionary<string, object>(_flags),
            };
        }

        public void LoadData(Dictionary<string, object> data)
        {
            _flags.Clear();
            if (data != null && data.TryGetValue("flags", out var raw)
                && raw is Dictionary<string, object> flags)
            {
                foreach (var pair in flags)
                    _flags[pair.Key] = pair.Value;
            }
        }

        // -------------------------------------------------------------------
        // JSON save/load: one document, one slot per ISaveable.SaveKey.
        // {"game_manager": {"flags": {...}}, "player": {"position": ..., "health": ...}}
        // -------------------------------------------------------------------

        /// <summary>Serialize every ISaveable in the scene (self included) to JSON.</summary>
        public string SaveToJson()
        {
            var document = new Dictionary<string, object>();
            foreach (var saveable in FindSaveables())
                document[saveable.SaveKey] = saveable.SaveData();
            return JsonConvert.SerializeObject(document, Formatting.Indented);
        }

        /// <summary>Restore every ISaveable in the scene from a JSON document.</summary>
        public void LoadFromJson(string json)
        {
            var parsed = JToken.Parse(json);
            if (!(ToPlainObject(parsed) is Dictionary<string, object> document))
            {
                Debug.LogError("GameManager: save document root is not an object");
                return;
            }
            foreach (var saveable in FindSaveables())
            {
                if (document.TryGetValue(saveable.SaveKey, out var slot)
                    && slot is Dictionary<string, object> data)
                {
                    saveable.LoadData(data);
                }
            }
        }

        public void SaveGame(string path = null)
        {
            path = path ?? DefaultSavePath;
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            File.WriteAllText(path, SaveToJson());
            Debug.Log($"GameManager: saved to {path}");
        }

        public bool LoadGame(string path = null)
        {
            path = path ?? DefaultSavePath;
            if (!File.Exists(path))
            {
                Debug.LogWarning($"GameManager: no save file at {path}");
                return false;
            }
            LoadFromJson(File.ReadAllText(path));
            Debug.Log($"GameManager: loaded from {path}");
            return true;
        }

        List<ISaveable> FindSaveables()
        {
            var saveables = FindObjectsByType<MonoBehaviour>(
                    FindObjectsInactive.Include, FindObjectsSortMode.InstanceID)
                .OfType<ISaveable>()
                .ToList();
            if (!saveables.Contains(this))
                saveables.Add(this);
            return saveables;
        }

        /// <summary>
        /// Convert a parsed JToken tree into plain Dictionary/List/primitive
        /// values so LoadData implementations get the same shapes SaveData
        /// produced (mirrors Godot's Variant round-trip through JSON).
        /// </summary>
        static object ToPlainObject(JToken token)
        {
            switch (token.Type)
            {
                case JTokenType.Object:
                    var dict = new Dictionary<string, object>();
                    foreach (var property in ((JObject)token).Properties())
                        dict[property.Name] = ToPlainObject(property.Value);
                    return dict;
                case JTokenType.Array:
                    return ((JArray)token).Select(ToPlainObject).ToList();
                case JTokenType.Integer:
                    return token.Value<long>();
                case JTokenType.Float:
                    return token.Value<double>();
                case JTokenType.Boolean:
                    return token.Value<bool>();
                case JTokenType.Null:
                    return null;
                default:
                    return token.Value<string>();
            }
        }
    }
}
