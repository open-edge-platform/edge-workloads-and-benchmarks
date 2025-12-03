# SPDX-FileCopyrightText: (C) 2024 - 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

import argparse
from pathlib import Path
from typing import Optional, Union, Dict, Any
from zipfile import ZipFile

import torch
import openvino as ov
from tqdm import tqdm
from ultralytics import YOLO
from ultralytics.utils import DEFAULT_CFG
from ultralytics.cfg import get_cfg
from ultralytics.data.converter import coco80_to_coco91_class
from ultralytics.data.utils import check_det_dataset
from ultralytics.utils.metrics import ConfusionMatrix
import nncf

from common import download_file, save_openvino_models, validate_hash


def download_coco_dataset(dataset_dir: Union[str, Path], scripts_dir: Path) -> Path:
    print("\n[ Download ] Downloading COCO validation dataset.")
    
    DATA_URL = "http://images.cocodataset.org/zips/val2017.zip"
    LABELS_URL = "https://github.com/ultralytics/yolov5/releases/download/v1.0/coco2017labels-segments.zip"

    out_dir = Path(dataset_dir)

    data_path = out_dir / "val2017.zip"
    labels_path = out_dir / "coco2017labels-segments.zip"
    
    # Use local coco.yaml from scripts directory
    cfg_path = scripts_dir / "coco.yaml"

    if not (out_dir / "coco/labels").exists():
        download_file(DATA_URL, data_path.name, data_path.parent)
        download_file(LABELS_URL, labels_path.name, labels_path.parent)

        validate_hash(
            file_path=data_path,
            expected_hash="9ea554bcf9e6f88876b1157ab38247eb7c1c57564c05c7345a06ac479c6e7a3b9c3825150c189d7d3f2e807c95fd0e07fe90161c563591038e697c846ac76007",
        )

        validate_hash(
            file_path=labels_path,
            expected_hash="b7f85a6704f3eec97d2a90e01b2b88e7dc052697f17bed7d944d29634971a3087e37af306c84b8a71471d70b97769824150ff22c012c8bb122bd52e97977e37e",
        )
        
        print("[ Download ] Extracting dataset files.")
        with ZipFile(labels_path, "r") as zip_ref:
            # Only extract validation labels, not train/test
            val_files = [f for f in zip_ref.namelist() if 'val2017' in f or 'labels/val2017' in f]
            for file in val_files:
                zip_ref.extract(file, out_dir)
        with ZipFile(data_path, "r") as zip_ref:
            zip_ref.extractall(out_dir / "coco/images")
    
    return cfg_path


def download_yolo(model_name: str, models_dir: Path) -> tuple[Path, YOLO]:
    """Download YOLO model and test on sample image."""
    print(f"\n[ Download ] Downloading YOLO model: {model_name}")
    models_dir.mkdir(exist_ok=True)
    
    # Download and load YOLO model
    det_model = YOLO(models_dir / f"{model_name}.pt")
    det_model_path = models_dir / f"{model_name}_openvino_model/{model_name}.xml"
    
    # Download test image and run inference
    test_image = models_dir / "coco_bike.jpg"
    if not test_image.exists():
        print("[ Download ] Downloading test image.")
        download_file(
            "https://storage.openvinotoolkit.org/repositories/openvino_notebooks/data/data/image/coco_bike.jpg",
            "coco_bike.jpg",
            models_dir
        )
    
    print("[ Test ] Running test inference on sample image.")
    _ = det_model(test_image)
    
    return det_model_path, det_model


def convert_yolo_to_openvino(det_model: YOLO, det_model_path: Path) -> ov.Model:
    """Convert YOLO model to OpenVINO IR format."""
    if not det_model_path.exists():
        print("[ Conversion ] Converting YOLO model to OpenVINO format.")
        det_model.export(format="openvino", dynamic=True, half=True)
    
    core = ov.Core()
    det_ov_model = core.read_model(det_model_path)
    det_ov_model.reshape([1, 3, 640, 640])
    
    return det_ov_model


