# SPDX-FileCopyrightText: (C) 2024 - 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

from __future__ import annotations
import csv
import json
import re
from dataclasses import dataclass, asdict
from collections import defaultdict
from pathlib import Path
from statistics import mean

ROOT = Path(__file__).resolve().parent.parent.parent
EDGE_RESULTS = ROOT / "collateral" / "results" / "edge-ai-pipelines"
VISION_RESULTS = ROOT / "collateral" / "results" / "vision-benchmarks"
MEDIA_RESULTS = ROOT / "collateral" / "results" / "media-benchmarks"
GENAI_RESULTS = ROOT / "collateral" / "results" / "genai-benchmarks"
HTML_DIR = Path(__file__).resolve().parent
DATA_JSON = HTML_DIR / "data.json"

EDGE_CSV_PATTERN = re.compile(r"e2e-edge-pipeline_.*\.csv$")
VISION_CSV_PATTERN = re.compile(r"vision-benchmark_.*\.csv$")
MEDIA_CSV_PATTERN = re.compile(r"media-benchmark_.*\.csv$")
GENAI_CSV_PATTERN = re.compile(r"genai-benchmark_.*\.csv$")


# =============================================================================
# Shared utilities
# =============================================================================

def parse_float(value: str | None) -> float | None:
    return float(value) if value and value.upper() != 'NA' else None


def avg_field(records, field: str) -> float | None:
    """Average a numeric field across records, skipping None values."""
    vals = [getattr(r, field) for r in records if getattr(r, field) is not None]
    return round(mean(vals), 2) if vals else None


def parse_theo_strings(records, field: str) -> list[float]:
    """Parse a string field (e.g. 'theoretical') into floats, skipping NA/NaN."""
    vals: list[float] = []
    for r in records:
        raw = getattr(r, field, "")
        try:
            if raw and raw.lower() not in {"na", "nan"}:
                vals.append(float(raw))
        except (ValueError, AttributeError):
            continue
    return vals


def read_csvs(
    results_dir: Path,
    pattern: re.Pattern,
    label: str,
    field_map: dict[str, tuple[str, type]],
    post_process=None,
) -> list[dict]:
    """Generic CSV reader that walks results_dir/<subdir>/<csv files>.

    field_map: {CSV column name: (dataclass field name, converter)}
    post_process: Optional callable(res_dict, kwargs) -> kwargs
        for custom logic that can't be expressed as a simple field map.
    """
    records: list[dict] = []
    if not results_dir.exists():
        return records

    for subdir in results_dir.iterdir():
        if not subdir.is_dir():
            continue
        print(f"[ Info ] Scanning {label}/{subdir.name}/ ...")
        for res_file in subdir.iterdir():
            if not res_file.is_file() or not pattern.search(res_file.name):
                continue
            try:
                with res_file.open("r", newline="") as fh:
                    rows = list(csv.reader(fh))
                    if len(rows) < 2:
                        continue
                    res_dict = dict(zip(rows[0], rows[1]))
                    kwargs: dict = {}
                    for csv_col, (field_name, converter) in field_map.items():
                        kwargs[field_name] = converter(res_dict.get(csv_col, ""))
                    if post_process:
                        kwargs = post_process(res_dict, kwargs)
                    records.append(kwargs)
            except (csv.Error, ValueError, KeyError) as e:
                print(f"[ Warning ] Failed to parse {res_file.name}: {e}")
    return records


# =============================================================================
# Edge AI Pipelines
# =============================================================================

@dataclass
class EdgeRecord:
    timestamp: str
    system: str
    duration: str
    cores: str
    config: str
    detect: str
    classify: str
    batch: str
    throughput: float | None
    per_stream: float | None
    theoretical: str
    streams: str
    pipeline: str
    device_config: str | None = None
    avg_power: float | None = None
    efficiency: float | None = None
    primary_fps: float | None = None
    secondary_fps: float | None = None


EDGE_FIELD_MAP: dict[str, tuple[str, type]] = {
    "Timestamp":                           ("timestamp", str),
    "System":                              ("system", str),
    "Duration (s)":                        ("duration", str),
    "Cores Pinned":                        ("cores", str),
    "Pipeline Config":                     ("config", str),
    "Detect Device":                       ("detect", str),
    "Classify Device":                     ("classify", str),
    "Batch":                               ("batch", str),
    "Throughput (fps)":                    ("throughput", parse_float),
    "Throughput per Stream (fps/#)":       ("per_stream", parse_float),
    "Theoretical Stream Density (@30fps)": ("theoretical", str),
    "Measured Stream Density (#)":         ("streams", str),
    "Device Configuration":                ("device_config", lambda v: v or None),
    "Avg Power (W)":                       ("avg_power", parse_float),
    "Efficiency (FPS/W)":                  ("efficiency", parse_float),
    "Primary FPS":                         ("primary_fps", parse_float),
    "Secondary FPS":                       ("secondary_fps", parse_float),
}


