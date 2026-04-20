# Compute Driver Installation Scripts
GPU and NPU compute drivers required for device-specific benchmarks.

## Usage

### GPU Driver Installation
```bash
./install_gpu_driver.sh
```

**Specifications:**
- GPU Driver Version: 26.09.37435.1
- IGC Version: 2.30.1

### NPU Driver Installation  
```bash
./install_npu_driver.sh
```

**Specifications:**
- NPU Driver Version: v1.32.0
- Level Zero: 1.27.0
- Requires Ubuntu 24.04


## Directory Structure
Downloaded packages are saved locally for offline reinstallation.
```
drivers/
├── gpu/
│   └── 26.09.37435.1/          # Downloaded GPU driver packages
└── npu/
    └── v1.32.0/                # Downloaded NPU driver packages
```