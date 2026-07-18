// Assets/Scripts/Engine/IfDataPaths.cs
// Resolves the nox_if_engine data directory (rulesets + scenarios) shipped under
// StreamingAssets, so both the runtime play scene and the headless probe load the
// same JSON. StreamingAssets is a plain folder on desktop; on packaged platforms
// it may be a URI, but this template targets desktop editor/standalone.
using System.IO;
using UnityEngine;

namespace NoxIfEngine
{
    public static class IfDataPaths
    {
        public static string DataRoot =>
            Path.Combine(Application.streamingAssetsPath, "nox_if_engine", "data");

        public static string Ruleset(string id) =>
            Path.Combine(DataRoot, "rulesets", id + ".json");

        public static string Scenario(string id) =>
            Path.Combine(DataRoot, "scenarios", id + ".json");
    }
}
