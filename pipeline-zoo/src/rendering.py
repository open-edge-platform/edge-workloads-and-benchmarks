"""Pipeline rendering — template expansion and config generation."""

import functools
import json
import re
from pathlib import Path

from src.config import ZOO_DIR, PIPE_ROOT
from src.models import PipelineZooError, PlatformConfig, PipelineConfig


def parse_j2_params(j2_text):
    """Extract {% set var = "value" %} assignments from a .j2 file."""
    from jinja2 import Environment
    env = Environment(autoescape=True)
    ast = env.parse(j2_text)
    params = {}
    for node in ast.body:
        if node.__class__.__name__ == "Assign":
            target = node.target
            value = node.node
            if (target.__class__.__name__ == "Name" and
                    value.__class__.__name__ == "Const"):
                params[target.name] = str(value.value)
    return params


def render_pipeline(pipeline_dir, params_file, data=None):
    """Load pipeline.json + params .j2, substitute all variables.

    Args:
        pipeline_dir: Path to directory containing pipeline.json.
        params_file: Path to a params .j2 file.
        data: Optional pre-parsed pipeline.json dict (avoids re-read).

    Returns a single-line GStreamer pipeline string.
    """
    if data is None:
        pj_path = pipeline_dir / "pipeline.json"
        data = json.loads(pj_path.read_text())
    mode = data["pipelines"][0].get("mode", pipeline_dir.name)

    pipeline_lines = data["pipelines"][0]["pipeline"]
    pipeline_str = " ".join(line.strip() for line in pipeline_lines)

    # Load device params
    params = parse_j2_params(params_file.read_text())

    # Substitute device params
    for var, value in params.items():
        pipeline_str = pipeline_str.replace(f"${{{var}}}", value)

    # Substitute path variables (derived from pipeline.json assets + registry)
    assets = data.get("assets", {})
    pv = build_path_vars(assets, mode)
    for var, value in pv.items():
        pipeline_str = pipeline_str.replace(f"${{{var}}}", value)

    # Inject labels into gvaclassify elements that lack them
    pipeline_str = _inject_classify_labels(pipeline_str, assets)

    # Strip empty-value properties (e.g. "batch-size= nireq=") left by
    # device params that set a variable to "".
    pipeline_str = re.sub(r"\b\w[\w-]+=(?=\s|!|$)", "", pipeline_str)

    # Clean up residue from empty variable expansion
    pipeline_str = re.sub(r"  +", " ", pipeline_str).strip()

    # Detect unresolved ${var} placeholders
    unresolved = re.findall(r'\$\{[^}]+\}', pipeline_str)
    if unresolved:
        raise PipelineZooError(
            f"Unresolved variable(s) in pipeline: {', '.join(unresolved)}")

    return pipeline_str


@functools.lru_cache(maxsize=1)
def discover_pipelines() -> list[PipelineConfig]:
    """Discover all pipelines under ZOO_DIR.

    New layout: {use_case}/{mode}/pipeline.json with platform subdirs
    containing params_*.j2 files.

    Returns a sorted list of PipelineConfig instances.
    """
    pipelines: list[PipelineConfig] = []
    for pj_path in sorted(ZOO_DIR.glob("*/*/pipeline.json")):
        pipeline_dir = pj_path.parent
        rel = pipeline_dir.relative_to(ZOO_DIR)
        use_case, mode = rel.parts

        platforms: dict[str, PlatformConfig] = {}
        for sub in sorted(pipeline_dir.iterdir()):
            if not sub.is_dir():
                continue
            devices = sorted(
                f.stem.removeprefix("params_")
                for f in sub.glob("params_*.j2")
            )
            if devices:
                platforms[sub.name] = PlatformConfig(
                    name=sub.name, devices=devices, params_dir=sub)

        if not platforms:
            continue

        pipelines.append(PipelineConfig(
            use_case=use_case, mode=mode,
            pipeline_dir=pipeline_dir, platforms=platforms))

    return pipelines


def generate_config_json(pipeline_dir, params_file, pipeline_name, data=None):
    """Generate a DL Streamer Pipeline Server config.json dict."""
    pipeline_str = render_pipeline(pipeline_dir, params_file, data=data)

    pipeline_for_server = _adapt_pipeline_for_server(pipeline_str)

    config = {
        "config": {
            "pipelines": [
                {
                    "name": pipeline_name,
                    "source": "gstreamer",
                    "queue_maxsize": 50,
                    "pipeline": pipeline_for_server,
                    "auto_start": False,
                }
            ]
        }
    }
    return config


def _adapt_pipeline_for_server(pipeline_str):
    """Adapt a raw GStreamer pipeline for the pipeline server.

    Replace fakesink with gvametaconvert + gvametapublish + appsink.
    """
    pipeline_str = re.sub(
        r"fakesink\s+sync=false\s+async=false\s*$",
        "gvametaconvert add-empty-results=true name=metaconvert ! "
        "gvametapublish name=destination ! appsink name=appsink",
        pipeline_str,
    )
    return pipeline_str


def build_path_vars(assets, mode):
    """Build a path variable dict from asset IDs + registry metadata."""
    from src.assets import get_model_path_vars, resolve_video, ASSET_KEY_PREFIX

    path_vars = {}
    for asset_key, asset_id in assets.items():
        prefix = ASSET_KEY_PREFIX.get(asset_key)
        if prefix is None:
            continue

        if asset_key == "input_video":
            try:
                reg_vars = resolve_video(asset_id).get("path_vars", {})
            except (PipelineZooError, KeyError, ValueError):
                continue
        else:
            try:
                reg_vars = get_model_path_vars(asset_id)
            except KeyError:
                continue

        for suffix, rel_path in reg_vars.items():
            var_name = f"{prefix}-{suffix}"
            full_path = f"{PIPE_ROOT}/{rel_path}"
            path_vars[var_name] = full_path

    return path_vars


def _inject_classify_labels(pipeline_str, assets):
    """Inject labels= into gvaclassify elements when the asset registry
    specifies a labels file and the element doesn't already have one.

    This fixes model-proc files that declare converter=label but ship
    without a labels list — the labels path is injected at render time
    from asset metadata.
    """
    from src.assets import get_model_path_vars, get_model_labels

    # Collect labels paths for classification assets
    labels_map = {}  # model xml path substring → labels path
    for asset_key, asset_id in assets.items():
        if not asset_key.startswith("classification_model"):
            continue
        labels = get_model_labels(asset_id)
        if not labels:
            continue
        try:
            model_path = get_model_path_vars(asset_id).get("model-path", "")
        except KeyError:
            continue
        if model_path:
            # Extract the .xml filename (e.g. "resnet-50_int8.xml")
            xml_name = model_path.rsplit("/", 1)[-1]
            labels_map[xml_name] = labels

    if not labels_map:
        return pipeline_str

    # For each gvaclassify element, inject labels= if missing
    def _inject(match):
        element = match.group(0)
        if "labels=" in element:
            return element  # already has labels
        for xml_name, labels_path in labels_map.items():
            if xml_name in element:
                # Insert labels= after the model= property
                element = re.sub(
                    r'(model="[^"]*")',
                    rf'\1 labels="{labels_path}"',
                    element,
                    count=1,
                )
                break
        return element

    pipeline_str = re.sub(
        r'gvaclassify\s[^!]+',
        _inject,
        pipeline_str,
    )
    return pipeline_str