def _edge_post(res_dict: dict, kwargs: dict) -> dict:
    """Build the pipeline field from Pipeline1/Pipeline2/Pipeline columns."""
    if "Pipeline1" in res_dict and "Pipeline2" in res_dict:
        kwargs["pipeline"] = (
            f"Pipeline1: {res_dict['Pipeline1']}... | "
            f"Pipeline2: {res_dict['Pipeline2']}..."
        )
    elif "Pipeline1" in res_dict:
        kwargs["pipeline"] = res_dict["Pipeline1"]
    else:
        kwargs["pipeline"] = res_dict.get("Pipeline", "")
    return kwargs


def read_edge_csvs() -> list[EdgeRecord]:
    raw = read_csvs(EDGE_RESULTS, EDGE_CSV_PATTERN, "edge-ai-pipelines",
                    EDGE_FIELD_MAP, _edge_post)
    return [EdgeRecord(**r) for r in raw]


def aggregate_edge(records: list[EdgeRecord]) -> list[dict]:
    groups = defaultdict(list)
    for r in records:
        if r.device_config:
            key = (r.config, r.device_config, r.batch)
        else:
            key = (r.config, f"{r.detect}-{r.classify}", r.batch)
        groups[key].append(r)

    summary: list[dict] = []
    for key, recs in groups.items():
        cfg, device_desc, batch = key
        theo_vals = parse_theo_strings(recs, "theoretical")
        pri = [r.primary_fps for r in recs if r.primary_fps is not None]
        sec = [r.secondary_fps for r in recs if r.secondary_fps is not None]
        first_rec = recs[0]
        summary.append({
            "config": cfg,
            "device_config": device_desc,
            "detect": first_rec.detect,
            "classify": first_rec.classify,
            "batch": batch,
            "runs": len(recs),
            "avg_throughput": avg_field(recs, "throughput"),
            "theoretical_streams": int(round(mean(theo_vals))) if theo_vals else None,
            "avg_power": avg_field(recs, "avg_power"),
            "efficiency": avg_field(recs, "efficiency"),
            "primary_fps": round(mean(pri), 2) if pri else None,
            "secondary_fps": round(mean(sec), 2) if sec else None,
            "primary_theoretical": int(mean(pri) / 30) if pri else None,
            "secondary_theoretical": int(mean(sec) / 30) if sec else None,
        })

    order_map = {"light": 0, "medium": 1, "heavy": 2}
    device_order = {"GPU-Only": 0, "NPU-Only": 1}
    def device_sort_key(dc):
        if dc in device_order: return device_order[dc]
        if "Split" in dc: return 2
        if "Concurrent" in dc: return 3
        return 4
    summary.sort(key=lambda x: (
        order_map.get(x["config"], 99),
        device_sort_key(x["device_config"]),
        int(x["batch"])
    ))
    return summary


# =============================================================================
# Vision Benchmarks
# =============================================================================

@dataclass
class VisionRecord:
    timestamp: str
    system: str
    model: str
    device: str
    mode: str
    batch: str
    duration: str
    throughput: float | None
    median_latency: float | None
    concurrent: str
    avg_power: float | None = None
    efficiency: float | None = None
    primary_fps: float | None = None
    secondary_fps: float | None = None


VISION_FIELD_MAP: dict[str, tuple[str, type]] = {
    "Timestamp":            ("timestamp", str),
    "System":               ("system", str),
    "Model":                ("model", str),
    "Device":               ("device", str),
    "Mode":                 ("mode", str),
    "Batch":                ("batch", str),
    "Duration (s)":         ("duration", str),
    "Throughput (fps)":     ("throughput", parse_float),
    "Median Latency (ms)":  ("median_latency", parse_float),
    "Concurrent":           ("concurrent", lambda v: v if v else "None"),
    "Avg Power (W)":        ("avg_power", parse_float),
    "Efficiency (FPS/W)":   ("efficiency", parse_float),
    "Primary FPS":          ("primary_fps", parse_float),
    "Secondary FPS":        ("secondary_fps", parse_float),
}


def _vision_post(res_dict: dict, kwargs: dict) -> dict:
    """For older CSVs without per-device columns: infer primary_fps."""
    if kwargs["primary_fps"] is None and kwargs["concurrent"] in ("None", ""):
        kwargs["primary_fps"] = kwargs["throughput"]
    return kwargs