def setup_validator_and_dataloader(det_model: YOLO, cfg_path: Path, dataset_dir: Union[str, Path]):
    print("\n[ Setup ] Setting up validator and data loader.")
    
    args = get_cfg(cfg=DEFAULT_CFG)
    args.data = str(cfg_path)
    
    det_validator = det_model.task_map[det_model.task]["validator"](args=args)
    det_validator.data = check_det_dataset(args.data)
    det_validator.stride = 32
    det_data_loader = det_validator.get_dataloader(Path(dataset_dir) / "coco", 1)
    
    det_validator.is_coco = True
    det_validator.class_map = coco80_to_coco91_class()
    det_validator.names = det_model.model.names
    det_validator.metrics.names = det_validator.names
    det_validator.nc = det_model.model.model[-1].nc
    
    return det_validator, det_data_loader


def test_model_accuracy(
    model: ov.Model,
    core: ov.Core,
    data_loader: torch.utils.data.DataLoader,
    validator: Any,
    num_samples: Optional[int] = None,
    device: str = "CPU"
) -> Dict[str, float]:
    """
    OpenVINO YOLO model accuracy validation function. Runs model validation on dataset and returns metrics
    """
    print(f"\n[ Accuracy ] Testing model accuracy on {device}.")
    
    validator.seen = 0
    validator.jdict = []
    validator.stats = dict(tp=[], conf=[], pred_cls=[], target_cls=[], target_img=[])
    validator.batch_i = 1
    validator.confusion_matrix = ConfusionMatrix(nc=validator.nc)
    
    model.reshape({0: [1, 3, 640, 640]})
    ov_config = {}
    if "GPU" in device:
        ov_config = {"GPU_DISABLE_WINOGRAD_CONVOLUTION": "YES"}
    compiled_model = core.compile_model(model, device, ov_config)
    
    for batch_i, batch in enumerate(tqdm(data_loader, total=num_samples)):
        if num_samples is not None and batch_i == num_samples:
            break
        batch = validator.preprocess(batch)
        results = compiled_model(batch["img"])
        preds = torch.from_numpy(results[compiled_model.output(0)])
        preds = validator.postprocess(preds)
        validator.update_metrics(preds, batch)
    
    stats = validator.get_stats()
    return stats


def print_accuracy_stats(stats: Dict[str, float], total_images: int, total_objects: int):
    """
    Helper function for printing accuracy statistic
    """
    print("Boxes:")
    mp, mr, map50, mean_ap = (
        stats["metrics/precision(B)"],
        stats["metrics/recall(B)"],
        stats["metrics/mAP50(B)"],
        stats["metrics/mAP50-95(B)"],
    )
    
    print("    Best mean average:")
    s = ("%20s" + "%12s" * 6) % (
        "Class",
        "Images",
        "Labels",
        "Precision",
        "Recall",
        "mAP@.5",
        "mAP@.5:.95",
    )
    print(s)
    pf = "%20s" + "%12i" * 2 + "%12.3g" * 4
    print(pf % ("all", total_images, total_objects, mp, mr, map50, mean_ap))
    
    if "metrics/precision(M)" in stats:
        s_mp, s_mr, s_map50, s_mean_ap = (
            stats["metrics/precision(M)"],
            stats["metrics/recall(M)"],
            stats["metrics/mAP50(M)"],
            stats["metrics/mAP50-95(M)"],
        )
        print("    Macro average mean:")
        print(s)
        print(pf % ("all", total_images, total_objects, s_mp, s_mr, s_map50, s_mean_ap))


