#!/usr/bin/env python3
"""daz_compose.py — NoxDev daz-bridge P1 scene composer.

JSON scene spec -> generated DazScript (.dsa) -> headless(-ish) Daz Studio 6
render -> manifest.json + PNGs.

Scene spec v1 (P1 subset — see SCENE_COMPOSER_SPEC.md):
    {
      "figures": [{ "asset": "People/.../Figure.duf", "id": "her",
                    "pose": "Poses/....duf",          // optional; warn+skip if missing
                    "position": [0, 0, 0],            // cm, optional
                    "rotationY": 15 }],               // deg, optional
      "environment": "Environments/.../set.duf",       // optional; warn+skip if missing
      "cameras": [{ "name": "front", "focalMM": 65,
                    "orbit": { "yawDeg": 0, "pitchDeg": 10, "distanceCM": 300 } }],
      "lighting": "path/to/lights.duf" | "hdri:name",  // optional; hdri:* -> P1 warn
      "render": { "width": 512, "height": 512, "outDir": "D:/Daz/NoxDev/renders/job" }
    }

Usage:
    python daz_compose.py scene.json
    python daz_compose.py scene.json --dry-run          # generate .dsa only, print path
    python daz_compose.py scene.json --timeout 3600

All DazScript API patterns are the ones validated by tools/daz_turnaround.dsa
on DS6 (App.scriptArgs parsing, content-dir self-registration, property-control
camera placement, MainWindow viewport, MainWindow.close() exit), plus a
DzImageRenderHandler primary render path (official Daz "Render Image" sample)
to fix the turnaround's known imageSize-not-applied issue, with the proven
doRender() path as fallback.
"""

import argparse
import json
import os
import struct
import subprocess
import sys
import tempfile
import time

DEFAULT_DAZ_EXE = r"C:\Daz 3D\Applications\64-bit\DAZ 3D\DAZStudio6\DAZStudio.exe"
DEFAULT_CONTENT_DIR = "C:/Daz 3D/Applications/Data/DAZ 3D/My DAZ 3D Library"
INSTANCE_NAME = "noxcompose"
MANIFEST_NAME = "manifest.json"

# ---------------------------------------------------------------------------
# spec validation
# ---------------------------------------------------------------------------

def validate_spec(spec):
    """Return a list of error strings (empty = valid)."""
    errors = []
    if not isinstance(spec, dict):
        return ["spec root must be a JSON object"]

    figures = spec.get("figures")
    if not isinstance(figures, list) or not figures:
        errors.append("'figures' must be a non-empty array")
    else:
        for i, fig in enumerate(figures):
            if not isinstance(fig, dict) or not isinstance(fig.get("asset"), str) or not fig["asset"]:
                errors.append("figures[%d].asset must be a non-empty string" % i)
                continue
            pos = fig.get("position")
            if pos is not None and (not isinstance(pos, list) or len(pos) != 3
                                    or not all(isinstance(v, (int, float)) for v in pos)):
                errors.append("figures[%d].position must be [x, y, z] numbers (cm)" % i)
            rot = fig.get("rotationY")
            if rot is not None and not isinstance(rot, (int, float)):
                errors.append("figures[%d].rotationY must be a number (deg)" % i)
            pose = fig.get("pose")
            if pose is not None and not isinstance(pose, str):
                errors.append("figures[%d].pose must be a string path" % i)

    cameras = spec.get("cameras")
    if not isinstance(cameras, list) or not cameras:
        errors.append("'cameras' must be a non-empty array")
    else:
        for i, cam in enumerate(cameras):
            if not isinstance(cam, dict) or not isinstance(cam.get("name"), str) or not cam["name"]:
                errors.append("cameras[%d].name must be a non-empty string" % i)
                continue
            orbit = cam.get("orbit")
            if not isinstance(orbit, dict):
                errors.append("cameras[%d].orbit must be an object {yawDeg, pitchDeg, distanceCM}" % i)
            else:
                for key in ("yawDeg", "pitchDeg", "distanceCM"):
                    if key in orbit and not isinstance(orbit[key], (int, float)):
                        errors.append("cameras[%d].orbit.%s must be a number" % (i, key))
            if "focalMM" in cam and not isinstance(cam["focalMM"], (int, float)):
                errors.append("cameras[%d].focalMM must be a number" % i)

    render = spec.get("render")
    if not isinstance(render, dict):
        errors.append("'render' must be an object {width, height, outDir}")
    else:
        for key in ("width", "height"):
            v = render.get(key)
            if not isinstance(v, int) or v <= 0:
                errors.append("render.%s must be a positive integer" % key)
        if not isinstance(render.get("outDir"), str) or not render["outDir"]:
            errors.append("render.outDir must be a non-empty string")

    env = spec.get("environment")
    if env is not None and not isinstance(env, str):
        errors.append("'environment' must be a string path")
    lighting = spec.get("lighting")
    if lighting is not None and not isinstance(lighting, str):
        errors.append("'lighting' must be a string ('hdri:<name>' or a .duf path)")

    return errors


