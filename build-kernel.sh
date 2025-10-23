#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log() {
    echo -e "${BLUE}[*]${NC} $1"
}

error() {
    echo -e "${RED}[!]${NC} $1"
    exit 1
}

success() {
    echo -e "${GREEN}[+]${NC} $1"
}

# Parse command line arguments
INTERACTIVE=1
while getopts "y" opt; do
    case $opt in
        y)
            INTERACTIVE=0
            ;;
        \?)
            error "Invalid option: -$OPTARG"
            ;;
    esac
done

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    error "Please don't run as root"
fi

# Configuration
KERNEL_TARGET="sun"
KERNEL_VARIANT="gki"
BUILD_TYPE="user"
WORKING_DIR="$(pwd)/nord4"
ANYKERNEL_BRANCH="gki-2.0"

# Check for required tools
REQUIRED_TOOLS="git curl make gcc bc bison flex perl zip python3"
for tool in $REQUIRED_TOOLS; do
    if ! command -v $tool >/dev/null 2>&1; then
        error "$tool is required but not installed. Please install it first."
    fi
done

# Clean up function
cleanup() {
    log "Cleaning up previous build artifacts..."
    rm -rf "$WORKING_DIR"
    rm -rf AnyKernel3
    rm -rf susfs4ksu
    rm -rf kernel_patches
    rm -rf git-repo
    rm -f *.zip
}

# Handle cleanup based on interactive mode
if [ -d "$WORKING_DIR" ]; then
    if [ $INTERACTIVE -eq 1 ]; then
        read -p "Previous build directory found. Clean and start fresh? [Y/n] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
            cleanup
        fi
    else
        cleanup
    fi
fi

# Clone required repositories
log "Cloning required repositories..."
if [ ! -d "AnyKernel3" ]; then
    git clone https://github.com/TheWildJames/AnyKernel3.git -b "$ANYKERNEL_BRANCH"
fi

# Install repo tool if not present
log "Installing repo tool..."
if [ ! -f "./git-repo/repo" ]; then
    mkdir -p ./git-repo
    curl https://storage.googleapis.com/git-repo-downloads/repo > ./git-repo/repo
    chmod a+rx ./git-repo/repo
fi

# Create and enter working directory
log "Setting up working directory..."
mkdir -p "$WORKING_DIR"
cd "$WORKING_DIR" || error "Failed to enter working directory"

# Initialize and sync kernel source
log "Initializing and syncing kernel source..."
../git-repo/repo init -u https://github.com/OnePlusOSS/kernel_manifest.git -b oneplus/sm7675 -m oneplus_nord_4_v.xml --repo-rev=v2.16 --depth=1
../git-repo/repo sync -c -j$(nproc --all) --no-tags --fail-fast

# Add KernelSU
log "Adding KernelSU..."
cd kernel_platform || error "Failed to enter kernel_platform directory"
git clone https://github.com/tiann/KernelSU -b main KernelSU
rm -f KernelSU/kernel/kernel

# Configure KernelSU and kernel tree
log "Configuring KernelSU..."
mkdir -p common/drivers/kernelsu
ln -sf $(pwd)/KernelSU/kernel $(pwd)/common/drivers/kernelsu
echo "obj-y += kernelsu/" >> common/drivers/Makefile
echo "source \"drivers/kernelsu/Kconfig\"" >> common/drivers/Kconfig
sed -i 's/ccflags-y += -DKSU_VERSION=16/ccflags-y += -DKSU_VERSION=12321/' KernelSU/kernel/Makefile

# Add KernelSU configuration
log "Adding KernelSU configuration..."
echo "CONFIG_KSU=y" >> common/arch/arm64/configs/gki_defconfig

# Setup build environment
log "Setting up build environment..."
export TARGET_BUILD_VARIANT=$BUILD_TYPE
export ANDROID_BUILD_TOP="$(pwd)/.."
export TARGET_BOARD_PLATFORM=$KERNEL_TARGET

# Build the kernel
log "Building the kernel..."
cd common || error "Failed to enter common directory"
make O=out ARCH=arm64 gki_defconfig
make O=out ARCH=arm64 -j$(nproc --all)

# Create final ZIP
log "Creating final ZIP..."
cd ../..
mkdir -p out/msm-kernel-$KERNEL_TARGET-$KERNEL_VARIANT/dist
cp kernel_platform/common/out/arch/arm64/boot/Image ../../AnyKernel3/
cd ../../AnyKernel3
zip -r9 "../Anykernel3-OPNord4-KernelSU.zip" ./*

cd ..
success "Build completed! Check Anykernel3-OPNord4-KernelSU.zip"