def quantize_yolo_model(
    fp32_model: ov.Model,
    data_loader: torch.utils.data.DataLoader,
    validator: Any,
    model_name: str,
    subset_size: int = 512
) -> ov.Model:
    print("\n[ Quantization ] Quantizing model to INT8.")
    
    def transform_fn(data_item: dict):
        """Quantization transform function. Extracts and preprocess input data from dataloader item for quantization."""
        input_tensor = validator.preprocess(data_item)['img'].numpy()
        return input_tensor

    quantization_dataset = nncf.Dataset(data_loader, transform_fn)
    
    # Define ignored scope for post-processing layers
    ignored_scope = nncf.IgnoredScope(
        subgraphs=[
            nncf.Subgraph(
                inputs=[
                    f"__module.model.{22 if 'v8' in model_name else 23}/aten::cat/Concat",
                    f"__module.model.{22 if 'v8' in model_name else 23}/aten::cat/Concat_1",
                    f"__module.model.{22 if 'v8' in model_name else 23}/aten::cat/Concat_2"
                ],
                outputs=[f"__module.model.{22 if 'v8' in model_name else 23}/aten::cat/Concat_7"]
            )
        ]
    )
    
    quantized_model = nncf.quantize(
        fp32_model,
        quantization_dataset,
        preset=nncf.QuantizationPreset.PERFORMANCE,
        ignored_scope=ignored_scope,
        subset_size=subset_size,
    )
    
    return quantized_model


def main(
    model_name: str = "yolo11n",
    dataset_dir: Optional[Union[str, Path]] = "datasets",
    samples: int = 512,
    subset_size: int = None,
    output_dir: Union[str, Path] = Path("models"),
    device: str = "CPU"
) -> None:

    print(f"[ Info ] Starting YOLO model conversion: {model_name}")
    
    # Setup directories
    dataset_dir = Path(dataset_dir).absolute()
    models_dir = Path("source-models")
    scripts_dir = Path(__file__).parent.parent / "scripts"
    output_dir = Path(output_dir) / model_name
    
    models_dir.mkdir(exist_ok=True)
    output_dir.mkdir(parents=True, exist_ok=True)
    subset_size = subset_size if subset_size is not None else samples

    det_model_path, det_model = download_yolo(model_name, models_dir)
    fp32_model = convert_yolo_to_openvino(det_model, det_model_path)
    cfg_path = download_coco_dataset(dataset_dir, scripts_dir)
    
    # Setup validator and data loader
    validator, data_loader = setup_validator_and_dataloader(det_model, cfg_path, dataset_dir)
    core = ov.Core()

    # Quantize model
    int8_model = quantize_yolo_model(
        fp32_model, data_loader, validator, model_name, subset_size
    )

    # Set model info
    fp32_model.set_rt_info('yolo_v11', ['model_info', 'model_type'])
    int8_model.set_rt_info('yolo_v11', ['model_info', 'model_type'])
    fp32_out, int8_out = save_openvino_models(
        fp32_model, int8_model, output_dir, prefix=model_name
    )

    print(f"\n[ Saved ] Saved FP32 model to {fp32_out}")
    print(f"[ Saved ] Saved INT8 model to {int8_out}")

    # Test FP32 accuracy
    fp32_stats = test_model_accuracy(
        fp32_model, core, data_loader, validator, 
        num_samples=samples, device=device
    )

    # Test INT8 accuracy
    int8_stats = test_model_accuracy(
        int8_model, core, data_loader, validator, 
        num_samples=samples, device=device
    )
    
    # Print results
    print("\n[Summary]")
    print("FP32 model accuracy:")
    print_accuracy_stats(fp32_stats, validator.seen, validator.nt_per_class.sum())
    
    print("\nINT8 model accuracy:")
    print_accuracy_stats(int8_stats, validator.seen, validator.nt_per_class.sum())


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="NNCF INT8 Quantizer for YOLOv11 models")
    ap.add_argument(
        "-m",
        "--model-name",
        default="yolo11m",
        help="YOLO model name (default: yolo11m).",
    )
    ap.add_argument(
        "-i",
        "--dataset-dir",
        default="./datasets",
        help="Directory for COCO dataset. Automatically downloads if not on system.",
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
        default=str(Path("models/yolo")),
        help="Directory to save converted models (default: models).",
    )
    ap.add_argument(
        "--device",
        default="CPU",
        help="Device for inference testing (default: CPU).",
    )
    args = ap.parse_args()

    main(
        model_name=args.model_name,
        dataset_dir=args.dataset_dir,
        samples=args.calib_subset,
        subset_size=args.subset_size,
        output_dir=args.output_dir,
        device=args.device,
    )
