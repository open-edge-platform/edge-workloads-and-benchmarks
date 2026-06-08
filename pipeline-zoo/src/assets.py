"""Asset registry and asset management."""

import copy
import json
import re
import shutil
import urllib.request
from pathlib import Path
from urllib.parse import urlparse

from src.config import (
    ASSETS_DIR, ENV_FILE, DEFAULT_IMAGE, REST_PORT, RTSP_PORT,
)
from src.models import PipelineZooError

_ALLOWED_URL_SCHEMES = ("https",)


# =========================================================================== #
#  Shared constants for downloader scripts running inside Docker              #
# =========================================================================== #

_VENV = "/model-conversion/venv/bin/python3"
_SCRIPTS = "/model-conversion/download-models"
_CACHE = "/cache/datasets"
_OUTPUT = "/output/models"
_LABELS = "/opt/intel/dlstreamer/samples/labels/imagenet_2012.txt"
_MODEL_PROC_URL = (
    "https://raw.githubusercontent.com/open-edge-platform/dlstreamer/"
    "refs/heads/main/samples/gstreamer/model_proc/public/"
    "classification-optimized.json"
)
_YOLOV5_BASE = (
    "https://raw.githubusercontent.com/dlstreamer/pipeline-zoo-models/"
    "refs/heads/main/storage/yolov5m-640_INT8"
)
_EFFICIENTNET_BASE = (
    "https://raw.githubusercontent.com/dlstreamer/pipeline-zoo-models/"
    "refs/heads/main/storage/efficientnet-b0_INT8"
)
_OMZ_BASE = (
    "https://storage.openvinotoolkit.org/repositories/open_model_zoo/"
    "2023.0/models_bin/1"
)
_MODEL_PROC_BASE = (
    "https://raw.githubusercontent.com/open-edge-platform/dlstreamer/"
    "refs/heads/main/samples/gstreamer/model_proc"
)
_EDGE_AI_RESOURCES = (
    "https://github.com/open-edge-platform/edge-ai-resources/raw/main/models"
)

# =========================================================================== #
#  Video download registry — maps local filenames to download URLs            #
#  Sources: VIPPET default_recordings.yaml                                    #
# =========================================================================== #

_VIDEOS = {
    "warehouse.avi": (
        "https://github.com/open-edge-platform/edge-ai-resources/raw/"
        "c13b8dbf23d514c2667d39b66615bd1400cb889d/videos/warehouse.avi"
    ),
    "license-plate-detection.mp4": (
        "https://github.com/open-edge-platform/edge-ai-resources/raw/"
        "6d452bf87bb1707630f747774d2d15caa1a6f7aa/videos/ParkingVideo.mp4"
    ),
    "obj_classification.mp4": (
        "https://www.pexels.com/download/video/6891009"
    ),
    "age_prediction.mp4": (
        "https://www.pexels.com/download/video/3249935"
    ),
    "traffic.mp4": (
        "https://videos.pexels.com/video-files/1192116/"
        "1192116-sd_640_360_30fps.mp4"
    ),
}


# =========================================================================== #
#  Thin routing table — each entry describes how to obtain a model            #
#  Everything else (path_vars, check_files) is derived by helpers             #
# =========================================================================== #

