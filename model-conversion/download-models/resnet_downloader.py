# SPDX-FileCopyrightText: (C) 2024 - 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

import argparse
from pathlib import Path
from typing import Optional, Union
from PIL import Image

import openvino as ov
import torch
from torchvision import datasets, transforms
import kagglehub

from common import (
    build_classify_dataloader,
    quantize_with_nncf,
    save_openvino_models,
    top1_accuracy_ov,
)

# ResNet-specific transforms
RESNET_TRANSFORM = transforms.Compose([
    transforms.Resize(256, interpolation=Image.BILINEAR),
    transforms.CenterCrop(224),
    transforms.PILToTensor(),
    transforms.Lambda(lambda x: x.to(torch.float32) / 255.0),
])

def download_resnet() -> Path:
    model_path = kagglehub.model_download("google/resnet-v1/tensorFlow2/50-classification")
    print(f"[ Download ] Resnet-50 Downloaded to: {model_path}")
    return model_path

def main(
    imagenet_dir: Union[str, Path],
    samples: int = 512,
    subset_size: Optional[int] = None,
    output_dir: Union[str, Path] = Path("models/resnet-50"),
) -> None:

    model_path = download_resnet()
    fp32_model = ov.convert_model(model_path, input=[1, 224, 224, 3])

    ppp = ov.preprocess.PrePostProcessor(fp32_model)
    ppp.input().tensor().set_layout(ov.Layout("NCHW"))
    ppp.input().model().set_layout(ov.Layout("NHWC"))
    fp32_model = ppp.build()
    
    # Try ImageNet, fallback to CIFAR-100
    if imagenet_dir:
        print("\n[ Loading ] Loading ImageNet Validation dataset.")
        try:
            val_loader = build_classify_dataloader(
                datasets.ImageNet, RESNET_TRANSFORM, imagenet_dir,
                samples=samples, split="val"
            )
            use_imagenet = True
        except Exception as e:
            print(f"\n[ Error ] Failed to load ImageNet: {e}.")
            print("[ Loading ] Loading CIFAR-100 Dataset as backup.")
            val_loader = build_classify_dataloader(
                datasets.CIFAR100, RESNET_TRANSFORM, "datasets",
                samples=samples, train=False, download=True
            )
            use_imagenet = False
    else:
        print("\n[ Loading ] ImageNet path not provided. Downloading CIFAR-100 as proxy dataset.")
        val_loader = build_classify_dataloader(
            datasets.CIFAR100, RESNET_TRANSFORM, "datasets",
            samples=samples, train=False, download=True
        )
        use_imagenet = False

    print("\n[ Quantization ] Quantization to INT8 in progress.")
    input_name = fp32_model.input(0).get_any_name()
    quant_subset = subset_size if subset_size is not None else samples
    int8_model = quantize_with_nncf(fp32_model, val_loader, input_name, subset_size=quant_subset)

    fp32_out, int8_out = save_openvino_models(fp32_model, int8_model, output_dir, prefix="resnet-50")
    print(f"\n[ Saved ] Saved INT8 model to {int8_out}.")
    
    if use_imagenet:
        print("\n[ Accuracy ] FP32 accuracy check in progress.")
        fp32_top1 = top1_accuracy_ov(fp32_model, "CPU", val_loader)
        print(f"FP32 Top-1 Accuracy: {fp32_top1:.4f}%")

        print("\n[ Accuracy ] INT8 accuracy check in progress.")
        int8_top1 = top1_accuracy_ov(int8_model, "CPU", val_loader)
        print(f"INT8 Top-1 Accuracy: {int8_top1:.4f}%")

        print("\n[Summary]")
        print(f"FP32 OpenVINO Accuracy: {fp32_top1:.4f}%")
        print(f"INT8 OpenVINO Accuracy: {int8_top1:.4f}%")
    else:
        print("\n[ Info ] Accuracy checking only supported with ImageNet Dataset.")
        print("[ Info ] Please download the official ImageNet Val and Devkit tar files for accuracy checking.")

if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="NNCF INT8 Quantizer for ResNet-50")
    ap.add_argument(
        "-i",
        "--imagenet-root",
        default=None,
        help="Path to ImageNet packages directory containing tar.gz files. (Optional for accuracy validation)",
    )
    ap.add_argument(
        "-s",
        "--calib-subset",
        type=int,
        default=512,
        help="Number of images to sample for accuracy checks.",
    )
    ap.add_argument(
        "--subset-size",
        type=int,
        default=None,
        help="Number of images for NNCF calibration. Defaults to calib-subset if unset.",
    )
    ap.add_argument(
        "-o",
        "--output-dir",
        type=str,
        default=str(Path("models/resnet-50")),
        help="Directory to save converted models (default: models/resnet-50).",
    )
    args = ap.parse_args()

    main(
        args.imagenet_root,
        samples=args.calib_subset,
        subset_size=args.subset_size,
        output_dir=args.output_dir,
    )
