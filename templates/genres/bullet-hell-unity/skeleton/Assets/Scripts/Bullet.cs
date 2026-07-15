// Assets/Scripts/Bullet.cs
// A single pooled bullet. Deliberately dumb: it holds state and its visual, but
// it does NOT drive itself — BulletSystem steps every live bullet centrally in
// one FixedUpdate. This is the Unity port of BulletUpHell keeping bullets as
// plain pooled data stepped from the Spawning autoload rather than as scene
// nodes with their own _physics_process. One component per pooled GameObject;
// Activate() checks it out of the pool, Deactivate() returns it.

using UnityEngine;

namespace NoxDev.BulletHell
{
    public sealed class Bullet : MonoBehaviour
    {
        public BulletProps Props { get; private set; }
        public Vector2 Position { get; private set; }
        public Vector2 Velocity { get; private set; }
        public float Age { get; private set; }

        SpriteRenderer _renderer;
        Transform _transform;

        /// <summary>Wire the cached components once, at pool-creation time.</summary>
        public void Bind(SpriteRenderer renderer)
        {
            _renderer = renderer;
            _transform = transform;
        }

        /// <summary>Check a bullet out of the pool with fresh state.</summary>
        public void Activate(BulletProps props, Vector2 position, Vector2 velocity)
        {
            Props = props;
            Position = position;
            Velocity = velocity;
            Age = 0f;

            if (_transform == null)
                _transform = transform;
            _transform.position = position;
            _transform.localScale = new Vector3(props.visualScale, props.visualScale, 1f);

            if (_renderer != null)
                _renderer.color = props.color;
            gameObject.SetActive(true);
        }

        /// <summary>Advance one physics tick. Called only by BulletSystem.</summary>
        public void Step(float delta)
        {
            Age += delta;
            Position += Velocity * delta;
            _transform.position = Position;
        }

        /// <summary>Return the bullet to the pool (hidden, inert).</summary>
        public void Deactivate()
        {
            Props = null;
            gameObject.SetActive(false);
        }
    }
}