_MODELS = {
    "Ultralytics/yolov11n": {
        "downloader":  [_VENV, f"{_SCRIPTS}/yolo_downloader.py",
                        "-m", "yolo11n", "-i", _CACHE, "-o", _OUTPUT],
        "pre_setup":   [_VENV, f"{_SCRIPTS}/initialize_ultralytics.py",
                        "-i", _CACHE],
        "cache_dir":   "models/yolo11n",
        "xml":         "yolo11n_int8.xml",
    },
    "Ultralytics/yolov11m": {
        "downloader":  [_VENV, f"{_SCRIPTS}/yolo_downloader.py",
                        "-m", "yolo11m", "-i", _CACHE, "-o", _OUTPUT],
        "pre_setup":   [_VENV, f"{_SCRIPTS}/initialize_ultralytics.py",
                        "-i", _CACHE],
        "cache_dir":   "models/yolo11m",
        "xml":         "yolo11m_int8.xml",
    },
    "dlstreamer/yolov5m": {
        "urls": [
            (f"{_YOLOV5_BASE}/FP16-INT8/yolov5m-640_INT8.xml",
             "models/yolo-v5m/yolov5m-640_INT8.xml"),
            (f"{_YOLOV5_BASE}/FP16-INT8/yolov5m-640_INT8.bin",
             "models/yolo-v5m/yolov5m-640_INT8.bin"),
            (f"{_YOLOV5_BASE}/yolo-v5.json",
             "models/yolo-v5m/yolo-v5.json"),
        ],
        "cache_dir":   "models/yolo-v5m",
        "xml":         "yolov5m-640_INT8.xml",
        "model_proc":  "yolo-v5.json",
    },
    "google/resnet-v1-50-tf": {
        "downloader":  [_VENV, f"{_SCRIPTS}/resnet_downloader.py",
                        "-o", f"{_OUTPUT}/resnet-50"],
        "cache_dir":   "models/resnet-50",
        "xml":         "resnet-50_int8.xml",
        "model_proc":  ("resnet-50.json", _MODEL_PROC_URL),
        "labels":      _LABELS,
    },
    "pytorch/mobilenet-v2": {
        "downloader":  [_VENV, f"{_SCRIPTS}/mobilenet_downloader.py",
                        "-o", f"{_OUTPUT}/mobilenet-v2"],
        "cache_dir":   "models/mobilenet-v2",
        "xml":         "mobilenetv2_int8.xml",
        "model_proc":  ("mobilenet-v2.json", _MODEL_PROC_URL),
        "labels":      _LABELS,
    },
    "public/yolov8_license_plate_detector": {
        "zip_url":     f"{_EDGE_AI_RESOURCES}/license-plate-reader.zip",
        "zip_files": [
            ("license-plate-reader/models/yolov8n/yolov8n_retrained.xml",
             "models/yolov8-lpr/yolov8_license_plate_detector.xml"),
            ("license-plate-reader/models/yolov8n/yolov8n_retrained.bin",
             "models/yolov8-lpr/yolov8_license_plate_detector.bin"),
        ],
        "cache_dir":   "models/yolov8-lpr",
        "xml":         "yolov8_license_plate_detector.xml",
    },
    "public/ch_PP-OCRv4_rec_infer": {
        "zip_url":     f"{_EDGE_AI_RESOURCES}/license-plate-reader.zip",
        "zip_files": [
            ("license-plate-reader/models/ch_PP-OCRv4_rec_infer/ch_PP-OCRv4_rec_infer.xml",
             "models/ppocr-v4/ch_PP-OCRv4_rec_infer.xml"),
            ("license-plate-reader/models/ch_PP-OCRv4_rec_infer/ch_PP-OCRv4_rec_infer.bin",
             "models/ppocr-v4/ch_PP-OCRv4_rec_infer.bin"),
        ],
        "cache_dir":   "models/ppocr-v4",
        "xml":         "ch_PP-OCRv4_rec_infer.xml",
    },
    "public/pallet_defect_detection": {
        "zip_url":     f"{_EDGE_AI_RESOURCES}/INT8/pallet_defect_detection.zip",
        "zip_files": [
            ("pallet_defect_detection/deployment/Detection/model/model.xml",
             "models/pallet-defect-detection/pallet_defect_detection.xml"),
            ("pallet_defect_detection/deployment/Detection/model/model.bin",
             "models/pallet-defect-detection/pallet_defect_detection.bin"),
        ],
        "cache_dir":   "models/pallet-defect-detection",
        "xml":         "pallet_defect_detection.xml",
    },
    # ── OMZ models (pre-trained, downloaded from OpenVINO storage) ──────── #
    "omz/face-detection-retail-0004": {
        "urls": [
            (f"{_OMZ_BASE}/face-detection-retail-0004/FP16/face-detection-retail-0004.xml",
             "models/face-detection-retail-0004/face-detection-retail-0004.xml"),
            (f"{_OMZ_BASE}/face-detection-retail-0004/FP16/face-detection-retail-0004.bin",
             "models/face-detection-retail-0004/face-detection-retail-0004.bin"),
        ],
        "model_proc": ("face-detection-retail-0004.json",
                       f"{_MODEL_PROC_BASE}/intel/face-detection-retail-0004.json"),
        "cache_dir":   "models/face-detection-retail-0004",
        "xml":         "face-detection-retail-0004.xml",
    },
    "omz/age-gender-recognition-retail-0013": {
        "urls": [
            (f"{_OMZ_BASE}/age-gender-recognition-retail-0013/FP16/age-gender-recognition-retail-0013.xml",
             "models/age-gender-recognition-retail-0013/age-gender-recognition-retail-0013.xml"),
            (f"{_OMZ_BASE}/age-gender-recognition-retail-0013/FP16/age-gender-recognition-retail-0013.bin",
             "models/age-gender-recognition-retail-0013/age-gender-recognition-retail-0013.bin"),
        ],
        "model_proc": ("age-gender-recognition-retail-0013.json",
                       f"{_MODEL_PROC_BASE}/intel/age-gender-recognition-retail-0013.json"),
        "cache_dir":   "models/age-gender-recognition-retail-0013",
        "xml":         "age-gender-recognition-retail-0013.xml",
    },
    # ── Ultralytics YOLO models (download + INT8 quantization) ─────────── #
    "public/yolo11n": {
        "downloader":  [_VENV, f"{_SCRIPTS}/yolo_downloader.py",
                        "-m", "yolo11n", "-i", _CACHE, "-o", _OUTPUT],
        "pre_setup":   [_VENV, f"{_SCRIPTS}/initialize_ultralytics.py",
                        "-i", _CACHE],
        "cache_dir":   "models/yolo11n",
        "xml":         "yolo11n_int8.xml",
    },
    "public/yolov8n": {
        "downloader":  [_VENV, f"{_SCRIPTS}/yolo_downloader.py",
                        "-m", "yolov8n", "-i", _CACHE, "-o", _OUTPUT],
        "pre_setup":   [_VENV, f"{_SCRIPTS}/initialize_ultralytics.py",
                        "-i", _CACHE],
        "cache_dir":   "models/yolov8n",
        "xml":         "yolov8n_int8.xml",
    },
    "public/yolo11s": {
        "downloader":  [_VENV, f"{_SCRIPTS}/yolo_downloader.py",
                        "-m", "yolo11s", "-i", _CACHE, "-o", _OUTPUT],
        "pre_setup":   [_VENV, f"{_SCRIPTS}/initialize_ultralytics.py",
                        "-i", _CACHE],
        "cache_dir":   "models/yolo11s",
        "xml":         "yolo11s.xml",
    },
    "public/colorcls2": {
        "cache_dir":   "models/colorcls2",
        "xml":         "colorcls2.xml",
    },
    # ── Pipeline-zoo-models (pre-converted, GitHub download) ───────────── #
    "pipeline-zoo-models/efficientnet-b0_INT8": {
        "urls": [
            (f"{_EFFICIENTNET_BASE}/FP16-INT8/efficientnet-b0.xml",
             "models/efficientnet-b0/efficientnet-b0.xml"),
            (f"{_EFFICIENTNET_BASE}/FP16-INT8/efficientnet-b0.bin",
             "models/efficientnet-b0/efficientnet-b0.bin"),
        ],
        "model_proc": ("preproc-aspect-ratio.json",
                       f"{_MODEL_PROC_BASE}/public/preproc-aspect-ratio.json"),
        "cache_dir":   "models/efficientnet-b0",
        "xml":         "efficientnet-b0.xml",
    },
}


