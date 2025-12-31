# Model Conversion and Quantization

Download, convert, and quantize AI models for Deep Learning Streamer (DL Streamer) pipelines.

### Model Collateral Matrix

| Model Name   | Task           | Dimensions     | Dataset  | Source Model |
|--------------|----------------|----------------|----------|--------------|
| Yolo-v11n    | Detection      | 640x640 (INT8) | COCO     | [source](https://docs.ultralytics.com/models/yolo11/)   |
| Yolo-v11m    | Detection      | 640x640 (INT8) | COCO     | [source](https://docs.ultralytics.com/models/yolo11/)   |
| Yolo-v5m     | Detection      | 640x640 (INT8) | COCO     | [source](https://github.com/dlstreamer/pipeline-zoo-models/tree/main/storage/yolov5m-640_INT8)   |
| Resnet-50    | Classification | 224x224 (INT8) | ImageNet | [source](https://www.kaggle.com/models/google/resnet-v1/tensorFlow2/50-classification/)   |
| Mobilenet-V2 | Classification | 224x224 (INT8) | ImageNet | [source](https://pytorch.org/hub/pytorch_vision_mobilenet_v2/)   |

### Usage

```bash
./convert_models.sh
```

## ImageNet Accuracy Check for Classification Networks (Optional)

The CIFAR dataset is used as a proxy dataset for classification network quantization. For classification accuracy validation, the ImageNet dataset is required.

### ImageNet Dataset Setup

1. Register at https://www.image-net.org/download.php
2. Download files:
   - `ILSVRC2012_devkit_t12.tar.gz` (2.5MB)
   - `ILSVRC2012_img_val.tar` (6.3GB)
3. Place in directory:
   ```bash
   ${Path-to-datasets}/datasets/imagenet-packages/
   ├── ILSVRC2012_devkit_t12.tar.gz
   └── ILSVRC2012_img_val.tar
   ```
   Keep the files as tar and tar.gz files.

```bash
./convert_models.sh -i "${Path-to-datasets}/datasets/imagenet-packages"
```

## Output Structure

Models are saved in the following pipeline configurations:

```
pipelines/
├── light/
│   ├── detection/
│   │   └── yolov11n_640x640/INT8/
│   └── classification/
│       └── resnet-v1-50-tf/INT8/
├── medium/
│   ├── detection/
│   │   └── yolov5m_640x640/INT8/
│   └── classification/
│       ├── resnet-v1-50-tf/INT8/
│       └── mobilenet-v2-1.0-224-tf/INT8/
└── heavy/
    ├── detection/
    │   └── yolov11m_640x640/INT8/
    └── classification/
        ├── resnet-v1-50-tf/INT8/
        └── mobilenet-v2-1.0-224-tf/INT8/
```