def read_vision_csvs() -> list[VisionRecord]:
    raw = read_csvs(VISION_RESULTS, VISION_CSV_PATTERN, "vision-benchmarks",
                    VISION_FIELD_MAP, _vision_post)
    return [VisionRecord(**r) for r in raw]


def aggregate_vision(records: list[VisionRecord]) -> list[dict]:
    groups = defaultdict(list)
    for r in records:
        key = (r.model, r.device, r.mode, r.batch, r.concurrent)
        groups[key].append(r)

    MODEL_ORDER = [
        "yolov11n_640x640", "yolov5m_640x640", "yolov11m_640x640",
        "resnet-v1-50-tf", "mobilenet-v2-1.0-224-tf",
    ]
    DEVICE_ORDER = {"GPU": 0, "NPU": 1, "GPU-NPU-Concurrent": 2}
    MODE_ORDER = {"latency": 0, "tput": 1}

    summary: list[dict] = []
    for key, recs in groups.items():
        model, device, mode, batch, concurrent = key
        summary.append({
            "model": model, "device": device, "mode": mode,
            "batch": batch, "concurrent": concurrent,
            "runs": len(recs),
            "avg_throughput": avg_field(recs, "throughput"),
            "median_latency": avg_field(recs, "median_latency"),
            "avg_power": avg_field(recs, "avg_power"),
            "efficiency": avg_field(recs, "efficiency"),
            "primary_fps": avg_field(recs, "primary_fps"),
            "secondary_fps": avg_field(recs, "secondary_fps"),
        })

    summary.sort(key=lambda x: (
        MODEL_ORDER.index(x["model"]) if x["model"] in MODEL_ORDER else 99,
        DEVICE_ORDER.get(x["device"], 99),
        MODE_ORDER.get(x["mode"], 99),
        int(x["batch"]),
    ))
    return summary


# =============================================================================
# Media Benchmarks
# =============================================================================

@dataclass
class MediaRecord:
    timestamp: str
    system: str
    media: str
    codec: str
    resolution: str
    streams: str
    duration: str
    throughput: float | None
    per_stream: float | None
    theoretical: str
    target_fps: str
    avg_power: float | None = None
    efficiency: float | None = None


MEDIA_FIELD_MAP: dict[str, tuple[str, type]] = {
    "Timestamp":                     ("timestamp", str),
    "System":                        ("system", str),
    "Media":                         ("media", str),
    "Codec":                         ("codec", str),
    "Resolution":                    ("resolution", str),
    "Streams":                       ("streams", str),
    "Duration (s)":                  ("duration", str),
    "Throughput (fps)":              ("throughput", parse_float),
    "Throughput per Stream (fps/#)": ("per_stream", parse_float),
    "Theoretical Stream Density":    ("theoretical", str),
    "Target FPS":                    ("target_fps", str),
    "Avg Power (W)":                 ("avg_power", parse_float),
    "Efficiency (FPS/W)":            ("efficiency", parse_float),
}


def read_media_csvs() -> list[MediaRecord]:
    raw = read_csvs(MEDIA_RESULTS, MEDIA_CSV_PATTERN, "media-benchmarks",
                    MEDIA_FIELD_MAP)
    return [MediaRecord(**r) for r in raw]


def aggregate_media(records: list[MediaRecord]) -> list[dict]:
    groups = defaultdict(list)
    for r in records:
        key = (r.media, r.codec, r.resolution, r.streams)
        groups[key].append(r)

    CODEC_ORDER = {"h265": 0, "h264": 1}
    RES_ORDER = {"1080p": 0, "4k": 1}

    summary: list[dict] = []
    for key, recs in groups.items():
        media, codec, resolution, streams = key
        theo_vals = parse_theo_strings(recs, "theoretical")
        summary.append({
            "media": media, "codec": codec,
            "resolution": resolution, "streams": streams,
            "target_fps": recs[0].target_fps,
            "runs": len(recs),
            "avg_throughput": avg_field(recs, "throughput"),
            "theoretical_streams": int(round(mean(theo_vals))) if theo_vals else None,
            "avg_power": avg_field(recs, "avg_power"),
            "efficiency": avg_field(recs, "efficiency"),
        })

    summary.sort(key=lambda x: (
        CODEC_ORDER.get(x["codec"], 99),
        RES_ORDER.get(x["resolution"], 99),
        x["media"],
        int(x["streams"]),
    ))
    return summary


# =============================================================================
# GenAI Benchmarks
# =============================================================================

@dataclass
class GenaiRecord:
    timestamp: str
    system: str
    model: str
    device: str
    precision: str
    type: str
    duration: str
    first_token_latency: float | None
    second_token_throughput: float | None
    avg_power: float | None = None
    efficiency: float | None = None
    cores: str = ""


