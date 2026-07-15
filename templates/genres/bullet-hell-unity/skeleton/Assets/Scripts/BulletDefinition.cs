// Assets/Scripts/BulletDefinition.cs
// Scene-side registration nodes — the Unity port of the Godot template's
// BulletProps and SpawnPattern nodes (BuHBulletProperties / BuHPattern), which
// register their resources into the Spawning autoload on _ready.
//
// In the Godot scene these are Path2D nodes carrying a BulletProps / PatternCircle
// resource and an id; on ready they call into the addon. Here each is a tiny
// MonoBehaviour holding a serialized definition that it registers with
// BulletSystem in Awake. Keeping registration in scene components (rather than
// hardcoding in the spawner) preserves the addon's "add a bullet/pattern by
// dropping a node and giving it an id" extension model.

using UnityEngine;

namespace NoxDev.BulletHell
{
    /// <summary>
    /// Registers one bullet type by id (port of BuHBulletProperties). Drop this
    /// on a GameObject, set the id + props, and BulletSystem knows the type.
    /// </summary>
    public sealed class BulletDefinition : MonoBehaviour
    {
        [Tooltip("The bullet type this node contributes to the BulletSystem "
                 + "registry. Its id is how patterns reference it.")]
        public BulletProps props = new BulletProps();

        void Awake()
        {
            BulletSystem.Instance.RegisterBullet(props);
        }
    }

    /// <summary>
    /// Registers one spawn pattern by id (port of BuHPattern). Spawners reference
    /// the pattern by id; the pattern references its bullet type by id.
    /// </summary>
    public sealed class PatternDefinition : MonoBehaviour
    {
        [Tooltip("The volley pattern this node contributes to the BulletSystem "
                 + "registry. Spawners fire it by id.")]
        public SpawnPattern pattern = new SpawnPattern();

        void Awake()
        {
            BulletSystem.Instance.RegisterPattern(pattern);
        }
    }
}