# =========================================================================== #
#  Helpers — derive path_vars, check_files, and video info from the table     #
# =========================================================================== #

def _xml_to_bin(xml):
    """Derive .bin filename from .xml filename."""
    return xml.rsplit(".", 1)[0] + ".bin"


def _check_files(entry):
    """Return list of cache-relative paths that must exist for a model."""
    cdir = entry["cache_dir"]
    files = [f"{cdir}/{entry['xml']}", f"{cdir}/{_xml_to_bin(entry['xml'])}"]
    proc = entry.get("model_proc")
    if isinstance(proc, tuple):  # (name, url) — downloaded separately
        files.append(f"{cdir}/{proc[0]}")
    elif isinstance(proc, str):  # filename already in cache (e.g. yolov5m)
        files.append(f"{cdir}/{proc}")
    return files


def get_model_path_vars(asset_id):
    """Return {suffix: relative_path} for a model asset.

    Keys: "model-path" (points to .xml), "model-dir" (parent directory).
    Paths are relative to PIPE_ROOT and contain no {mode} template.
    """
    entry = _MODELS[asset_id]
    cdir = entry["cache_dir"]
    return {
        "model-path": f"{cdir}/{entry['xml']}",
        "model-dir":  cdir,
    }


def get_model_labels(asset_id):
    """Return the labels path for a model, or None."""
    return _MODELS.get(asset_id, {}).get("labels")