GENAI_FIELD_MAP: dict[str, tuple[str, type]] = {
    "Timestamp":                    ("timestamp", str),
    "System":                       ("system", str),
    "Model":                        ("model", str),
    "Device":                       ("device", str),
    "Precision":                    ("precision", str),
    "Type":                         ("type", str),
    "Duration (s)":                 ("duration", str),
    "1st Token Latency (ms)":       ("first_token_latency", parse_float),
    "2nd Token Throughput (tok/s)":  ("second_token_throughput", parse_float),
    "Avg Power (W)":                ("avg_power", parse_float),
    "Efficiency (tpt/W)":           ("efficiency", parse_float),
    "Cores Pinned":                 ("cores", str),
}


def read_genai_csvs() -> list[GenaiRecord]:
    raw = read_csvs(GENAI_RESULTS, GENAI_CSV_PATTERN, "genai-benchmarks",
                    GENAI_FIELD_MAP)
    return [GenaiRecord(**r) for r in raw]


def aggregate_genai(records: list[GenaiRecord]) -> list[dict]:
    groups = defaultdict(list)
    for r in records:
        key = (r.model, r.device, r.precision, r.type)
        groups[key].append(r)

    MODEL_ORDER = [
        "llama-3.2-3b-instruct", "deepseek-qwen-1.5b", "mistral-7b",
        "minicpm-v-2.6", "gemma-3-4b-it", "phi-4-multimodal",
    ]
    DEVICE_ORDER = {"GPU": 0, "NPU": 1}
    PRECISION_ORDER = {"INT8_ASYM": 0, "INT4_SYM_CW": 1}

    summary: list[dict] = []
    for key, recs in groups.items():
        model, device, precision, model_type = key
        summary.append({
            "model": model, "device": device,
            "precision": precision, "type": model_type,
            "runs": len(recs),
            "first_token_latency": avg_field(recs, "first_token_latency"),
            "second_token_throughput": avg_field(recs, "second_token_throughput"),
            "avg_power": avg_field(recs, "avg_power"),
            "efficiency": avg_field(recs, "efficiency"),
        })

    summary.sort(key=lambda x: (
        MODEL_ORDER.index(x["model"]) if x["model"] in MODEL_ORDER else 99,
        DEVICE_ORDER.get(x["device"], 99),
        PRECISION_ORDER.get(x["precision"], 99),
    ))
    return summary


# =============================================================================
# Output
# =============================================================================

def write_data_json(edge_summary, edge_raw, vision_summary, vision_raw,
                    media_summary=None, media_raw=None,
                    genai_summary=None, genai_raw=None):
    data = {
        "edge_ai_pipelines": {
            "summary": edge_summary,
            "raw": [asdict(r) for r in edge_raw],
        },
        "vision_benchmarks": {
            "summary": vision_summary,
            "raw": [asdict(r) for r in vision_raw],
        },
        "media_benchmarks": {
            "summary": media_summary or [],
            "raw": [asdict(r) for r in (media_raw or [])],
        },
        "genai_benchmarks": {
            "summary": genai_summary or [],
            "raw": [asdict(r) for r in (genai_raw or [])],
        },
        "generated": "Generated by generate_report.py",
    }
    with DATA_JSON.open('w', encoding='utf-8') as f:
        json.dump(data, f, indent=2)


def main():
    edge_records = read_edge_csvs()
    vision_records = read_vision_csvs()
    media_records = read_media_csvs()
    genai_records = read_genai_csvs()

    if not edge_records and not vision_records and not media_records and not genai_records:
        print("[ Info ] No benchmark CSV files found in collateral/results/. Generating empty data.json.")

    edge_summary = aggregate_edge(edge_records) if edge_records else []
    vision_summary = aggregate_vision(vision_records) if vision_records else []
    media_summary = aggregate_media(media_records) if media_records else []
    genai_summary = aggregate_genai(genai_records) if genai_records else []

    write_data_json(edge_summary, edge_records, vision_summary, vision_records,
                    media_summary, media_records, genai_summary, genai_records)

    print(f"[ Info ] Generated data file: {DATA_JSON}")
    print(f"[ Info ] Dashboard ready at: {HTML_DIR / 'index.html'}")
    if edge_records:
        print(f"[ Info ] Edge AI Pipelines: {len(edge_records)} records -> {len(edge_summary)} summary entries")
    if vision_records:
        print(f"[ Info ] Vision Benchmarks: {len(vision_records)} records -> {len(vision_summary)} summary entries")
    if media_records:
        print(f"[ Info ] Media Benchmarks: {len(media_records)} records -> {len(media_summary)} summary entries")
    if genai_records:
        print(f"[ Info ] GenAI Benchmarks: {len(genai_records)} records -> {len(genai_summary)} summary entries")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
