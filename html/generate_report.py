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

ROOT = Path(__file__).resolve().parent.parent
RESULTS = ROOT / "results"
HTML_DIR = Path(__file__).resolve().parent
DATA_JSON = HTML_DIR / "data.json"
CSV_PATTERN = re.compile(r"e2e-edge-pipeline_.*\.csv$")

@dataclass
class Record:
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


def parse_float(value: str | None) -> float | None:
    """Parse float field, returning None for NA/missing values."""
    return float(value) if value and value.upper() != 'NA' else None


def read_csvs():
    """Read all CSV benchmark files from device-specific subdirectories and return parsed records."""
    records: list[Record] = []
    if not RESULTS.exists():
        return records
    
    # Scan all subdirectories in results/
    for devconfig_dir in RESULTS.iterdir():
        if not devconfig_dir.is_dir():
            continue
            
        print(f"[ Info ] Scanning {devconfig_dir.name}/ for results files...")
        
        for res_file in devconfig_dir.iterdir():
            if not res_file.is_file() or not CSV_PATTERN.search(res_file.name):
                continue
                
            try:
                with res_file.open("r", newline="") as fh:
                    rows = list(csv.reader(fh))
                    if len(rows) < 2:
                        continue
                    
                    # Create dict by zipping header with data row
                    res_dict = dict(zip(rows[0], rows[1]))
                    
                    # Build pipeline string based on available columns
                    if "Pipeline1" in res_dict and "Pipeline2" in res_dict:
                        pipeline_data = f"Pipeline1: {res_dict['Pipeline1']}... | Pipeline2: {res_dict['Pipeline2']}..."
                    elif "Pipeline1" in res_dict:
                        pipeline_data = res_dict["Pipeline1"]
                    else:
                        pipeline_data = res_dict.get("Pipeline", "")
                    
                    rec = Record(
                        timestamp=res_dict.get("Timestamp", ""),
                        system=res_dict.get("System", ""),
                        duration=res_dict.get("Duration (s)", ""),
                        cores=res_dict.get("Cores Pinned", ""),
                        config=res_dict.get("Pipeline Config", ""),
                        detect=res_dict.get("Detect Device", ""),
                        classify=res_dict.get("Classify Device", ""),
                        batch=res_dict.get("Batch", ""),
                        throughput=parse_float(res_dict.get("Throughput (fps)")),
                        per_stream=parse_float(res_dict.get("Throughput per Stream (fps/#)")),
                        theoretical=res_dict.get("Theoretical Stream Density (@30fps±5%)", ""),
                        streams=res_dict.get("Measured Stream Density (#)", ""),
                        pipeline=pipeline_data,
                        device_config=res_dict.get("Device Configuration"),
                        avg_power=parse_float(res_dict.get("Avg Power (W)")),
                        efficiency=parse_float(res_dict.get("Efficiency (FPS/W)")),
                    )
                    records.append(rec)
            except Exception as e:
                print(f"[ Warning ] Failed to parse {res_file.name}: {e}")
                continue
    
    return records


def aggregate(records: list[Record]):
    """Aggregate records by configuration groups."""
    groups = defaultdict(list)
    for r in records:
        # Use device_config for grouping if available, otherwise fall back to detect/classify
        if r.device_config:
            key = (r.config, r.device_config, r.batch)
        else:
            key = (r.config, f"{r.detect}-{r.classify}", r.batch)
        groups[key].append(r)
        
    summary: list[dict] = []
    for key, recs in groups.items():
        cfg, device_desc, batch = key
        
        # Calculate average throughput
        thr = [r.throughput for r in recs if r.throughput is not None]
        
        # Calculate average power and efficiency
        pwr = [r.avg_power for r in recs if r.avg_power is not None]
        eff = [r.efficiency for r in recs if r.efficiency is not None]
        
        # Parse theoretical streams (numeric if possible)
        theo_vals: list[float] = []
        for r2 in recs:
            try:
                if r2.theoretical and r2.theoretical.lower() not in {"na", "nan"}:
                    theo_vals.append(float(r2.theoretical))
            except ValueError:
                continue
                
        # Extract detect/classify from first record for compatibility
        first_rec = recs[0]
        
        summary.append({
            "config": cfg,
            "device_config": device_desc,
            "detect": first_rec.detect,
            "classify": first_rec.classify,
            "batch": batch,
            "runs": len(recs),
            "avg_throughput": round(mean(thr), 2) if thr else None,
            "theoretical_streams": int(round(mean(theo_vals))) if theo_vals else None,
            "avg_power": round(mean(pwr), 2) if pwr else None,
            "efficiency": round(mean(eff), 2) if eff else None,
        })
        
    # Custom config order: light, medium, heavy
    order_map = {"light": 0, "medium": 1, "heavy": 2}
    summary.sort(key=lambda x: (
        order_map.get(x["config"], 99), 
        x["device_config"], 
        int(x["batch"])
    ))
    
    return summary


def write_data_json(summary, raw_records):
    """Write the aggregated data to JSON file for the dashboard."""
    data = {
        "summary": summary,
        "raw": [asdict(r) for r in raw_records],
        "generated": "Generated by generate_report.py",
        "timestamp": str(Path(RESULTS).stat().st_mtime) if RESULTS.exists() else None
    }
    
    with DATA_JSON.open('w', encoding='utf-8') as f:
        json.dump(data, f, indent=2)


def main():
    """Main execution function."""
    records = read_csvs()
    if not records:
        print("[ Error ] No benchmark CSV files found in results/. Run benchmarks first.")
        return 1
        
    summary = aggregate(records)
    write_data_json(summary, records)
    
    print(f"[ Info ] Generated data file: {DATA_JSON}")
    print(f"[ Info ] Dashboard ready at: {HTML_DIR / 'index.html'}")
    print(f"[ Info ] Processed {len(records)} records into {len(summary)} summary entries")
    
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
