#!/bin/bash

################################################################################
# KowSu Build Script - LKM Compilation for OnePlus Kernels
#
# This script compiles KowSu (KernelSU in LKM mode) for OnePlus devices.
# It handles kernel module compilation, userspace binaries, and APK building.
#
# USAGE:
#   ./build_kowsu.sh --device space --kmi android15 --all
#   ./build_kowsu.sh --device <device> [--kmi <version>] [--module|--daemon|--all]
#   ./build_kowsu.sh --list          # List supported devices
#   ./build_kowsu.sh --clean         # Clean build artifacts
#
# REQUIREMENTS:
#   - Docker or Podman installed
#   - Rust toolchain
#   - Android NDK
#   - Gradle (for APK building)
################################################################################

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load configuration
if [[ -f "configs/kowsu_build_config.sh" ]]; then
    source configs/kowsu_build_config.sh
else
    echo -e "${RED}[✗] Error: configs/kowsu_build_config.sh not found${NC}"
    exit 1
fi

# ================== Variables ==================
DEVICE=""
KMI=""
BUILD_MODULE=0
BUILD_DAEMON=0
BUILD_APK=0
BUILD_ALL=0
CLEAN_BUILD=0
LIST_DEVICES=0
VERBOSE=0

# ================== Functions ==================

print_help() {
    cat << EOF
${BLUE}KowSu Build Script - LKM Compilation${NC}

${YELLOW}USAGE:${NC}
  ./build_kowsu.sh --device <device> [OPTIONS]

${YELLOW}OPTIONS:${NC}
  --device <device>    Target device (required). Use --list to see all devices
  --kmi <version>      Android version (default: auto-detect from device)
                       Options: android12, android13, android14, android15, android16
  --module             Build only kernel module (.ko)
  --daemon             Build only userspace daemon (ksud)
  --apk                Build only Manager APK
  --all                Build everything (default)
  --list               List all supported devices
  --clean              Clean all build artifacts
  --verbose            Enable verbose output
  --help               Show this help message

${YELLOW}EXAMPLES:${NC}
  # Build everything for OnePlus13
  ./build_kowsu.sh --device OnePlus13 --all

  # Build only kernel module
  ./build_kowsu.sh --device OnePlus13 --module

  # Build for specific KMI version
  ./build_kowsu.sh --device OnePlus13 --kmi android15 --all

  # List supported devices
  ./build_kowsu.sh --list

  # Clean build artifacts
  ./build_kowsu.sh --clean

${YELLOW}BUILD PROCESS:${NC}
  1. Validates device and KMI version
  2. Sets up Docker/Podman environment
  3. Compiles kernelsu.ko using DDK
  4. Compiles ksuinit and ksud
  5. Builds Manager APK
  6. Creates flashable artifacts

${YELLOW}OUTPUT:${NC}
  out/kowsu/
  ├── modules/       # Compiled .ko files
  ├── artifacts/     # Final build outputs
  └── logs/          # Build logs

EOF
}

log_info() {
    echo -e "${BLUE}[*]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $*"
}

log_error() {
    echo -e "${RED}[✗]${NC} $*" >&2
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $*"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --device)
                DEVICE="$2"
                shift 2
                ;;
            --kmi)
                KMI="$2"
                shift 2
                ;;
            --module)
                BUILD_MODULE=1
                shift
                ;;
            --daemon)
                BUILD_DAEMON=1
                shift
                ;;
            --apk)
                BUILD_APK=1
                shift
                ;;
            --all)
                BUILD_ALL=1
                shift
                ;;
            --clean)
                CLEAN_BUILD=1
                shift
                ;;
            --list)
                LIST_DEVICES=1
                shift
                ;;
            --verbose)
                VERBOSE=1
                shift
                ;;
            --help|-h)
                print_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_help
                exit 1
                ;;
        esac
    done
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating build prerequisites..."
    
    local issues=0
    
    # Check container runtime
    if [[ -z "$CONTAINER_RUNTIME" ]]; then
        log_error "No container runtime (Docker/Podman) found"
        issues=$((issues + 1))
    else
        log_success "Container runtime: $CONTAINER_RUNTIME"
    fi
    
    # Check Rust
    if ! command -v rustc &> /dev/null; then
        log_error "Rust compiler not found"
        issues=$((issues + 1))
    else
        log_success "Rust compiler found: $(rustc --version)"
    fi
    
    # Check Cargo
    if ! command -v cargo &> /dev/null; then
        log_error "Cargo not found"
        issues=$((issues + 1))
    else
        log_success "Cargo found"
    fi
    
    # Check Gradle
    if ! command -v gradle &> /dev/null && [[ ! -f "manager/gradlew" ]]; then
        log_error "Gradle not found"
        issues=$((issues + 1))
    else
        log_success "Gradle found"
    fi
    
    if [[ $issues -gt 0 ]]; then
        log_error "$issues prerequisite(s) missing"
        return 1
    fi
    
    log_success "All prerequisites satisfied"
    return 0
}

