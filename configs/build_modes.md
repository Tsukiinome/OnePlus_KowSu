# KowSu vs KernelSU-Next Build Modes Guide

## 🔄 Comparison Table

| Feature | KernelSU-Next (GKI) | KowSu (LKM) |
|---------|-------------------|-----------|
| **Mode** | Generic Kernel Image | Loadable Kernel Module |
| **Integration** | Patched into boot.img | Dynamically loaded kernel module |
| **SUSFS Support** | Required/Integrated | Not used/Not compatible |
| **Compilation Target** | boot.img + vendor_boot | kernelsu.ko module file |
| **Device Support** | GKI 2.0+ devices (kernel 5.10+) | Custom kernels (any version) |
| **Load Method** | Integrated at boot | Loaded by init/Manager at runtime |
| **Manager Role** | Control interface | Must load .ko module |
| **Performance** | Kernel-integrated | Module overhead but flexible |
| **Update Method** | Full boot image replacement | Single .ko file replacement |
| **Supported Architectures** | arm64-v8a, x86_64 | arm64-v8a (primary focus) |

---

## 📋 Build Process: KernelSU-Next (GKI)

### Prerequisites
```bash
# Environment setup
ANDROID_SDK_HOME="/path/to/android-sdk"
ANDROID_NDK_HOME="/path/to/ndk/26"
KERNEL_SOURCE="/path/to/kernel" # OnePlus official GKI kernel
```

### Step-by-step build
```bash
# 1. Clone GKI KernelSU-Next
git clone https://github.com/KernelSU-Next/KernelSU-Next.git
cd KernelSU-Next

# 2. Build boot image with SUSFS integration
./build.sh gki all

# 3. Outputs
#   - boot.img (with integrated KSU + SUSFS)
#   - vendor_boot.img (system partition patches)
#   - Manager APK

# 4. Flash to device
adb reboot bootloader
fastboot flash boot boot.img
fastboot flash vendor_boot vendor_boot.img
```

### Configuration
- SUSFS patches applied to kernel
- Kernel modules precompiled
- Single unified boot image

---

## 📋 Build Process: KowSu (LKM)

### Prerequisites
```bash
# Environment setup (same as KowSu fork)
ANDROID_SDK_HOME="/path/to/android-sdk"
ANDROID_NDK_HOME="/path/to/ndk/26"
KERNEL_SOURCE="/path/to/OnePlus_KowSu" # Your fork
CONTAINER_RUNTIME="docker" or "podman" # For DDK compilation
```

### Step-by-step build
```bash
# 1. Clone OnePlus_KowSu fork
git clone https://github.com/Tsukiinome/OnePlus_KowSu.git
cd OnePlus_KowSu

# 2. Source KowSu configuration
source configs/kowsu_build_config.sh

# 3. Build KernelSU.ko module (LKM)
./build_kowsu.sh --device space --kmi android15

# 4. Outputs
#   - kernelsu.ko (module file)
#   - ksuinit (binary)
#   - ksud (daemon)
#   - Manager APK

# 5. Create flashable ZIP with .ko module
# (Uses AnyKernel3 or custom script)
# ZIP structure:
# ├── kernelsu.ko
# ├── install.sh (insmod kernelsu.ko)
# ├── ksuinit
# ├── ksud
# └── META-INF/

# 6. Flash to device
adb reboot bootloader
# Use custom recovery to flash ZIP
```

### Configuration
- No SUSFS patches needed
- Kernel compiled with CONFIG_KSU=m
- Module loaded dynamically
- Device-specific compilation

---

## 🛠️ Kernel Configuration

### GKI Mode (KernelSU-Next)
```makefile
# .config for GKI kernel
CONFIG_KSU=y              # Built-in, not module
CONFIG_HAVE_UNIX98_PTYS=y
CONFIG_DEVPTS_FS=y
CONFIG_SUSFS=y            # SUSFS patches integrated
CONFIG_SUSFS_SUS_PATH=y
CONFIG_SUSFS_SUS_MOUNT=y
```

### LKM Mode (KowSu)
```makefile
# .config for LKM kernel
CONFIG_KSU=m              # Loadable module
CONFIG_HAVE_UNIX98_PTYS=y
CONFIG_DEVPTS_FS=y
CONFIG_SUSFS=n            # NOT included
# Module loaded after boot by init
```

---

## 📦 Build Artifacts

### KernelSU-Next (GKI) Produces
```
out/
├── boot.img              # Patched boot image with integrated KSU
├── vendor_boot.img       # Vendor boot modifications
├── dtbo.img              # Device tree overlay (if needed)
└── Manager-vX.X.X.apk    # Manager application
```

### KowSu (LKM) Produces
```
out/kowsu/
├── modules/
│   └── android15_kernelsu.ko    # Compiled kernel module
├── artifacts/
│   ├── ksuinit                  # Init binary
│   ├── ksud                     # Userspace daemon (aarch64)
│   └── Manager-vX.X.X.apk      # Manager application
└── logs/
    ├── android15.log            # Build log
    └── manager.log              # APK build log
```

---

## 🔧 Troubleshooting

### GKI Build Issues
| Issue | Cause | Solution |
|-------|-------|----------|
| SUSFS patches fail | Kernel version mismatch | Use matching branch for kernel version |
| boot.img too large | Too many patches | Reduce patches or use smaller flags |
| Device won't boot | Incompatible GKI kernel | Verify device GKI support |

### LKM Build Issues
| Issue | Cause | Solution |
|-------|-------|----------|
| kernelsu.ko fails to load | Missing kernel config | Verify CONFIG_KSU=m set |
| Manager can't find .ko | Path incorrect | Check /system/lib/modules/ or custom path |
| KowSu daemon crashes | Userspace binary mismatch | Recompile ksud for target architecture |

---

## 📚 References

- **KernelSU Official**: https://kernelsu.org/
- **KernelSU-Next**: https://github.com/KernelSU-Next/KernelSU-Next
- **KowSu**: https://github.com/KOWX712/KernelSU
- **SUSFS**: https://gitlab.com/simonpunk/susfs4ksu
- **OnePlus Kernel Sources**: https://github.com/OnePlusOSS/

---

## ⚡ Quick Reference

### For GKI devices (KernelSU-Next)
```bash
# Single command full build
./build.sh gki all
```

### For LKM devices (KowSu)
```bash
# Build specific device
./build_kowsu.sh --device space --all

# Or specific KMI
./build_kowsu.sh --device space --kmi android15
```

---

## 📝 Important Notes

1. **KowSu requires DDK (Android Kernel Development Kit)**
   - Uses Docker/Podman containers
   - Automatically pulls DDK images
   - Network access required for first build

2. **GKI mode automatically includes SUSFS**
   - SUSFS cannot be disabled in KernelSU-Next
   - Adds /data/adb/modules/ overlay support

3. **LKM mode is more flexible**
   - Can update kernel module without full boot image
   - Better for kernel development
   - Requires runtime module loading

4. **Both use KowSu Manager**
   - Same APK can work with both modes
   - Different kernel communication mechanisms
   - Material design interface for KowSu branch
