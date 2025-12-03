# SPDX-FileCopyrightText: (C) 2024 - 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

"""
Initialize Ultralytics settings as one-time setup before running YOLO model conversion.
This script initializes the dataset dir and updates from cache.
"""
import argparse
from pathlib import Path
from ultralytics.utils import SETTINGS


def initialize_datasets_dir(dataset_dir: str) -> None:
    dataset_path = Path(dataset_dir).absolute()
    print(f"[ Init ] Setting Ultralytics datasets directory: {dataset_path}")
    
    SETTINGS['datasets_dir'] = str(dataset_path)
    SETTINGS._save()  
    print(f"[ Init ] Ultralytics settings updated and saved")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Initialize Ultralytics settings for YOLO model conversion"
    )
    parser.add_argument(
        "-i", "--dataset-dir",
        type=str,
        default="datasets",
        help="Directory for COCO dataset (default: datasets)"
    )
    
    args = parser.parse_args()
    initialize_datasets_dir(args.dataset_dir)