# ---------------------------------------------------------------------------
# DazScript generation (patterns validated by daz_turnaround.dsa on DS6)
# ---------------------------------------------------------------------------

DSA_TEMPLATE = r'''// GENERATED by daz_compose.py -- NoxDev daz-bridge P1. Do not edit; edit the spec JSON.
// API patterns per tools/daz_turnaround.dsa (validated DS6) + DzImageRenderHandler
// primary render path (Daz "Render Image" sample) for explicit pixel size.
(function () {
	var SPEC = __SPEC_JSON__;

	function log(msg) { print("[daz_compose] " + msg); }
	var warnings = [];
	function warn(msg) { warnings.push(String(msg)); log("WARN: " + msg); }

	// ---- args: -scriptArg "key='value'" via App.scriptArgs (turnaround pattern) ----
	var oArgs = {};
	var aRaw = App.scriptArgs;
	for (var a = 0; a < aRaw.length; a++) {
		var aMatches = /^([a-zA-Z]+)=(.*)$/g.exec(aRaw[a]);
		if (aMatches && aMatches.length == 3) {
			var value = aMatches[2];
			var aStr = /^(?:\"(.*)\")|(?:\'(.*)\')$/g.exec(value);
			if (aStr && aStr.length == 3) value = aStr[1] || aStr[2];
			oArgs[aMatches[1]] = value;
		}
	}
	var contentDir = oArgs.cfgContentDir !== undefined ? String(oArgs.cfgContentDir)
		: "__CONTENT_DIR__";

	var outDir = String(SPEC.render.outDir);
	var width = Number(SPEC.render.width);
	var height = Number(SPEC.render.height);

	// ---- content dir self-registration: fresh -instanceName instances have NO
	// registered content dirs, so .duf payload refs (/data/...) fail (turnaround) ----
	var cMgr = App.getContentMgr();
	var haveDir = false;
	for (var d = 0; d < cMgr.getNumContentDirectories(); d++) {
		if (String(cMgr.getContentDirectoryPath(d)).toLowerCase() == contentDir.toLowerCase()) haveDir = true;
	}
	if (!haveDir) {
		cMgr.addContentDirectory(contentDir);
		log("registered content dir: " + contentDir);
	}

	var dir = new DzDir(outDir);
	if (!dir.exists()) dir.mkpath(outDir);

	function writeManifestAndQuit(status, files) {
		var manifest = {
			status: status,
			generator: "daz_compose.py P1",
			files: files,
			warnings: warnings,
			render: { width: width, height: height, outDir: outDir }
		};
		var mf = new DzFile(outDir + "/manifest.json");
		if (mf.open(DzFile.WriteOnly)) { mf.write(JSON.stringify(manifest, null, 2)); mf.close(); }
		log("DONE status=" + status + " files=" + files.length + " -> " + outDir);
		Scene.clear();
		MainWindow.close();
	}

	function resolveAsset(relPath) {
		// try: absolute path as given, content-dir join, findFile with and
		// without a leading slash (fresh -instanceName instances resolve via
		// the registered dir join even when findFile comes up empty)
		var noSlash = relPath.charAt(0) == "/" ? relPath.substring(1) : relPath;
		var candidates = [relPath, contentDir + "/" + noSlash];
		for (var i = 0; i < candidates.length; i++) {
			if ((new DzFileInfo(candidates[i])).exists()) return candidates[i];
		}
		var finds = [cMgr.findFile(noSlash), cMgr.findFile("/" + noSlash)];
		for (var j = 0; j < finds.length; j++) {
			if (finds[j] && String(finds[j]) != "") return String(finds[j]);
		}
		return null;
	}

	Scene.clear();

	// ---- environment (optional; warn + skip when missing, never hard-fail) ----
	if (SPEC.environment) {
		var envAbs = resolveAsset(String(SPEC.environment));
		if (!envAbs) warn("environment not found (skipped): " + SPEC.environment);
		else if (!cMgr.openFile(envAbs, true)) warn("environment openFile failed (skipped): " + SPEC.environment);
		else log("environment loaded: " + SPEC.environment);
	}

	// ---- figures ----
	var figureNodes = [];
	for (var f = 0; f < SPEC.figures.length; f++) {
		var fig = SPEC.figures[f];
		var figId = fig.id !== undefined && fig.id !== null ? String(fig.id) : ("figure" + f);
		var absPath = resolveAsset(String(fig.asset));
		if (!absPath) {
			log("FATAL: figure asset not found: " + fig.asset);
			writeManifestAndQuit("error: figure asset not found: " + fig.asset, []);
			return;
		}
		var nSkelBefore = Scene.getNumSkeletons();
		if (!cMgr.openFile(absPath, true)) {
			writeManifestAndQuit("error: openFile failed: " + absPath, []);
			return;
		}
		// FIRST new skeleton = the body; later ones are followers (G8.1F adds
		// "Tear"/eyelash skeletons after the body — validated 2026-07-12)
		var target = null;
		if (Scene.getNumSkeletons() > nSkelBefore) target = Scene.getSkeleton(nSkelBefore);
		if (!target) target = Scene.getPrimarySelection();
		if (!target) {
			writeManifestAndQuit("error: no figure node after loading " + fig.asset, []);
			return;
		}
		log("figure loaded: " + figId + " -> " + target.getLabel());

		// pose preset (generation-bound: authored per Genesis generation, so a
		// missing/mismatched ref is a tagged warning + skip, never a hard fail)
		if (fig.pose) {
			var poseAbs = resolveAsset(String(fig.pose));
			if (!poseAbs) {
				warn("pose not found (skipped; generation-bound -- check the preset targets this figure's Genesis generation): " + fig.pose);
			} else {
				Scene.selectAllNodes(false);
				target.select(true);
				Scene.setPrimarySelection(target);
				if (!cMgr.openFile(poseAbs, true)) warn("pose apply failed (skipped): " + fig.pose);
				else log("pose applied to " + figId + ": " + fig.pose);
			}
		}

		// placement AFTER pose (pose presets can carry root transforms) —
		// property controls per turnaround pattern
		var pos = fig.position && fig.position.length == 3 ? fig.position : [0, 0, 0];
		target.getXPosControl().setValue(Number(pos[0]));
		target.getYPosControl().setValue(Number(pos[1]));
		target.getZPosControl().setValue(Number(pos[2]));
		if (fig.rotationY !== undefined && fig.rotationY !== null) {
			target.getYRotControl().setValue(Number(fig.rotationY));
		}
		figureNodes.push(target);
	}

	// ---- lighting (optional; P1 supports .duf light presets only) ----
	if (SPEC.lighting) {
		var sLight = String(SPEC.lighting);
		if (sLight.toLowerCase().indexOf("hdri:") == 0) {
			warn("lighting '" + sLight + "' -- hdri:* presets not supported in P1, using Iray default (headlamp)");
		} else {
			var lightAbs = resolveAsset(sLight);
			if (!lightAbs) warn("lighting preset not found (skipped): " + sLight);
			else if (!cMgr.openFile(lightAbs, true)) warn("lighting apply failed (skipped): " + sLight);
			else log("lighting applied: " + sLight);
		}
	}

	// ---- orbit center: bbox of first figure, feature-detected (turnaround pattern) ----
	var cx = 0, cy = 110, cz = 0;
	if (figureNodes.length > 0) {
		var t0 = figureNodes[0];
		try {
			var box = null;
			if (typeof t0.getWorldBox == "function") box = t0.getWorldBox();
			else if (t0.getObject() && typeof t0.getObject().getGeometryBoundingBox == "function")
				box = t0.getObject().getGeometryBoundingBox();
			if (box) {
				var mn = box.min, mx = box.max;
				cx = (mn.x + mx.x) / 2; cy = (mn.y + mx.y) / 2; cz = (mn.z + mx.z) / 2;
				log("orbit center from bbox: " + cx.toFixed(1) + "," + cy.toFixed(1) + "," + cz.toFixed(1));
			} else {
				warn("no bbox API -- orbit center default (0,110,0)");
			}
		} catch (e) {
			warn("bbox failed (" + e + ") -- orbit center default (0,110,0)");
		}
	}

	// ---- render options (turnaround pattern; imageSize known-not-applied on DS6,
	// so the primary render path below passes an explicit Size to the handler) ----
	var renderMgr = App.getRenderMgr();
	var ro = renderMgr.getRenderOptions();
	ro.renderImgToId = DzRenderOptions.DirectToFile;
	ro.imageSize = new Size(width, height);
	ro.aspectRatio = new Point(width, height);
	ro.isAspectConstrained = true;

	var vp = MainWindow.getViewportMgr().getActiveViewport().get3DViewport();

	var files = [];
	for (var c = 0; c < SPEC.cameras.length; c++) {
		var camSpec = SPEC.cameras[c];
		var orbit = camSpec.orbit || {};
		var yawDeg = orbit.yawDeg !== undefined ? Number(orbit.yawDeg) : 0;
		var pitchDeg = orbit.pitchDeg !== undefined ? Number(orbit.pitchDeg) : 0;
		var dist = orbit.distanceCM !== undefined ? Number(orbit.distanceCM) : 250;
		var yaw = yawDeg * Math.PI / 180.0;
		var pitch = pitchDeg * Math.PI / 180.0;

		var cam = new DzBasicCamera();
		cam.setName("cam_" + String(camSpec.name));
		Scene.addNode(cam);
		var focalCtrl = cam.getFocalLengthControl();
		if (focalCtrl) focalCtrl.setValue(camSpec.focalMM !== undefined ? Number(camSpec.focalMM) : 65.0);

		// orbit camera: position via translation controls, aim via Y/X rotation
		// (default camera forward is -Z; facing center needs YRot=yawDeg, and a
		// camera raised by pitch looks back down with XRot=-pitchDeg)
		var px = cx + dist * Math.sin(yaw) * Math.cos(pitch);
		var py = cy + dist * Math.sin(pitch);
		var pz = cz + dist * Math.cos(yaw) * Math.cos(pitch);
		cam.getXPosControl().setValue(px);
		cam.getYPosControl().setValue(py);
		cam.getZPosControl().setValue(pz);
		cam.getYRotControl().setValue(yawDeg);
		cam.getXRotControl().setValue(-pitchDeg);

		var safeName = String(camSpec.name).replace(/[^A-Za-z0-9_\-]/g, "_");
		var fname = outDir + "/" + ("0" + c).slice(-2) + "_" + safeName + ".png";
		var oldFile = new DzFileInfo(fname);
		if (oldFile.exists() && !oldFile.isDir()) oldFile.remove(); // overwrite (Autodazzler pattern)

		vp.setCamera(cam);

		var rendered = false;
		// PRIMARY: renderer.render(DzImageRenderHandler(Size,...)) — explicit pixel
		// size (fixes turnaround's imageSize-not-applied on DS6)
		try {
			if (typeof DzImageRenderHandler != "undefined") {
				var oSize = new Size(width, height);
				var oHandler = new DzImageRenderHandler(oSize, 0, fname);
				var oRenderer = renderMgr.getActiveRenderer();
				log("rendering (handler path, " + width + "x" + height + "): " + fname);
				oRenderer.render(oHandler, cam, ro);
				if (typeof oRenderer.isRendering == "function") {
					while (oRenderer.isRendering()) sleep(250);
				}
				oHandler.deleteLater();
				rendered = (new DzFileInfo(fname)).exists();
				if (!rendered) warn("handler render produced no file for camera '" + camSpec.name + "' -- falling back to doRender");
			}
		} catch (e) {
			warn("handler render path failed (" + e + ") -- falling back to doRender for camera '" + camSpec.name + "'");
			rendered = false;
		}
		// FALLBACK: proven turnaround path (size may be viewport-bound)
		if (!rendered) {
			ro.renderImgFilename = fname;
			log("rendering (doRender fallback): " + fname);
			renderMgr.doRender();
			rendered = (new DzFileInfo(fname)).exists();
		}

		if (rendered) files.push({ camera: String(camSpec.name), file: fname });
		else warn("render produced no file for camera '" + camSpec.name + "'");
	}

	writeManifestAndQuit(files.length == SPEC.cameras.length ? "ok" : (files.length > 0 ? "partial" : "error: no renders produced"), files);
})();
'''


