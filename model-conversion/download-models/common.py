# SPDX-FileCopyrightText: (C) 2024 - 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

import random
import urllib.parse
from pathlib import Path
from typing import Any, Tuple, Union, Optional

import hashlib
import numpy as np
import openvino as ov
import requests
from openvino import Core
from torch.utils.data import DataLoader, Subset
from tqdm import tqdm


def download_file(
    url: str,
    filename: Optional[str] = None,
    directory: Optional[Union[str, Path]] = None,
) -> Path:
    """Download file from URL with progress bar."""
    filename = filename or Path(urllib.parse.urlparse(url).path).name
    filepath = Path(directory) / filename if directory is not None else Path(filename)
    
    if filepath.exists():
        print(f"[ Download ] '{filepath}' already exists.")
        return filepath.resolve()

    if directory is not None:
        Path(directory).mkdir(parents=True, exist_ok=True)

    response = requests.get(url=url, stream=True, timeout=30)
    response.raise_for_status()
    
    filesize = int(response.headers.get("Content-length", 0))
    with tqdm(total=filesize, unit="B", unit_scale=True, desc=filename) as pbar:
        with open(filepath, "wb") as f:
            for chunk in response.iter_content(chunk_size=8192):
                f.write(chunk)
                pbar.update(len(chunk))
    
    response.close()
    return filepath.resolve()

def validate_hash(file_path: str, expected_hash: str) -> None:
    """
    Verify that hash matches the calculated hash of the file.

    :param file_path: Path to file.
    :param expected_hash: Expected hash of the file.
    """
    with open(file_path, "rb") as hash_file:
        downloaded_hash = hashlib.sha3_512(hash_file.read()).hexdigest()
    if downloaded_hash != expected_hash:
        raise ValueError(f"Downloaded file {file_path} does not match the required hash.")

def build_classify_dataloader(
    dataset_class,
    transform,
    root: Union[str, Path],
    batch_size: int = 1,
    workers: int = 4,
    samples: int = -1,
    shuffle: bool = False,
    **dataset_kwargs
) -> DataLoader:
    """Data loader builder for classification datasets (ImageNet, CIFAR)."""
    ds = dataset_class(root=root, transform=transform, **dataset_kwargs)
    
    if samples > 0 and samples < len(ds):
        rng = random.Random(0) # nosec B311
        idx = list(range(len(ds)))
        rng.shuffle(idx)
        ds = Subset(ds, idx[:samples])
    
    return DataLoader(
        ds,
        batch_size=batch_size,
        shuffle=shuffle,
        num_workers=workers,
        pin_memory=False,
        drop_last=False,
    )

def pick_softmax_output(compiled: Any) -> Any:
    for o in compiled.outputs:
        names = o.get_tensor().get_names()
        for n in names:
            if "softmax" in str(n).lower():
                return o
    return compiled.outputs[0]

def drop_background(probs: np.ndarray) -> np.ndarray:
    if probs.ndim == 2 and probs.shape[1] == 1001:
        return probs[:, 1:]
    return probs

def top1_accuracy_ov(
    model_or_path: Union[str, Path, "ov.Model"], device: str, loader: DataLoader
) -> float:

    core = Core()
    compiled = core.compile_model(model_or_path, device)
    out = pick_softmax_output(compiled)

    hits, seen = 0, 0
    for images, labels in loader:
        arr = images.numpy()
        probs = compiled(arr)[out]
        probs = drop_background(probs)
        preds = np.argmax(probs, axis=1)
        y = labels.numpy().astype(np.int64)
        hits += int(np.sum(preds == y))
        seen += y.shape[0]
    return (hits / max(1, seen)) * 100.0

def quantize_with_nncf(
    fp32_model: "ov.Model", calib_loader: DataLoader, input_name: str, subset_size: int
) -> "ov.Model":
    import nncf
    from typing import Tuple as _Tuple
    import torch as _torch

    def transform_fn(data_item: _Tuple[_torch.Tensor, _torch.Tensor]):
        images, _ = data_item
        return {input_name: images.numpy()}

    calib_dataset = nncf.Dataset(calib_loader, transform_fn)
    return nncf.quantize(
        model=fp32_model,
        calibration_dataset=calib_dataset,
        preset=nncf.QuantizationPreset.PERFORMANCE,
        subset_size=subset_size,
        fast_bias_correction=True,
    )

def save_openvino_models(
    fp32_model: "ov.Model",
    int8_model: "ov.Model",
    output_dir: Union[str, Path],
    prefix: str,
) -> Tuple[Path, Path]:
    out_dir = Path(output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    fp32_out = out_dir / f"{prefix}_fp32.xml"
    int8_out = out_dir / f"{prefix}_int8.xml"
    ov.save_model(fp32_model, str(fp32_out), compress_to_fp16=False)
    ov.save_model(int8_model, str(int8_out))
    return fp32_out, int8_out