def resolve_video(url_or_path):
    """Derive local video paths from a Pexels URL or local filename.

    For Pexels URLs: extracts video ID, expects H.265 transcoded output.
    For local filenames: uses the file directly from video/ cache.
    """
    m = re.search(r"/video-files/(\d+)/", url_or_path)
    if m:
        vid = m.group(1)
        return {
            "path_vars":  {"path": f"video/{vid}.h265"},
            "mp4_name":   f"{vid}.mp4",
            "h265_name":  f"{vid}.h265",
            "h265_loop":  f"{vid}_loop100.h265",
            "check_file": f"video/{vid}.h265",
        }
    if not url_or_path.startswith("http"):
        name = url_or_path
        return {
            "path_vars":  {"path": f"video/{name}"},
            "mp4_name":   name,
            "h265_name":  None,
            "h265_loop":  None,
            "check_file": f"video/{name}",
        }
    raise PipelineZooError(
        f"Cannot resolve video asset: {url_or_path}\n"
        f"  Expected a Pexels URL or a local filename.")


# Maps pipeline.json asset keys to variable-name prefixes used in templates.
ASSET_KEY_PREFIX = {
    "detection_model":        "det",
    "classification_model":   "class",
    "classification_model_0": "class1",
    "classification_model_1": "class2",
    "input_video":            "video",
}

# Maps CLI flag dest names to the pipeline.json asset key(s) they override.
_CLI_TO_ASSET_KEYS = {
    "detection_model":        ["detection_model"],
    "classification_model_0": ["classification_model_0", "classification_model"],
    "classification_model_1": ["classification_model_1"],
    "input_video":            ["input_video"],
}


def apply_asset_overrides(args, pipeline_data):
    """Apply CLI asset override flags to pipeline data.

    Returns pipeline_data (possibly deep-copied with overridden asset IDs).
    """
    overrides = {}
    for dest, asset_keys in _CLI_TO_ASSET_KEYS.items():
        value = getattr(args, dest, None)
        if value is not None:
            overrides[dest] = value

    if not overrides:
        return pipeline_data

    pipeline_data = copy.deepcopy(pipeline_data)
    assets = pipeline_data.get("assets", {})

    for dest, value in overrides.items():
        replaced = False
        for key in _CLI_TO_ASSET_KEYS[dest]:
            if key in assets:
                print(f"  Override: {key} = {value}  (was {assets[key]})")
                assets[key] = value
                replaced = True
                break
        if not replaced:
            raise PipelineZooError(
                f"Cannot override '{dest}': no matching asset key in "
                f"pipeline.json (tried: {_CLI_TO_ASSET_KEYS[dest]})")

    return pipeline_data


def _validate_url(url):
    """Reject URLs with unexpected schemes (only https allowed)."""
    scheme = urlparse(url).scheme
    if scheme not in _ALLOWED_URL_SCHEMES:
        raise PipelineZooError(
            f"Unsupported URL scheme '{scheme}' in: {url}\n"
            f"  Allowed: {', '.join(_ALLOWED_URL_SCHEMES)}")