def generate_script(spec, content_dir):
    spec_json = json.dumps(spec, indent=2)
    # indent the embedded literal to match template body
    spec_json = spec_json.replace("\n", "\n\t")
    script = DSA_TEMPLATE.replace("__SPEC_JSON__", spec_json)
    script = script.replace("__CONTENT_DIR__", content_dir.replace("\\", "/"))
    return script


# ---------------------------------------------------------------------------
# PNG header probe (no PIL dependency)
# ---------------------------------------------------------------------------

def png_size(path):
    """Return (width, height) from a PNG's IHDR, or None."""
    try:
        with open(path, "rb") as fh:
            head = fh.read(24)
        if len(head) == 24 and head[:8] == b"\x89PNG\r\n\x1a\n" and head[12:16] == b"IHDR":
            return struct.unpack(">II", head[16:24])
    except OSError:
        pass
    return None


# ---------------------------------------------------------------------------
# runner
# ---------------------------------------------------------------------------

def instance_log_path():
    return os.path.expandvars(r"%APPDATA%\DAZ 3D\Studio6 [" + INSTANCE_NAME + r"]\log.txt")


def instance_already_running():
    """True if a DAZStudio process with our -instanceName is alive.

    Daz Studio is single-instance per instanceName: a second launch hands off
    and exits code 1 immediately (observed 2026-07-12), so fail fast instead.
    """
    try:
        out = subprocess.run(
            ["powershell", "-NoProfile", "-Command",
             "(Get-CimInstance Win32_Process -Filter \"Name='DAZStudio.exe'\").CommandLine"],
            capture_output=True, text=True, timeout=30).stdout or ""
        return ("-instanceName %s" % INSTANCE_NAME) in out
    except (OSError, subprocess.TimeoutExpired):
        return False  # can't tell — proceed and rely on the exit-code diagnostics