# Build kernel module
build_module() {
    local device="$1"
    local kmi="$2"
    
    log_info "Building kernel module for $device ($kmi)..."
    
    if ! validate_kmi "$kmi" &>/dev/null; then
        log_error "Invalid KMI: $kmi"
        return 1
    fi
    
    setup_build_env "$kmi"
    
    local logfile="${LOGS_DIR}/${device}_${kmi}.log"
    
    {
        log_info "Compiling kernelsu.ko with DDK..."
        
        if [[ -z "$CONTAINER_RUNTIME" ]]; then
            log_error "Container runtime not available"
            return 1
        fi
        
        $CONTAINER_RUNTIME run --rm --privileged \
            -v "$(pwd):/workspace:z" \
            -w /workspace \
            "${DDK_IMAGE_BASE}:${kmi}-22" /bin/bash -c "
                set -e
                git config --global --add safe.directory /workspace
                cd kernel
                export ${COMPILER_FLAGS[@]}
                ${KOWSU_BUILD_FLAGS[@]/%/\\n}
                CONFIG_KSU=m CC=clang make -j\$(nproc)
                cp -f kernelsu.ko ../out/kowsu/modules/${device}_${kmi}_kernelsu.ko
                echo 'Module built: kernelsu.ko'
            " || return 1
        
        log_success "Module compiled: kernelsu.ko"
        
    } | tee "$logfile" 2>&1
    
    return $?
}

# Build userspace daemon
build_daemon() {
    local device="$1"
    local kmi="$2"
    
    log_info "Building userspace daemon (ksud)..."
    
    setup_build_env "$kmi"
    
    local logfile="${LOGS_DIR}/${device}_ksud.log"
    
    {
        log_info "Building ksuinit..."
        rustup target add aarch64-unknown-linux-musl 2>/dev/null || true
        export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER="$(command -v clang)"
        RUSTFLAGS="-C link-arg=-no-pie" cargo build \
            --package ksuinit \
            --target aarch64-unknown-linux-musl \
            --release \
            --manifest-path ./userspace/ksuinit/Cargo.toml || return 1
        
        cp target/aarch64-unknown-linux-musl/release/ksuinit \
            out/kowsu/artifacts/ksuinit_${kmi}
        
        log_success "ksuinit compiled"
        
        log_info "Building ksud..."
        rustup target add aarch64-linux-android 2>/dev/null || true
        cargo build \
            --target aarch64-linux-android \
            --release \
            --manifest-path ./userspace/ksud/Cargo.toml || return 1
        
        cp target/aarch64-linux-android/release/ksud \
            out/kowsu/artifacts/ksud_${kmi}
        
        log_success "ksud compiled"
        
    } | tee "$logfile" 2>&1
    
    return $?
}

# Build Manager APK
build_apk() {
    log_info "Building Manager APK..."
    
    local logfile="${LOGS_DIR}/manager_build.log"
    
    {
        cd manager
        ./gradlew aRelease || return 1
        cd ..
        
        cp manager/app/release/*.apk out/kowsu/artifacts/ 2>/dev/null || true
        
        log_success "Manager APK built"
        
    } | tee "$logfile" 2>&1
    
    return $?
}

# Main build function
run_build() {
    # Validate prerequisites
    if ! validate_prerequisites; then
        return 1
    fi
    
    # Validate device and KMI
    if [[ -z "$DEVICE" ]]; then
        log_error "Device not specified"
        return 1
    fi
    
    if ! get_device_info "$DEVICE" &>/dev/null; then
        log_error "Device '$DEVICE' not found"
        return 1
    fi
    
    # Auto-detect KMI if not specified
    if [[ -z "$KMI" ]]; then
        KMI=$(get_android_version "$DEVICE")
        log_info "Auto-detected KMI: $KMI"
    fi
    
    # Default to build all if no specific component selected
    if [[ $BUILD_MODULE -eq 0 && $BUILD_DAEMON -eq 0 && $BUILD_APK -eq 0 && $BUILD_ALL -eq 0 ]]; then
        BUILD_ALL=1
    fi
    
    # Build selected components
    local failed=0
    
    if [[ $BUILD_MODULE -eq 1 || $BUILD_ALL -eq 1 ]]; then
        if ! build_module "$DEVICE" "$KMI"; then
            log_error "Failed to build module"
            failed=$((failed + 1))
        fi
    fi
    
    if [[ $BUILD_DAEMON -eq 1 || $BUILD_ALL -eq 1 ]]; then
        if ! build_daemon "$DEVICE" "$KMI"; then
            log_error "Failed to build daemon"
            failed=$((failed + 1))
        fi
    fi
    
    if [[ $BUILD_APK -eq 1 || $BUILD_ALL -eq 1 ]]; then
        if ! build_apk; then
            log_error "Failed to build APK"
            failed=$((failed + 1))
        fi
    fi
    
    if [[ $failed -eq 0 ]]; then
        log_success "Build completed successfully!"
        log_info "Artifacts located in: ${KOWSU_OUTPUT_DIR}/artifacts/"
        return 0
    else
        log_error "Build failed with $failed error(s)"
        return 1
    fi
}

# ================== Main ==================

# Parse arguments
parse_args "$@"

# Handle special commands
if [[ $CLEAN_BUILD -eq 1 ]]; then
    log_info "Cleaning build artifacts..."
    cleanup_build
    log_success "Cleanup complete"
    exit 0
fi

if [[ $LIST_DEVICES -eq 1 ]]; then
    list_devices
    exit 0
fi

# Run main build
if ! run_build; then
    exit 1
fi

exit 0