def _download_url(url, dest):
    """Download a file from *url* to *dest* with a simple progress message."""
    _validate_url(url)
    dest = Path(dest)
    dest.parent.mkdir(parents=True, exist_ok=True)
    print(f"    Downloading {dest.name}...")
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        resp = urllib.request.urlopen(req, timeout=300)  # nosec B310 — scheme validated by _validate_url()
        with open(dest, "wb") as f:
            shutil.copyfileobj(resp, f)
    except (urllib.error.URLError, OSError) as exc:
        raise PipelineZooError(f"Download failed for {url}: {exc}") from exc


def _download_model(asset_id):
    """Download/convert a model asset into the cache directory.

    For URL-based models (yolov5m): download directly from GitHub.
    For script-based models: run conversion script via docker exec.
    No install/copy step — path_vars point directly at the cache.
    """
    from src.docker import docker_exec

    entry = _MODELS[asset_id]
    cache_dir = entry["cache_dir"]

    # Check if already cached
    check = _check_files(entry)
    if all((ASSETS_DIR / f).is_file() for f in check):
        print(f"    Using cached model files for {asset_id}")
        return

    if "urls" in entry:
        # Direct download (e.g. yolov5m pre-converted from GitHub)
        for url, dest_rel in entry["urls"]:
            dest_path = ASSETS_DIR / dest_rel
            if not dest_path.is_file():
                _download_url(url, dest_path)
    elif "zip_url" in entry:
        # Download ZIP, extract specific files to target paths
        import io
        import zipfile

        zip_url = entry["zip_url"]
        zip_files = entry["zip_files"]
        _validate_url(zip_url)
        print(f"    Downloading {zip_url.rsplit('/', 1)[-1]}...")
        try:
            resp = urllib.request.urlopen(zip_url, timeout=300)  # nosec B310
            zip_data = io.BytesIO(resp.read())
        except (urllib.error.URLError, OSError) as exc:
            raise PipelineZooError(
                f"Download failed for {zip_url}: {exc}") from exc
        with zipfile.ZipFile(zip_data) as zf:
            for src_path, dest_rel in zip_files:
                dest_path = ASSETS_DIR / dest_rel
                dest_path.parent.mkdir(parents=True, exist_ok=True)
                # Validate that src_path exists in the ZIP and is safe
                if src_path not in zf.namelist():
                    raise PipelineZooError(
                        f"File '{src_path}' not found in {zip_url}")
                with zf.open(src_path) as src, open(dest_path, "wb") as dst:
                    shutil.copyfileobj(src, dst)
                print(f"    Extracted {dest_path.name}")
    elif "downloader" in entry:
        # Run downloader script via docker exec
        if "pre_setup" in entry:
            pre_cmd = entry["pre_setup"]
            print(f"    Running {Path(pre_cmd[1]).name}...")
            docker_exec("pipeline-zoo-assets", pre_cmd)

        cmd = entry["downloader"]
        print(f"    Running {Path(cmd[1]).name}...")
        docker_exec("pipeline-zoo-assets", cmd)
    else:
        raise PipelineZooError(
            f"Model '{asset_id}' has no downloader or URLs and is not cached.\n"
            f"  Expected files in: {ASSETS_DIR / cache_dir}")

    # Download model-proc JSON if specified as (name, url) tuple
    proc = entry.get("model_proc")
    if isinstance(proc, tuple):
        proc_name, proc_url = proc
        dst = ASSETS_DIR / cache_dir / proc_name
        if not dst.is_file():
            _download_url(proc_url, dst)


