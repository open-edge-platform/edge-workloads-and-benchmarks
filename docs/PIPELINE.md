# Edge AI Pipeline Architecture

## Pipeline Architecture

HEVC 1080p Video Decode (GPU Hardware-Accelerated) → Object Detection (GPU or NPU) → Object Tracking → 1-2x Object Classification (GPU or NPU)

## Pipeline Configurations

| Config | Video | Objects per Frame | Detection | Classification #1 | Classification #2 |
|--------|-------|-------------------|-----------|-------------------|-------------------|
| light  | bears_1080.h265 | 2 | YOLOv11n (640x640) INT8 | ResNet‑50 (224x224) INT8 | N/A |
| medium | apple_1080.h265 | 1 | YOLOv5m (640x640) INT8  | ResNet‑50 (224x224) INT8 | MobileNet‑V2 (224x224) INT8 |
| heavy  | bears_1080.h265 | 2 | YOLOv11m (640x640) INT8 | ResNet‑50 (224x224) INT8 | MobileNet‑V2 (224x224) INT8 |

## Device Configurations

Pipeline configurations include single-device pipelines (GPU or NPU only), pipelines with multiple devices (GPU Detect and NPU Classify "split"), and multiple single-device pipelines running concurrently in separate processes (GPU only and NPU only, "concurrent"). Please refer to the following naming convention:

| Name | Detect Device | Classify Device | Concurrent GST-Launch Processes |
|------|---------------|-----------------|---------------------------------|
| GPU-Only | GPU | GPU | No (All streams in single GST-Launch)
| NPU-Only | NPU | NPU | No (All streams in single GST-Launch)
| Split    | GPU | NPU | No (All streams in single GST-Launch)
| Concurrent | GPU + NPU | GPU + NPU | Yes (Separate GPU-Only streams and NPU-only streams)