def run(spec_path, daz_exe, content_dir, timeout_s, dry_run, keep_script):
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(line_buffering=True)
    with open(spec_path, "r", encoding="utf-8") as fh:
        spec = json.load(fh)

    errors = validate_spec(spec)
    if errors:
        print("[daz_compose] SPEC INVALID: %s" % spec_path)
        for e in errors:
            print("  - %s" % e)
        return 2

    out_dir = spec["render"]["outDir"].replace("\\", "/")
    spec["render"]["outDir"] = out_dir
    os.makedirs(out_dir, exist_ok=True)

    manifest_path = os.path.join(out_dir, MANIFEST_NAME)
    if os.path.exists(manifest_path):
        os.remove(manifest_path)  # stale manifest would defeat completion polling

    script_text = generate_script(spec, content_dir)
    fd, script_path = tempfile.mkstemp(prefix="noxdev_daz_compose_", suffix=".dsa")
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(script_text)
    print("[daz_compose] generated DazScript: %s" % script_path)

    if dry_run:
        print("[daz_compose] --dry-run: not launching Daz Studio")
        return 0

    if not os.path.isfile(daz_exe):
        print("[daz_compose] ERROR: DAZStudio.exe not found: %s" % daz_exe)
        return 2

    if instance_already_running():
        print("[daz_compose] ERROR: a DAZStudio instance named '%s' is already running — "
              "wait for it to finish or kill it, then retry" % INSTANCE_NAME)
        return 3

    cmd = [
        daz_exe,
        script_path,
        "-scriptArg", "cfgContentDir='%s'" % content_dir.replace("\\", "/"),
        "-instanceName", INSTANCE_NAME,
        "-noPrompt",
    ]
    print("[daz_compose] launching: %s" % subprocess.list2cmdline(cmd))
    proc = subprocess.Popen(cmd)

    # ---- poll for the manifest the generated script writes just before quitting ----
    started = time.time()
    manifest = None
    exit_note = None
    while time.time() - started < timeout_s:
        if os.path.exists(manifest_path):
            try:
                with open(manifest_path, "r", encoding="utf-8") as fh:
                    manifest = json.load(fh)
                break
            except (ValueError, OSError):
                pass  # mid-write; retry next poll
        if proc.poll() is not None and not os.path.exists(manifest_path):
            exit_note = "Daz Studio exited (code %s) without writing a manifest" % proc.returncode
            break
        time.sleep(2)

    if manifest is None:
        if exit_note is None:
            exit_note = "timed out after %ds waiting for manifest" % timeout_s
            proc.kill()
        print("[daz_compose] FAILED: %s" % exit_note)
        print("[daz_compose] check the instance log for 'Script Error' lines: %s" % instance_log_path())
        print("[daz_compose] generated script kept at: %s" % script_path)
        return 1

    # let the instance close on its own (MainWindow.close()), then make sure
    try:
        proc.wait(timeout=60)
    except subprocess.TimeoutExpired:
        print("[daz_compose] instance did not exit after manifest — killing")
        proc.kill()

    # ---- report ----
    status = manifest.get("status", "?")
    files = manifest.get("files", [])
    warnings = manifest.get("warnings", [])
    want_w = spec["render"]["width"]
    want_h = spec["render"]["height"]

    print("[daz_compose] status: %s" % status)
    for entry in files:
        fpath = entry.get("file", "")
        dims = png_size(fpath)
        size_note = "MISSING"
        if os.path.isfile(fpath):
            kb = os.path.getsize(fpath) / 1024.0
            if dims:
                match = "OK" if dims == (want_w, want_h) else "MISMATCH (wanted %dx%d)" % (want_w, want_h)
                size_note = "%dx%d %s, %.0f KB" % (dims[0], dims[1], match, kb)
            else:
                size_note = "not a PNG?, %.0f KB" % kb
        print("  [%s] %s — %s" % (entry.get("camera", "?"), fpath, size_note))
    for w in warnings:
        print("  WARN: %s" % w)
    print("[daz_compose] manifest: %s" % manifest_path)

    if not keep_script and str(status) == "ok":
        os.remove(script_path)
    else:
        print("[daz_compose] generated script kept at: %s" % script_path)

    return 0 if str(status) == "ok" else 1


def main(argv=None):
    ap = argparse.ArgumentParser(description="JSON scene spec -> generated DazScript -> headless Daz Studio render (NoxDev daz-bridge P1)")
    ap.add_argument("spec", help="path to scene spec JSON (see SCENE_COMPOSER_SPEC.md)")
    ap.add_argument("--daz-exe", default=DEFAULT_DAZ_EXE, help="DAZStudio.exe path (default: %(default)s)")
    ap.add_argument("--content-dir", default=DEFAULT_CONTENT_DIR, help="Daz content library root to self-register (default: %(default)s)")
    ap.add_argument("--timeout", type=int, default=1800, help="seconds to wait for the manifest (default: %(default)s; CPU Iray is slow)")
    ap.add_argument("--dry-run", action="store_true", help="generate the .dsa and exit without launching Daz Studio")
    ap.add_argument("--keep-script", action="store_true", help="keep the generated .dsa even on success")
    args = ap.parse_args(argv)
    return run(args.spec, args.daz_exe, args.content_dir, args.timeout, args.dry_run, args.keep_script)


if __name__ == "__main__":
    sys.exit(main())
