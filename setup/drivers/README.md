# Compute Driver Installation Scripts

Intel has validated the GPU and NPU compute drivers in terms of performance reproducibility, for Edge Workloads and Benchmarks.

## Usage

### GPU Driver Installation
```bash
./install_gpu_driver.sh
```

**Specifications:**
- GPU Driver Version: 25.27.34303.5

### NPU Driver Installation  
```bash
./install_npu_driver.sh
```

**Specifications:**
- NPU Driver Version: 1.23.0
- Level Zero: 1.22.4


## Directory Structure

```
drivers/
├── gpu/
│   └── 25.27.34303.5/          # Downloaded GPU driver packages
└── npu/
    └── v1.23.0/                # Downloaded NPU driver packages
```

Downloaded packages are saved locally for offline reinstallation.

## Integration with the Main Prerequisite Script

Driver installation is **optional** by default. The main `install_prerequisites.sh` script does not automatically install drivers to maintain system stability.

Use these dedicated scripts or the `install_prerequisites.sh` script with the `--reinstall-gpu-driver=yes` / `--reinstall-npu-driver=yes` flags to install the compute drivers.