def ensure_assets(pipeline_dir, mode, data=None, asset_port=None):
    """Check pipeline assets exist; auto-download if missing.

    Script-based models run inside the assets-download container via docker exec.
    URL-based models (yolov5m) are downloaded directly.
    Videos are transcoded by the video-download service (one-shot).

    Returns immediately if all assets are present.
    Raises PipelineZooError if download fails.
    """
    from src.docker import (
        validate_compose, compose_up, compose_stop, exec_video_download,
        generate_env_file, wait_for_container,
    )

    if data is None:
        pj_path = pipeline_dir / "pipeline.json"
        data = json.loads(pj_path.read_text())
    assets = data.get("assets", {})

    missing_models = []
    missing_videos = []

    for key, asset_id in assets.items():
        if key == "input_video":
            vreg = resolve_video(asset_id)
            check = ASSETS_DIR / vreg["check_file"]
            if not check.is_file():
                missing_videos.append((key, asset_id))
        else:
            if asset_id not in _MODELS:
                available = ", ".join(sorted(_MODELS))
                raise PipelineZooError(
                    f"Unknown model asset '{asset_id}' for key '{key}'.\n"
                    f"  Available models: {available}")
            for f in _check_files(_MODELS[asset_id]):
                if not (ASSETS_DIR / f).is_file():
                    missing_models.append((key, asset_id))
                    break

    if not missing_models and not missing_videos:
        return  # All assets present

    print(f"\n  Missing assets for {mode} pipeline:")
    for key, asset_id in missing_models:
        entry = _MODELS[asset_id]
        cached = all((ASSETS_DIR / f).is_file() for f in _check_files(entry))
        tag = " (cached)" if cached else " (download + convert)"
        print(f"    [{key}] {asset_id}{tag}")
    for key, url in missing_videos:
        vreg = resolve_video(url)
        if not url.startswith("http") and url in _VIDEOS:
            print(f"    [{key}] {vreg['mp4_name']} (download)")
        else:
            print(f"    [{key}] {vreg['mp4_name']} (download + transcode + loop)")

    print("\n  Downloading missing assets...")
    print()

    # Ensure assets directory exists and is writable by the container
    ASSETS_DIR.mkdir(parents=True, exist_ok=True)
    ASSETS_DIR.chmod(0o777)  # noqa: S103

    # Ensure .env file exists
    if not ENV_FILE.is_file():
        generate_env_file("/dev/null", DEFAULT_IMAGE, REST_PORT, RTSP_PORT)

    # ── Start assets-download container if anything is missing ───────────────
    # Direct-download videos (local filename with URL in _VIDEOS) don't need
    # the Docker container — only Pexels URLs that require transcode do.
    pexels_videos = [(k, u) for k, u in missing_videos
                     if u.startswith("http") or u not in _VIDEOS]
    direct_videos = [(k, u) for k, u in missing_videos
                     if not u.startswith("http") and u in _VIDEOS]

    needs_container = any(
        "downloader" in _MODELS[a]
        for _k, a in missing_models
    ) or bool(pexels_videos)

    if needs_container:
        print("  Starting assets-download container...")
        validate_compose()
        compose_up("download")
        wait_for_container("assets-download", profile="download")
        print("  Container ready.\n")

    # ── Phase 1: Model downloads ────────────────────────────────────────────
    for key, asset_id in missing_models:
        print(f"  Downloading {asset_id}...")
        _download_model(asset_id)
        print()

    # ── Phase 2a: Direct video downloads (from _VIDEOS registry) ──────────
    for _key, filename in direct_videos:
        vreg = resolve_video(filename)
        dst = ASSETS_DIR / vreg["check_file"]
        dst.parent.mkdir(parents=True, exist_ok=True)
        print(f"  Downloading {filename}...")
        _download_url(_VIDEOS[filename], dst)
        print()

    # ── Phase 2b: Video download + transcode (Pexels URLs) ─────────────────
    if pexels_videos:
        print("  Starting video download + transcode...")
        video_args = []
        for _key, url in pexels_videos:
            vreg = resolve_video(url)
            video_args.extend([
                "--url", url,
                "--output-path", vreg["check_file"],
                "--loop-count", "100",
            ])
        exec_video_download(video_args)
        print()

    # ── Stop assets-download container ──────────────────────────────────────
    if needs_container:
        print("  Stopping assets-download container...")
        compose_stop("assets-download")

    # ── Verify ──────────────────────────────────────────────────────────────
    still_missing = []
    for key, asset_id in missing_models:
        for f in _check_files(_MODELS[asset_id]):
            if not (ASSETS_DIR / f).is_file():
                still_missing.append(f)
    for key, url in missing_videos:
        vreg = resolve_video(url)
        if not (ASSETS_DIR / vreg["check_file"]).is_file():
            still_missing.append(vreg["check_file"])

    if still_missing:
        msg = "Some assets still missing after download:\n"
        for f in still_missing:
            msg += f"  {f}\n"
        raise PipelineZooError(msg)

    print("  All assets ready.\n")
